import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const String appVersion = '1.0.2';

class AppUpdateInfo {
  final String version;
  final String installerUrl;
  final String notes;
  final bool autoInstall;

  const AppUpdateInfo({
    required this.version,
    required this.installerUrl,
    required this.notes,
    required this.autoInstall,
  });
}

class UpdateService {
  UpdateService(this._supabase);

  final SupabaseClient _supabase;

  Future<AppUpdateInfo?> checkForUpdate() async {
    if (kIsWeb || !Platform.isWindows) return null;

    try {
      final data = await _supabase
          .from('app_updates')
          .select('version, installer_url, notes, auto_install')
          .eq('platform', 'windows')
          .eq('is_active', true)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (data == null) return null;

      final version = data['version']?.toString().trim() ?? '';
      final installerUrl = data['installer_url']?.toString().trim() ?? '';
      if (version.isEmpty || installerUrl.isEmpty) return null;

      if (_compareVersions(version, appVersion) <= 0) return null;
      if (data['auto_install'] != true) return null;

      return AppUpdateInfo(
        version: version,
        installerUrl: installerUrl,
        notes: data['notes']?.toString().trim() ?? '',
        autoInstall: true,
      );
    } catch (e) {
      debugPrint('update check failed: $e');
      return null;
    }
  }

  Future<File> downloadInstaller(AppUpdateInfo update) async {
    final safeVersion =
        update.version.replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_');
    final updateDir =
        Directory('${Directory.systemTemp.path}\\pink_phone_crm_update');
    if (!updateDir.existsSync()) {
      updateDir.createSync(recursive: true);
    }

    final file = File('${updateDir.path}\\핑크폰 설치 $safeVersion.exe');
    if (file.existsSync()) {
      file.deleteSync();
    }

    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(update.installerUrl));
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
            'installer download failed: ${response.statusCode}');
      }

      final sink = file.openWrite();
      await response.pipe(sink);
      await sink.close();
      return file;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> runInstaller(File installer) async {
    await Process.start(
      installer.path,
      const ['/SP-', '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART'],
      mode: ProcessStartMode.detached,
    );
  }

  int _compareVersions(String left, String right) {
    final leftParts = left.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final rightParts =
        right.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final length = leftParts.length > rightParts.length
        ? leftParts.length
        : rightParts.length;

    for (var i = 0; i < length; i++) {
      final leftValue = i < leftParts.length ? leftParts[i] : 0;
      final rightValue = i < rightParts.length ? rightParts[i] : 0;
      if (leftValue != rightValue) return leftValue.compareTo(rightValue);
    }
    return 0;
  }
}
