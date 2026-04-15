import 'package:supabase_flutter/supabase_flutter.dart';

class Notice {
  final String title;
  final String content;
  final DateTime? createdAt;

  const Notice({required this.title, required this.content, this.createdAt});

  factory Notice.fromMap(Map<String, dynamic> data) {
    return Notice(
      title: (data['title'] ?? '공지사항').toString(),
      content: (data['content'] ?? '').toString(),
      createdAt: DateTime.tryParse((data['created_at'] ?? '').toString()),
    );
  }
}

class NoticeService {
  final SupabaseClient supabase;

  const NoticeService(this.supabase);

  Future<Notice?> fetchLatestNotice() async {
    try {
      final data = await supabase
          .from('crm_notices')
          .select('title, content, created_at')
          .eq('is_active', true)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (data == null) return null;
      return Notice.fromMap(Map<String, dynamic>.from(data));
    } catch (_) {
      return null;
    }
  }

  Future<void> createNotice({
    required String title,
    required String content,
  }) async {
    await supabase.from('crm_notices').insert({
      'title': title.trim().isEmpty ? '공지사항' : title.trim(),
      'content': content.trim(),
      'created_by': supabase.auth.currentUser?.id,
      'is_active': true,
    });
  }
}
