import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class AuditLogPage extends StatefulWidget {
  final String role;

  const AuditLogPage({super.key, required this.role});

  @override
  State<AuditLogPage> createState() => _AuditLogPageState();
}

class _AuditLogPageState extends State<AuditLogPage> {
  final searchController = TextEditingController();
  final dateFormat = DateFormat('yyyy-MM-dd');
  final dateTimeFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

  List<Map<String, dynamic>> logs = [];
  bool isLoading = true;

  bool isAdmin() => widget.role == '대표' || widget.role == '개발자';

  @override
  void initState() {
    super.initState();
    fetchLogs();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> fetchLogs() async {
    if (!isAdmin()) {
      setState(() => isLoading = false);
      return;
    }

    setState(() => isLoading = true);
    try {
      final data = await supabase
          .from('audit_logs')
          .select()
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        logs = List<Map<String, dynamic>>.from(data);
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      debugPrint('audit log load failed: $e');
    }
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString())?.toLocal();
  }

  String _dateLabel(dynamic value) {
    final date = _parseDate(value);
    if (date == null) return '날짜 없음';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    if (target == today) return '오늘 ${dateFormat.format(date)}';
    if (target == today.subtract(const Duration(days: 1))) {
      return '어제 ${dateFormat.format(date)}';
    }
    return dateFormat.format(date);
  }

  String _timeLabel(dynamic value) {
    final date = _parseDate(value);
    return date == null ? '-' : dateTimeFormat.format(date);
  }

  String _value(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? '-' : text;
  }

  String _actionLabel(dynamic value) {
    return switch (_value(value)) {
      'create_inventory' => '재고 등록',
      'update_inventory' => '재고 수정',
      'delete_inventory' => '재고 삭제',
      'create_customer' => '고객 등록',
      'update_customer' => '고객 수정',
      'delete_customer' => '고객 삭제',
      'create_lead' => '가망고객 등록',
      'update_lead' => '가망고객 수정',
      'delete_lead' => '가망고객 삭제',
      '-' => '-',
      final raw => raw,
    };
  }

  String _tableLabel(dynamic value) {
    return switch (_value(value)) {
      'device_inventory' => '재고관리',
      'customers' => '고객DB',
      'leads' => '가망고객',
      'wired_members' => '유선회원',
      'profiles' => '직원관리',
      '-' => '-',
      final raw => raw,
    };
  }

  String _detailKeyLabel(String key) {
    return switch (key) {
      'store' => '매장',
      'model_name' => '모델명',
      'serial_number' => '일련번호',
      'status' => '상태',
      'memo' => '메모',
      'name' => '이름',
      'phone' => '연락처',
      'role' => '권한',
      'staff' => '담당자',
      _ => key,
    };
  }

  String _detailLabel(dynamic detail) {
    if (detail == null) return '-';
    if (detail is Map) {
      return detail.entries
          .map((entry) =>
              '${_detailKeyLabel(entry.key.toString())}: ${entry.value}')
          .join(' / ');
    }
    return detail.toString();
  }

  String _targetLabel(Map<String, dynamic> log) {
    final detail = log['detail'];
    if (detail is Map) {
      final model = _value(detail['model_name']);
      final serial = _value(detail['serial_number']);
      if (model != '-' || serial != '-') {
        return [model, serial].where((value) => value != '-').join(' / ');
      }
      final name = _value(detail['name']);
      if (name != '-') return name;
    }
    return '대상번호 ${_value(log['target_id'])}';
  }

  List<Map<String, dynamic>> get filteredLogs {
    final query = searchController.text.trim().toLowerCase();
    if (query.isEmpty) return logs;

    return logs.where((log) {
      final haystack = [
        _actionLabel(log['action']),
        _tableLabel(log['target_table']),
        _targetLabel(log),
        _value(log['target_id']),
        _timeLabel(log['created_at']),
        _detailLabel(log['detail']),
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  Map<String, List<Map<String, dynamic>>> _groupByDate(
    List<Map<String, dynamic>> rows,
  ) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      grouped.putIfAbsent(_dateLabel(row['created_at']), () => []).add(row);
    }
    return grouped;
  }

  Widget _searchField() {
    return SizedBox(
      height: 42,
      child: TextField(
        controller: searchController,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: '액션, 화면, 대상, 상세 내용 검색',
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          filled: true,
          fillColor: const Color(0xFFF9FAFB),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF111827), width: 1.2),
          ),
        ),
      ),
    );
  }

  Widget _logRow(Map<String, dynamic> log) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF1F3F5))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              _actionLabel(log['action']),
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: Color(0xFF111827),
              ),
            ),
          ),
          SizedBox(
            width: 120,
            child: Text(
              _tableLabel(log['target_table']),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Color(0xFF374151),
              ),
            ),
          ),
          SizedBox(
            width: 220,
            child: Text(
              _targetLabel(log),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF374151),
              ),
            ),
          ),
          SizedBox(
            width: 170,
            child: Text(
              _timeLabel(log['created_at']),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF6B7280),
              ),
            ),
          ),
          Expanded(
            child: Text(
              _detailLabel(log['detail']),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6B7280),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateSection(String label, List<Map<String, dynamic>> rows) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
            ),
            child: Row(
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${rows.length}건',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
          for (final row in rows) _logRow(row),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!isAdmin()) {
      return const Scaffold(
        body: Center(child: Text('접근 권한 없음')),
      );
    }

    final rows = filteredLogs;
    final grouped = _groupByDate(rows);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      body: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded),
                  tooltip: '뒤로가기',
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '감사로그',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF111827),
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '재고와 주요 데이터 변경 이력을 날짜별로 확인합니다',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 360, child: _searchField()),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: fetchLogs,
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                  label: const Text('새로고침'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF111827),
                    foregroundColor: Colors.white,
                    elevation: 0,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : rows.isEmpty
                      ? const Center(child: Text('조건에 맞는 감사로그가 없습니다'))
                      : SingleChildScrollView(
                          child: Column(
                            children: [
                              for (final entry in grouped.entries)
                                _dateSection(entry.key, entry.value),
                            ],
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
