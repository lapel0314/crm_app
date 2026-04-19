import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'update_service_base.dart';

class UpdateService extends UpdateServiceBase {
  const UpdateService(super.supabase);

  @override
  Future<AppUpdateInfo?> checkForUpdate() async {
    if (Platform.isAndroid) return _checkAndroidUpdate();
    if (Platform.isWindows) return _checkWindowsUpdate();
    return null;
  }

  Future<AppUpdateInfo?> _checkAndroidUpdate() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;

    final data = await supabase
        .from('app_updates')
        .select(
          'latest_version, min_required_version, apk_url, update_message, version, installer_url, notes',
        )
        .eq('platform', 'android')
        .eq('is_active', true)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (data == null) return null;

    final latestVersion = _firstText(data, ['latest_version', 'version']);
    final minRequiredVersion =
        _firstText(data, ['min_required_version', 'latest_version', 'version']);
    final apkUrl = _firstText(data, ['apk_url', 'installer_url']);
    final message = _firstText(data, ['update_message', 'notes']);

    if (latestVersion.isEmpty || minRequiredVersion.isEmpty || apkUrl.isEmpty) {
      return null;
    }

    final required = compareVersions(currentVersion, minRequiredVersion) < 0;
    if (!required) return null;

    return AppUpdateInfo(
      platform: 'android',
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      minRequiredVersion: minRequiredVersion,
      packageUrl: apkUrl,
      message: message.isEmpty
          ? '최신 Android 앱을 설치한 뒤 다시 실행해 주세요.'
          : message,
      isRequired: true,
    );
  }

  Future<AppUpdateInfo?> _checkWindowsUpdate() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;

    final data = await supabase
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
    final notes = data['notes']?.toString().trim() ?? '';
    if (version.isEmpty || installerUrl.isEmpty) return null;

    if (compareVersions(version, currentVersion) <= 0) return null;

    return AppUpdateInfo(
      platform: 'windows',
      currentVersion: currentVersion,
      latestVersion: version,
      minRequiredVersion: version,
      packageUrl: installerUrl,
      message: notes.isEmpty
          ? '최신 Windows 버전을 설치한 뒤 다시 실행해 주세요.'
          : notes,
      isRequired: true,
    );
  }

  @override
  Future<void> startUpdate(AppUpdateInfo update) async {
    if (update.platform == 'android') {
      await _openAndroidApkUrl(update.packageUrl);
      return;
    }
    if (update.platform == 'windows') {
      final installer = await _downloadWindowsInstaller(update);
      await _runWindowsInstaller(installer);
    }
  }

  Future<void> _openAndroidApkUrl(String apkUrl) async {
    final uri = Uri.parse(apkUrl);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      throw StateError('업데이트 다운로드 주소를 열 수 없습니다.');
    }
  }

  Future<File> _downloadWindowsInstaller(AppUpdateInfo update) async {
    final safeVersion =
        update.latestVersion.replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_');
    final updateDir =
        Directory('${Directory.systemTemp.path}\\pink_phone_crm_update');
    if (!updateDir.existsSync()) {
      updateDir.createSync(recursive: true);
    }

    final file = File('${updateDir.path}\\pinkphone_setup_$safeVersion.exe');
    if (file.existsSync()) {
      file.deleteSync();
    }

    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(update.packageUrl));
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'installer download failed: ${response.statusCode}',
        );
      }

      final sink = file.openWrite();
      await response.pipe(sink);
      await sink.close();
      return file;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _runWindowsInstaller(File installer) async {
    final logPath =
        '${Directory.systemTemp.path}\\pink_phone_crm_update\\installer.log';
    await Process.start(
      installer.path,
      [
        '/SP-',
        '/VERYSILENT',
        '/SUPPRESSMSGBOXES',
        '/NORESTART',
        '/PASSWORD=$installerPassword',
        '/LOG=$logPath',
      ],
      mode: ProcessStartMode.detached,
    );
  }

  String _firstText(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }
}
