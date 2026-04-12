import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class AuditLogPage extends StatefulWidget {
  final String role;

  const AuditLogPage({super.key, required this.role});

  @override
  State<AuditLogPage> createState() => _AuditLogPageState();
}

class _AuditLogPageState extends State<AuditLogPage> {
  List<Map<String, dynamic>> logs = [];
  bool isLoading = true;

  bool isAdmin() {
    return widget.role == '대표' || widget.role == '개발자';
  }

  @override
  void initState() {
    super.initState();
    fetchLogs();
  }

  Future<void> fetchLogs() async {
    if (!isAdmin()) {
      setState(() {
        isLoading = false;
      });
      return;
    }

    try {
      final data = await supabase
          .from('audit_logs')
          .select()
          .order('created_at', ascending: false);

      setState(() {
        logs = List<Map<String, dynamic>>.from(data);
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
      });

      debugPrint('audit log load failed: $e');
    }
  }

  String formatDate(dynamic value) {
    if (value == null) return '-';
    final text = value.toString();
    if (text.length >= 19) {
      return text.substring(0, 19).replaceFirst('T', ' ');
    }
    return text;
  }

  String formatDetail(dynamic detail) {
    if (detail == null) return '-';
    if (detail is Map) {
      return detail.entries.map((e) => '${e.key}: ${e.value}').join(' / ');
    }
    return detail.toString();
  }

  DataColumn _column(String label) {
    return DataColumn(
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!isAdmin()) {
      return const Scaffold(
        body: Center(
          child: Text('접근 권한 없음'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('감사로그 조회'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFE7E9EE)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : logs.isEmpty
                  ? const Center(child: Text('감사로그가 없습니다'))
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          child: DataTable(
                            headingRowColor: WidgetStateProperty.all(
                              const Color(0xFFF8FAFC),
                            ),
                            dataRowMinHeight: 64,
                            dataRowMaxHeight: 72,
                            columnSpacing: 28,
                            horizontalMargin: 18,
                            columns: [
                              _column('액션'),
                              _column('테이블'),
                              _column('대상 ID'),
                              _column('시간'),
                              _column('상세'),
                            ],
                            rows: logs.map((log) {
                              return DataRow(
                                cells: [
                                  DataCell(
                                      Text(log['action']?.toString() ?? '-')),
                                  DataCell(Text(
                                      log['target_table']?.toString() ?? '-')),
                                  DataCell(
                                    SizedBox(
                                      width: 180,
                                      child: Text(
                                        log['target_id']?.toString() ?? '-',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                  DataCell(Text(formatDate(log['created_at']))),
                                  DataCell(
                                    SizedBox(
                                      width: 420,
                                      child: Text(
                                        formatDetail(log['detail']),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
        ),
      ),
    );
  }
}
