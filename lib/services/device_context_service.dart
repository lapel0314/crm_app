import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';

class DeviceContext {
  final String platform;
  final bool isMobile;
  final String? ssid;
  final String? wifiIp;
  final String? wifiGatewayIp;
  final String? wifiBssid;

  const DeviceContext({
    required this.platform,
    required this.isMobile,
    required this.ssid,
    required this.wifiIp,
    required this.wifiGatewayIp,
    required this.wifiBssid,
  });
}

class DeviceContextService {
  const DeviceContextService();

  Future<DeviceContext> load() async {
    final platform = _resolvePlatform();
    final isMobile = platform == 'android' || platform == 'ios';

    String? ssid;
    String? wifiIp;
    String? wifiGatewayIp;
    String? wifiBssid;
    if (isMobile && !kIsWeb) {
      final info = NetworkInfo();
      try {
        ssid = _clean(await info.getWifiName(), stripQuotes: true);
      } catch (_) {
        ssid = null;
      }
      try {
        wifiIp = _clean(await info.getWifiIP());
      } catch (_) {
        wifiIp = null;
      }
      try {
        wifiGatewayIp = _clean(await info.getWifiGatewayIP());
      } catch (_) {
        wifiGatewayIp = null;
      }
      try {
        wifiBssid = _clean(await info.getWifiBSSID());
      } catch (_) {
        wifiBssid = null;
      }
    }

    return DeviceContext(
      platform: platform,
      isMobile: isMobile,
      ssid: ssid,
      wifiIp: wifiIp,
      wifiGatewayIp: wifiGatewayIp,
      wifiBssid: wifiBssid,
    );
  }

  String? _clean(String? value, {bool stripQuotes = false}) {
    var text = value;
    if (stripQuotes) {
      text = text?.replaceAll('"', '');
    }
    text = text?.trim();
    return text == null || text.isEmpty ? null : text;
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
