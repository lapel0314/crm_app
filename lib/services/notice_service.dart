import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

class Notice {
  final String id;
  final String title;
  final String content;
  final String imagePath;
  final DateTime? createdAt;

  const Notice({
    required this.id,
    required this.title,
    required this.content,
    required this.imagePath,
    this.createdAt,
  });

  factory Notice.fromMap(Map<String, dynamic> data) {
    return Notice(
      id: (data['id'] ?? '').toString(),
      title: (data['title'] ?? '공지사항').toString(),
      content: (data['content'] ?? '').toString(),
      imagePath: (data['image_path'] ?? '').toString(),
      createdAt: DateTime.tryParse((data['created_at'] ?? '').toString()),
    );
  }

  bool get hasImage => imagePath.trim().isNotEmpty;

  bool get isToday {
    final date = createdAt?.toLocal();
    if (date == null) return false;
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }
}

class NoticeService {
  static const bucketName = 'crm-notice-images';

  final SupabaseClient supabase;

  const NoticeService(this.supabase);

  Future<Notice?> fetchLatestNotice() async {
    try {
      final data = await supabase
          .from('crm_notices')
          .select('id, title, content, image_path, created_at')
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

  Future<List<Notice>> fetchNotices() async {
    final rows = await supabase
        .from('crm_notices')
        .select('id, title, content, image_path, created_at')
        .eq('is_active', true)
        .order('created_at', ascending: false);

    return rows
        .map<Notice>((row) => Notice.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  Future<String> signedImageUrl(String imagePath) {
    return supabase.storage.from(bucketName).createSignedUrl(imagePath, 3600);
  }

  Future<void> createNotice({
    required String title,
    required String content,
    Uint8List? imageBytes,
    String? imageName,
    String? contentType,
  }) async {
    final payload = {
      'title': title.trim().isEmpty ? '공지사항' : title.trim(),
      'content': content.trim(),
      'created_by': supabase.auth.currentUser?.id,
      'is_active': true,
    };

    if (imageBytes != null && imageBytes.isNotEmpty) {
      final imagePath =
          '${DateTime.now().millisecondsSinceEpoch}_${imageName ?? 'notice.jpg'}';
      await supabase.storage.from(bucketName).uploadBinary(
            imagePath,
            imageBytes,
            fileOptions: FileOptions(
              contentType: contentType ?? 'image/jpeg',
              upsert: true,
            ),
          );
      payload['image_path'] = imagePath;
    }

    await supabase.from('crm_notices').insert(payload);
  }

  Future<void> deleteNotice(Notice notice) async {
    final updated = await supabase
        .from('crm_notices')
        .update({'is_active': false})
        .eq('id', notice.id)
        .select('id')
        .maybeSingle();

    if (updated == null) {
      throw StateError('삭제 권한이 없거나 대상 공지사항을 찾을 수 없습니다.');
    }

    if (notice.hasImage) {
      try {
        await supabase.storage.from(bucketName).remove([notice.imagePath]);
      } catch (_) {
        // Ignore missing or already-removed assets after the notice is hidden.
      }
    }
  }
}
