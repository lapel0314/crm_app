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

    try {
      await _client.from('audit_logs').insert({
        'actor_id': user.id,
        'action': action,
        'target_table': targetTable,
        'target_id': targetId,
        'detail': detail ?? <String, dynamic>{},
      });
    } catch (_) {
      // 감사 로그 실패가 업무 동작을 막지 않도록 조용히 무시합니다.
    }
  }
}
