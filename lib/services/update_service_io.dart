import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'update_service_base.dart';

class UpdateService extends UpdateServiceBase {
  static const _installerBucket = 'app-installers';

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
          'latest_version, min_required_version, apk_url, update_message, version, installer_url, installer_sha256, notes, storage_path',
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
    final apkSha256 = _firstText(data, ['installer_sha256']);
    final message = _firstText(data, ['update_message', 'notes']);
    final storagePath = _firstText(data, ['storage_path']);

    if (latestVersion.isEmpty ||
        minRequiredVersion.isEmpty ||
        (apkUrl.isEmpty && storagePath.isEmpty)) {
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
      packageSha256: apkSha256,
      message: message.isEmpty ? '최신 Android 앱을 설치한 뒤 다시 실행해 주세요.' : message,
      isRequired: true,
      storagePath: storagePath.isEmpty ? null : storagePath,
    );
  }

  Future<AppUpdateInfo?> _checkWindowsUpdate() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;

    final data = await supabase
        .from('app_updates')
        .select(
          'version, installer_url, installer_sha256, notes, auto_install, storage_path',
        )
        .eq('platform', 'windows')
        .eq('is_active', true)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (data == null) return null;

    final version = data['version']?.toString().trim() ?? '';
    final installerUrl = data['installer_url']?.toString().trim() ?? '';
    final installerSha256 = data['installer_sha256']?.toString().trim() ?? '';
    final notes = data['notes']?.toString().trim() ?? '';
    final storagePath = data['storage_path']?.toString().trim() ?? '';
    if (version.isEmpty || (installerUrl.isEmpty && storagePath.isEmpty)) {
      return null;
    }

    if (compareVersions(version, currentVersion) <= 0) return null;

    return AppUpdateInfo(
      platform: 'windows',
      currentVersion: currentVersion,
      latestVersion: version,
      minRequiredVersion: version,
      packageUrl: installerUrl,
      packageSha256: installerSha256,
      message: notes.isEmpty ? '최신 Windows 버전을 설치한 뒤 다시 실행해 주세요.' : notes,
      isRequired: true,
      storagePath: storagePath.isEmpty ? null : storagePath,
    );
  }

  @override
  Future<void> startUpdate(AppUpdateInfo update) async {
    final downloadUrl = await _resolveDownloadUrl(update);
    if (update.platform == 'android') {
      await _openAndroidApkUrl(downloadUrl);
      return;
    }
    if (update.platform == 'windows') {
      final installer = await _downloadWindowsInstaller(update, downloadUrl);
      await _runWindowsInstaller(installer);
    }
  }

  /// Storage-backed updates (`storagePath` set) require an authenticated
  /// session: the private `app-installers` bucket only signs URLs for
  /// logged-in accounts. Legacy rows without a storage path keep using
  /// `packageUrl` (a public GitHub Release link) directly.
  Future<String> _resolveDownloadUrl(AppUpdateInfo update) async {
    final storagePath = update.storagePath;
    if (storagePath == null || storagePath.isEmpty) {
      return update.packageUrl;
    }

    if (supabase.auth.currentSession == null) {
      throw const UpdateAuthRequiredException();
    }

    try {
      return await supabase.storage
          .from(_installerBucket)
          .createSignedUrl(storagePath, 3600);
    } on StorageException catch (e) {
      if (e.statusCode == '401' || e.statusCode == '403') {
        throw const UpdateAuthRequiredException();
      }
      throw StateError('업데이트 다운로드 주소를 발급받지 못했습니다.');
    }
  }

  Future<void> _openAndroidApkUrl(String apkUrl) async {
    final uri = _validateUpdateUri(apkUrl);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      throw StateError('업데이트 다운로드 주소를 열 수 없습니다.');
    }
  }

  Future<File> _downloadWindowsInstaller(
    AppUpdateInfo update,
    String downloadUrl,
  ) async {
    final packageUri = _validateUpdateUri(downloadUrl);
    final expectedSha256 = update.packageSha256.trim().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedSha256)) {
      throw StateError('Windows 설치파일 SHA-256 값이 등록되지 않았습니다.');
    }

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
      final response = await _openValidatedGet(client, packageUri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'installer download failed: ${response.statusCode}',
        );
      }

      final sink = file.openWrite();
      final digestSink = _DigestCollector();
      final byteSink = crypto.sha256.startChunkedConversion(digestSink);
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          byteSink.add(chunk);
        }
      } finally {
        byteSink.close();
        await sink.close();
      }

      final actualSha256 = digestSink.digest?.toString().toLowerCase();
      if (actualSha256 == null) {
        if (file.existsSync()) file.deleteSync();
        throw StateError('Windows 설치파일 SHA-256 계산에 실패했습니다.');
      }
      if (actualSha256 != expectedSha256) {
        if (file.existsSync()) file.deleteSync();
        throw StateError('Windows 설치파일 SHA-256 검증에 실패했습니다.');
      }

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
        '/SILENT',
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

  Future<HttpClientResponse> _openValidatedGet(
    HttpClient client,
    Uri uri, {
    int redirectCount = 0,
  }) async {
    if (redirectCount > 5) {
      throw StateError('업데이트 다운로드 리다이렉트가 너무 많습니다.');
    }

    final request = await client.getUrl(uri);
    request.followRedirects = false;
    final response = await request.close();
    if (_isRedirect(response.statusCode)) {
      final location = response.headers.value(HttpHeaders.locationHeader);
      await response.drain<void>();
      if (location == null || location.trim().isEmpty) {
        throw StateError('업데이트 다운로드 리다이렉트 주소가 없습니다.');
      }
      final nextUri = _validateUpdateUri(uri.resolve(location).toString());
      return _openValidatedGet(
        client,
        nextUri,
        redirectCount: redirectCount + 1,
      );
    }
    return response;
  }

  bool _isRedirect(int statusCode) {
    return statusCode == HttpStatus.movedPermanently ||
        statusCode == HttpStatus.found ||
        statusCode == HttpStatus.seeOther ||
        statusCode == HttpStatus.temporaryRedirect ||
        statusCode == HttpStatus.permanentRedirect;
  }

  Uri _validateUpdateUri(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !uri.hasScheme ||
        !uri.hasAuthority ||
        uri.scheme.toLowerCase() != 'https') {
      throw StateError('업데이트 다운로드 주소는 HTTPS만 허용됩니다.');
    }

    if (!_isAllowedUpdateHost(uri.host)) {
      throw StateError('허용되지 않은 업데이트 다운로드 호스트입니다.');
    }

    return uri;
  }

  bool _isAllowedUpdateHost(String host) {
    final normalizedHost = host.toLowerCase();
    final allowedHosts = <String>{
      'github.com',
      'github-releases.githubusercontent.com',
      'release-assets.githubusercontent.com',
      'objects.githubusercontent.com',
      ...updateAllowedHosts
          .split(',')
          .map((host) => host.trim().toLowerCase())
          .where((host) => host.isNotEmpty),
    };

    const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
    final supabaseHost = Uri.tryParse(supabaseUrl)?.host.toLowerCase();
    if (supabaseHost != null && supabaseHost.isNotEmpty) {
      allowedHosts.add(supabaseHost);
    }

    return allowedHosts.contains(normalizedHost);
  }
}

class _DigestCollector implements Sink<crypto.Digest> {
  crypto.Digest? digest;

  @override
  void add(crypto.Digest data) {
    digest = data;
  }

  @override
  void close() {}
}
