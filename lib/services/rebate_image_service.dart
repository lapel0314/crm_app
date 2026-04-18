import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RebateImage {
  final String id;
  final String carrier;
  final DateTime imageDate;
  final String storagePath;
  final String originalName;
  final String contentType;
  final DateTime? updatedAt;

  const RebateImage({
    required this.id,
    required this.carrier,
    required this.imageDate,
    required this.storagePath,
    required this.originalName,
    required this.contentType,
    this.updatedAt,
  });

  factory RebateImage.fromMap(Map<String, dynamic> data) {
    return RebateImage(
      id: (data['id'] ?? '').toString(),
      carrier: (data['carrier'] ?? 'SKT').toString(),
      imageDate: DateTime.tryParse((data['image_date'] ?? '').toString()) ??
          DateTime.now(),
      storagePath: (data['storage_path'] ?? '').toString(),
      originalName: (data['original_name'] ?? '').toString(),
      contentType: (data['content_type'] ?? '').toString(),
      updatedAt: DateTime.tryParse((data['updated_at'] ?? '').toString()),
    );
  }
}

class RebateImageService {
  static const bucketName = 'rebate-images';

  final SupabaseClient supabase;

  const RebateImageService(this.supabase);

  String formatDate(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  Future<RebateImage?> fetchByDate(DateTime date, String carrier) async {
    final data = await supabase
        .from('rebate_images')
        .select()
        .eq('carrier', carrier)
        .eq('image_date', formatDate(date))
        .maybeSingle();

    if (data == null) return null;
    return RebateImage.fromMap(Map<String, dynamic>.from(data));
  }

  Future<List<DateTime>> fetchUploadedDates(String carrier) async {
    final rows = await supabase
        .from('rebate_images')
        .select('image_date')
        .eq('carrier', carrier)
        .order('image_date', ascending: false);

    return rows
        .map<DateTime?>(
          (row) => DateTime.tryParse((row['image_date'] ?? '').toString()),
        )
        .whereType<DateTime>()
        .toList();
  }

  Future<String> signedUrl(String storagePath) {
    return supabase.storage.from(bucketName).createSignedUrl(storagePath, 3600);
  }

  Future<RebateImage> saveImage({
    required String carrier,
    required DateTime date,
    required Uint8List bytes,
    required String fileName,
    required String contentType,
  }) async {
    final normalizedDate = DateTime(date.year, date.month, date.day);
    final dateText = formatDate(normalizedDate);
    final existing = await fetchByDate(normalizedDate, carrier);
    final extension = _extensionFromFileName(fileName, contentType);
    final storagePath =
        '$carrier/$dateText/${DateTime.now().millisecondsSinceEpoch}$extension';

    await supabase.storage.from(bucketName).uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(
            contentType: contentType,
            upsert: true,
          ),
        );

    try {
      final row = await supabase
          .from('rebate_images')
          .upsert(
            {
              'image_date': dateText,
              'carrier': carrier,
              'storage_path': storagePath,
              'original_name': fileName,
              'content_type': contentType,
              'uploaded_by': supabase.auth.currentUser?.id,
            },
            onConflict: 'carrier,image_date',
          )
          .select()
          .single();

      if (existing != null && existing.storagePath != storagePath) {
        await _removeStorageObject(existing.storagePath);
      }

      return RebateImage.fromMap(Map<String, dynamic>.from(row));
    } catch (_) {
      await _removeStorageObject(storagePath);
      rethrow;
    }
  }

  Future<void> deleteImage(RebateImage image) async {
    await supabase.from('rebate_images').delete().eq('id', image.id);
    await _removeStorageObject(image.storagePath);
  }

  Future<void> _removeStorageObject(String storagePath) async {
    if (storagePath.trim().isEmpty) return;
    try {
      await supabase.storage.from(bucketName).remove([storagePath]);
    } catch (_) {}
  }

  String _extensionFromFileName(String fileName, String contentType) {
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex >= 0 && dotIndex < fileName.length - 1) {
      return fileName.substring(dotIndex).toLowerCase();
    }
    switch (contentType) {
      case 'image/png':
        return '.png';
      case 'image/webp':
        return '.webp';
      case 'image/gif':
        return '.gif';
      default:
        return '.jpg';
    }
  }
}
