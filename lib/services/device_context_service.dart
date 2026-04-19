import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';

class DeviceContext {
  final String platform;
  final bool isMobile;
  final String? ssid;

  const DeviceContext({
    required this.platform,
    required this.isMobile,
    required this.ssid,
  });
}

class DeviceContextService {
  const DeviceContextService();

  Future<DeviceContext> load() async {
    final platform = _resolvePlatform();
    final isMobile = platform == 'android' || platform == 'ios';

    String? ssid;
    if (isMobile && !kIsWeb) {
      try {
        ssid = await NetworkInfo().getWifiName();
        ssid = ssid?.replaceAll('"', '').trim();
        if (ssid != null && ssid.isEmpty) {
          ssid = null;
        }
      } catch (_) {
        ssid = null;
      }
    }

    return DeviceContext(
      platform: platform,
      isMobile: isMobile,
      ssid: ssid,
    );
  }

  String _resolvePlatform() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    return defaultTargetPlatform.name;
  }
}
