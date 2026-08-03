import 'package:flutter/material.dart';
import 'package:crm_app/theme/app_theme.dart';
import 'package:crm_app/widgets/app_toast.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crm_app/utils/store_utils.dart';

final supabase = Supabase.instance.client;

class RecycleBinPage extends StatefulWidget {
  final String role;
  final ValueChanged<String>? onNavigateToPage;

  const RecycleBinPage({
    super.key,
    required this.role,
    this.onNavigateToPage,
  });

  @override
  State<RecycleBinPage> createState() => _RecycleBinPageState();
}

class _RecycleBinPageState extends State<RecycleBinPage> {
  final searchController = TextEditingController();
  final dateTimeFormat = DateFormat('yyyy-MM-dd HH:mm');
  List<Map<String, dynamic>> records = [];
  bool isLoading = true;
  bool isRestoring = false;
  String selectedTable = '전체';
  String selectedPeriod = '전체';

  bool get isAdmin => isPrivilegedRole(widget.role);

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    fetchRecords();
  }

  Future<void> fetchRecords() async {
    if (!isAdmin) {
      setState(() => isLoading = false);
      return;
    }

    setState(() => isLoading = true);
    try {
      final data = await supabase.rpc('crm_deleted_records');
      if (!mounted) return;
      setState(() {
        records = List<Map<String, dynamic>>.from(data);
      });
    } catch (e) {
      debugPrint('recycle bin load failed: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> restoreRecord(Map<String, dynamic> record) async {
    if (isRestoring) return;
    setState(() => isRestoring = true);
    try {
      await supabase.rpc('restore_crm_record', params: {
        'target_table': record['target_table'],
        'target_id': record['target_id'],
      });
      if (!mounted) return;
      _showRestoreMessage(record);
      await fetchRecords();
    } catch (e) {
      debugPrint('restore failed: $e');
      if (mounted) _showMessage('복구 실패: $e');
    } finally {
      if (mounted) setState(() => isRestoring = false);
    }
  }

  void _showMessage(String text) {
    showToast(context, text);
  }

  String _tableLabel(dynamic value) {
    return switch (value?.toString()) {
      'customers' => '고객DB',
      'leads' => '가망고객',
      'wired_members' => '유선회원',
      'device_inventory' => '재고관리',
      _ => value?.toString() ?? '-',
    };
  }

  String _targetPageTitle(dynamic value) {
    return switch (value?.toString()) {
      'customers' => '고객DB',
      'leads' => '가망고객',
      'wired_members' => '유선회원',
      'device_inventory' => '재고관리',
      _ => '',
    };
  }

  String _value(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? '-' : text;
  }

  String _dateLabel(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    return date == null ? '-' : dateTimeFormat.format(date);
  }

  DateTime? _deletedDate(Map<String, dynamic> record) {
    return DateTime.tryParse(record['deleted_at']?.toString() ?? '')?.toLocal();
  }

  String _deletedAgeLabel(Map<String, dynamic> record) {
    final deletedAt = _deletedDate(record);
    if (deletedAt == null) return '삭제일 확인 필요';
    final days = DateTime.now().difference(deletedAt).inDays;
    if (days <= 0) return '오늘 삭제';
    return '삭제 후 $days일';
  }

  bool _matchesPeriod(Map<String, dynamic> record) {
    if (selectedPeriod == '전체') return true;
    final deletedAt = _deletedDate(record);
    if (deletedAt == null) return false;
    final days = DateTime.now().difference(deletedAt).inDays;
    return switch (selectedPeriod) {
      '오늘' => days <= 0,
      '7일' => days <= 7,
      '30일' => days <= 30,
      _ => true,
    };
  }

  List<Map<String, dynamic>> get filteredRecords {
    final query = searchController.text.trim().toLowerCase();
    return records.where((record) {
      final matchesTable = selectedTable == '전체' ||
          _tableLabel(record['target_table']) == selectedTable;
      if (!matchesTable || !_matchesPeriod(record)) return false;
      if (query.isEmpty) return true;
      final haystack = [
        record['title'],
        record['subtitle'],
        record['store'],
        record['deleted_by_name'],
        record['join_date'],
        record['model'],
        _tableLabel(record['target_table']),
      ].map(_value).join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  int _countTable(String label) {
    if (label == '전체') return records.length;
    return records
        .where((record) => _tableLabel(record['target_table']) == label)
        .length;
  }

  Future<void> confirmRestore(Map<String, dynamic> record) async {
    final shouldRestore = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            title: const Text(
              '삭제자료 복구',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            content: SizedBox(
              width: 420,
              child: Text(
                '${_tableLabel(record['target_table'])}의 '
                '${_value(record['title'])} 자료를 복구할까요?\n\n'
                '매장: ${_value(record['store'])}\n'
                '정보: ${_value(record['subtitle'])}\n'
                '삭제일: ${_dateLabel(record['deleted_at'])}',
                style: const TextStyle(height: 1.45),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소'),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.restore_rounded, size: 18),
                label: const Text('복구'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF111827),
                  foregroundColor: Colors.white,
                  elevation: 0,
                ),
              ),
            ],
          ),
        ) ??
        false;
    if (!shouldRestore) return;
    await restoreRecord(record);
  }

  void _showRestoreMessage(Map<String, dynamic> record) {
    final pageTitle = _targetPageTitle(record['target_table']);
    // 액션 버튼이 필요해 showToast 대신 SnackBar 직접 사용 (스타일은 테마가 적용).
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${_tableLabel(record['target_table'])} 자료를 복구했습니다.'),
        action: pageTitle.isEmpty || widget.onNavigateToPage == null
            ? null
            : SnackBarAction(
                label: '$pageTitle 보기',
                onPressed: () => widget.onNavigateToPage!(pageTitle),
              ),
      ),
    );
  }

  Widget _filterChip(String label, String value, ValueChanged<String> onTap) {
    final selected = label == value;
    return ChoiceChip(
      label: Text(label == '전체'
          ? '전체 ${records.length}'
          : '$label ${_countTable(label)}'),
      selected: selected,
      onSelected: (_) => setState(() => onTap(label)),
    );
  }

  Widget _periodChip(String label) {
    return ChoiceChip(
      label: Text(label),
      selected: selectedPeriod == label,
      onSelected: (_) => setState(() => selectedPeriod = label),
    );
  }

  Widget _recordTile(Map<String, dynamic> record, {required bool mobile}) {
    final restoreButton = OutlinedButton.icon(
      onPressed: isRestoring ? null : () => confirmRestore(record),
      icon: const Icon(Icons.restore_rounded, size: 18),
      label: const Text('복구'),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE8E9EF)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1F2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.restore_from_trash_rounded,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _tableLabel(record['target_table']),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF374151),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _value(record['title']),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF111827),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  [
                    if ((record['store']?.toString().trim() ?? '').isNotEmpty)
                      '매장: ${record['store']}',
                    if ((record['subtitle']?.toString().trim() ?? '')
                        .isNotEmpty)
                      '정보: ${record['subtitle']}',
                    if ((record['join_date']?.toString().trim() ?? '')
                        .isNotEmpty)
                      '가입일: ${record['join_date']}',
                    if ((record['model']?.toString().trim() ?? '').isNotEmpty)
                      '모델: ${record['model']}',
                    '삭제자: ${_value(record['deleted_by_name'])}',
                    '삭제일: ${_dateLabel(record['deleted_at'])}',
                    _deletedAgeLabel(record),
                  ].join(' · '),
                  maxLines: mobile ? 3 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (mobile) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: restoreButton,
                  ),
                ],
              ],
            ),
          ),
          if (!mobile) ...[
            const SizedBox(width: 12),
            restoreButton,
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.of(context).size.width < 760;
    final rows = filteredRecords;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(mobile ? 14 : 28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE8E9EF)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '삭제자료 복구',
                          style: TextStyle(
                            color: Color(0xFF111827),
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '새로고침',
                        onPressed: fetchRecords,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '삭제된 고객DB, 가망고객, 유선회원, 재고를 확인하고 필요한 자료만 복구합니다.',
                    style: TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 42,
                    child: TextField(
                      controller: searchController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: '이름, 연락처, 매장, 모델명 검색',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        filled: true,
                        fillColor: const Color(0xFFFAFAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final label in const [
                        '전체',
                        '고객DB',
                        '가망고객',
                        '유선회원',
                        '재고관리',
                      ])
                        _filterChip(
                          label,
                          selectedTable,
                          (value) => selectedTable = value,
                        ),
                      const SizedBox(width: 10),
                      for (final label in const ['오늘', '7일', '30일', '전체'])
                        _periodChip(label),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (isLoading)
                    const Center(child: CircularProgressIndicator())
                  else if (rows.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFAFAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE8E9EF)),
                      ),
                      child: const Text(
                        '조건에 맞는 삭제자료가 없습니다.',
                        style: TextStyle(
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  else
                    ...rows.map((record) => _recordTile(
                          record,
                          mobile: mobile,
                        )),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
