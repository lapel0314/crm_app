import 'package:flutter/foundation.dart';
import 'package:crm_app/services/device_context_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoginPolicyException implements Exception {
  final String message;

  const LoginPolicyException(this.message);

  @override
  String toString() => message;
}

class LoginPolicyDecision {
  final bool allowed;
  final String message;
  final String? reasonCode;
  final String? detectedPublicIp;
  final String? role;
  final String? storeName;
  final String? storeId;
  final String? ssid;
  final bool canManageNetworks;

  const LoginPolicyDecision({
    required this.allowed,
    required this.message,
    required this.reasonCode,
    required this.detectedPublicIp,
    required this.role,
    required this.storeName,
    required this.storeId,
    required this.ssid,
    required this.canManageNetworks,
  });

  factory LoginPolicyDecision.fromJson(Map<String, dynamic> json) {
    return LoginPolicyDecision(
      allowed: json['allowed'] == true,
      message: (json['message'] ?? '').toString(),
      reasonCode: json['reason_code']?.toString(),
      detectedPublicIp: json['detected_public_ip']?.toString(),
      role: json['role']?.toString(),
      storeName: json['store_name']?.toString(),
      storeId: json['store_id']?.toString(),
      ssid: json['ssid']?.toString(),
      canManageNetworks: json['can_manage_networks'] == true,
    );
  }
}

class StoreNetworkRecord {
  final String id;
  final String publicIp;
  final bool isActive;
  final String? label;
  final String? ssidHint;
  final String? lastSeenAt;

  const StoreNetworkRecord({
    required this.id,
    required this.publicIp,
    required this.isActive,
    required this.label,
    required this.ssidHint,
    required this.lastSeenAt,
  });

  factory StoreNetworkRecord.fromJson(Map<String, dynamic> json) {
    return StoreNetworkRecord(
      id: json['id'].toString(),
      publicIp: (json['public_ip'] ?? '').toString(),
      isActive: json['is_active'] != false,
      label: json['label']?.toString(),
      ssidHint: json['ssid_hint']?.toString(),
      lastSeenAt: json['last_seen_at']?.toString(),
    );
  }
}

class StoreNetworkSnapshot {
  final String? storeId;
  final String? storeName;
  final String? detectedPublicIp;
  final String? ssid;
  final bool canManageNetworks;
  final List<StoreNetworkRecord> networks;

  const StoreNetworkSnapshot({
    required this.storeId,
    required this.storeName,
    required this.detectedPublicIp,
    required this.ssid,
    required this.canManageNetworks,
    required this.networks,
  });

  factory StoreNetworkSnapshot.fromJson(Map<String, dynamic> json) {
    final rawNetworks = (json['networks'] as List?) ?? const [];
    return StoreNetworkSnapshot(
      storeId: json['store_id']?.toString(),
      storeName: json['store_name']?.toString(),
      detectedPublicIp: json['detected_public_ip']?.toString(),
      ssid: json['ssid']?.toString(),
      canManageNetworks: json['can_manage_networks'] == true,
      networks: rawNetworks
          .map((item) => StoreNetworkRecord.fromJson(
                Map<String, dynamic>.from(item as Map),
              ))
          .toList(),
    );
  }
}

class LoginPolicyService {
  final SupabaseClient supabase;
  final DeviceContextService deviceContextService;

  LoginPolicyService(
    this.supabase, {
    this.deviceContextService = const DeviceContextService(),
  });

  Future<LoginPolicyDecision> checkLoginPolicy() async {
    final context = await deviceContextService.load();
    final data = await _invokePolicy({
      'action': 'check_login_policy',
      'platform': context.platform,
      'ssid': context.ssid,
    });

    final decision = LoginPolicyDecision.fromJson(data);
    if (_shouldBypassIosDebugPolicy(decision, context)) {
      return LoginPolicyDecision(
        allowed: true,
        message: decision.message,
        reasonCode: 'ios_debug_bypass',
        detectedPublicIp: decision.detectedPublicIp,
        role: decision.role,
        storeName: decision.storeName,
        storeId: decision.storeId,
        ssid: decision.ssid,
        canManageNetworks: decision.canManageNetworks,
      );
    }
    if (!decision.allowed) {
      throw LoginPolicyException(
        decision.message.isEmpty ? '로그인이 허용되지 않습니다.' : decision.message,
      );
    }
    return decision;
  }

  Future<void> bootstrapSignupNetwork({
    required String storeName,
  }) async {
    final context = await deviceContextService.load();
    final data = await _invokePolicy({
      'action': 'bootstrap_signup_network',
      'platform': context.platform,
      'ssid': context.ssid,
      'store_name': storeName,
    });

    if (data['success'] == false) {
      throw LoginPolicyException(
        (data['message'] ?? '매장 네트워크를 등록하지 못했습니다.').toString(),
      );
    }
  }

  Future<StoreNetworkSnapshot> fetchStoreNetworks({String? storeId}) async {
    final context = await deviceContextService.load();
    final data = await _invokePolicy({
      'action': 'list_store_networks',
      'platform': context.platform,
      'ssid': context.ssid,
      if (storeId != null && storeId.isNotEmpty) 'store_id': storeId,
    });
    return StoreNetworkSnapshot.fromJson(data);
  }

  Future<StoreNetworkSnapshot> registerCurrentNetwork({
    String? storeId,
    String? storeName,
    String? label,
  }) async {
    final context = await deviceContextService.load();
    final data = await _invokePolicy({
      'action': 'register_current_network',
      'platform': context.platform,
      'ssid': context.ssid,
      if (storeId != null && storeId.isNotEmpty) 'store_id': storeId,
      if (storeName != null && storeName.isNotEmpty) 'store_name': storeName,
      if (label != null && label.isNotEmpty) 'label': label,
    });
    return StoreNetworkSnapshot.fromJson(data);
  }

  Future<StoreNetworkSnapshot> deactivateNetwork({
    required String networkId,
    String? storeId,
  }) async {
    final context = await deviceContextService.load();
    final data = await _invokePolicy({
      'action': 'deactivate_store_network',
      'platform': context.platform,
      'ssid': context.ssid,
      'network_id': networkId,
      if (storeId != null && storeId.isNotEmpty) 'store_id': storeId,
    });
    return StoreNetworkSnapshot.fromJson(data);
  }

  Future<Map<String, dynamic>> _invokePolicy(Map<String, dynamic> body) async {
    final accessToken = supabase.auth.currentSession?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      throw const LoginPolicyException('로그인 세션이 없습니다.');
    }

    final response = await supabase.functions.invoke(
      'auth-policy',
      body: {
        ...body,
        'access_token': accessToken,
      },
    );

    final data = _asMap(response.data);
    if (response.status >= 400) {
      throw LoginPolicyException(
        (data['message'] ?? '로그인 정책을 확인하지 못했습니다.').toString(),
      );
    }

    return data;
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) {
      return data.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{};
  }

  bool _shouldBypassIosDebugPolicy(
    LoginPolicyDecision decision,
    DeviceContext context,
  ) {
    return kDebugMode &&
        context.platform == 'ios' &&
        decision.reasonCode == 'staff_network_blocked';
  }
}
