import 'package:supabase_flutter/supabase_flutter.dart';

class AuditLogService {
  AuditLogService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<void> record({
    required String action,
    required String targetTable,
    String? targetId,
    Map<String, dynamic>? detail,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    if (action != 'export_customers_excel' &&
        action != 'export_wired_members_excel') {
      return;
    }

    try {
      final payload = detail ?? <String, dynamic>{};
      await _client.functions.invoke('auth-policy', body: {
        'action': 'record_export_audit_log',
        'access_token': _client.auth.currentSession?.accessToken,
        'target_table': targetTable,
        'row_count': payload['row_count'],
        'file_name': payload['file_name'],
        'store_filter': payload['store_filter'],
        'date_filter': payload['date_filter'],
      });
    } catch (_) {
      // 감사 로그 실패가 업무 동작을 막지 않도록 조용히 무시합니다.
    }
  }
}
