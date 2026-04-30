import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crm_app/utils/store_utils.dart';

final supabase = Supabase.instance.client;

class RecycleBinPage extends StatefulWidget {
  final String role;

  const RecycleBinPage({super.key, required this.role});

  @override
  State<RecycleBinPage> createState() => _RecycleBinPageState();
}

class _RecycleBinPageState extends State<RecycleBinPage> {
  final dateTimeFormat = DateFormat('yyyy-MM-dd HH:mm');
  List<Map<String, dynamic>> records = [];
  bool isLoading = true;
  bool isRestoring = false;

  bool get isAdmin => isPrivilegedRole(widget.role);

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
      _showMessage('복구 완료');
      await fetchRecords();
    } catch (e) {
      debugPrint('restore failed: $e');
      if (mounted) _showMessage('복구 실패: $e');
    } finally {
      if (mounted) setState(() => isRestoring = false);
    }
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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

  String _dateLabel(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    return date == null ? '-' : dateTimeFormat.format(date);
  }

  Widget _recordTile(Map<String, dynamic> record) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE8E9EF)),
      ),
      child: Row(
        children: [
          const Icon(Icons.restore_from_trash_rounded,
              color: Color(0xFFC94C6E)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_tableLabel(record['target_table'])} · ${record['title'] ?? '-'}',
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if ((record['store']?.toString().trim() ?? '').isNotEmpty)
                      '매장: ${record['store']}',
                    if ((record['subtitle']?.toString().trim() ?? '')
                        .isNotEmpty)
                      record['subtitle'].toString(),
                    '삭제일: ${_dateLabel(record['deleted_at'])}',
                  ].join(' · '),
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: isRestoring ? null : () => restoreRecord(record),
            icon: const Icon(Icons.restore_rounded, size: 18),
            label: const Text('복구'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.of(context).size.width < 760;

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
                          '휴지통/복구',
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
                    '삭제된 고객DB, 가망고객, 유선회원, 재고를 영구 삭제하지 않고 복구할 수 있습니다.',
                    style: TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (isLoading)
                    const Center(child: CircularProgressIndicator())
                  else if (records.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFAFAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE8E9EF)),
                      ),
                      child: const Text(
                        '휴지통이 비어 있습니다.',
                        style: TextStyle(
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  else
                    ...records.map(_recordTile),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
