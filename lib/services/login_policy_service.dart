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
  final String? wifiIp;
  final String? wifiGatewayIp;
  final String? wifiBssid;
  final bool canManageNetworks;
  final bool canModifyNetworks;

  const LoginPolicyDecision({
    required this.allowed,
    required this.message,
    required this.reasonCode,
    required this.detectedPublicIp,
    required this.role,
    required this.storeName,
    required this.storeId,
    required this.ssid,
    required this.wifiIp,
    required this.wifiGatewayIp,
    required this.wifiBssid,
    required this.canManageNetworks,
    required this.canModifyNetworks,
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
      wifiIp: json['wifi_ip']?.toString(),
      wifiGatewayIp: json['wifi_gateway_ip']?.toString(),
      wifiBssid: json['wifi_bssid']?.toString(),
      canManageNetworks: json['can_manage_networks'] == true,
      canModifyNetworks: json['can_modify_networks'] == true,
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

class StoreNetworkRequestRecord {
  final String id;
  final String publicIp;
  final String? label;
  final String? ssidHint;
  final String? wifiIp;
  final String? wifiGatewayIp;
  final String? requestedByName;
  final String? requestedAt;

  const StoreNetworkRequestRecord({
    required this.id,
    required this.publicIp,
    required this.label,
    required this.ssidHint,
    required this.wifiIp,
    required this.wifiGatewayIp,
    required this.requestedByName,
    required this.requestedAt,
  });

  factory StoreNetworkRequestRecord.fromJson(Map<String, dynamic> json) {
    return StoreNetworkRequestRecord(
      id: json['id'].toString(),
      publicIp: (json['public_ip'] ?? '').toString(),
      label: json['label']?.toString(),
      ssidHint: json['ssid_hint']?.toString(),
      wifiIp: json['wifi_ip']?.toString(),
      wifiGatewayIp: json['wifi_gateway_ip']?.toString(),
      requestedByName: json['requested_by_name']?.toString(),
      requestedAt: json['requested_at']?.toString(),
    );
  }
}

class StoreNetworkHistoryRecord {
  final String id;
  final String publicIp;
  final String status;
  final String? label;
  final String? ssidHint;
  final String? requestedByName;
  final String? reviewedByName;
  final String? requestedAt;
  final String? reviewedAt;

  const StoreNetworkHistoryRecord({
    required this.id,
    required this.publicIp,
    required this.status,
    required this.label,
    required this.ssidHint,
    required this.requestedByName,
    required this.reviewedByName,
    required this.requestedAt,
    required this.reviewedAt,
  });

  factory StoreNetworkHistoryRecord.fromJson(Map<String, dynamic> json) {
    return StoreNetworkHistoryRecord(
      id: json['id'].toString(),
      publicIp: (json['public_ip'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      label: json['label']?.toString(),
      ssidHint: json['ssid_hint']?.toString(),
      requestedByName: json['requested_by_name']?.toString(),
      reviewedByName: json['reviewed_by_name']?.toString(),
      requestedAt: json['requested_at']?.toString(),
      reviewedAt: json['reviewed_at']?.toString(),
    );
  }
}

class StoreSecuritySummary {
  final int activeNetworkCount;
  final int inactiveNetworkCount;
  final int pendingRequestCount;
  final int staffCount;
  final String? recentStaffLoginAt;
  final String? recentStaffLoginPublicIp;
  final String? recentStaffLoginName;

  const StoreSecuritySummary({
    required this.activeNetworkCount,
    required this.inactiveNetworkCount,
    required this.pendingRequestCount,
    required this.staffCount,
    required this.recentStaffLoginAt,
    required this.recentStaffLoginPublicIp,
    required this.recentStaffLoginName,
  });

  factory StoreSecuritySummary.fromJson(Map<String, dynamic> json) {
    int number(dynamic value) => int.tryParse((value ?? '0').toString()) ?? 0;
    return StoreSecuritySummary(
      activeNetworkCount: number(json['active_network_count']),
      inactiveNetworkCount: number(json['inactive_network_count']),
      pendingRequestCount: number(json['pending_request_count']),
      staffCount: number(json['staff_count']),
      recentStaffLoginAt: json['recent_staff_login_at']?.toString(),
      recentStaffLoginPublicIp:
          json['recent_staff_login_public_ip']?.toString(),
      recentStaffLoginName: json['recent_staff_login_name']?.toString(),
    );
  }
}

class StoreNetworkSnapshot {
  final String? storeId;
  final String? storeName;
  final String? detectedPublicIp;
  final String? ssid;
  final String? wifiIp;
  final String? wifiGatewayIp;
  final String? wifiBssid;
  final bool canManageNetworks;
  final bool canModifyNetworks;
  final StoreSecuritySummary securitySummary;
  final List<StoreNetworkRecord> networks;
  final List<StoreNetworkRequestRecord> pendingRequests;
  final List<StoreNetworkHistoryRecord> requestHistory;

  const StoreNetworkSnapshot({
    required this.storeId,
    required this.storeName,
    required this.detectedPublicIp,
    required this.ssid,
    required this.wifiIp,
    required this.wifiGatewayIp,
    required this.wifiBssid,
    required this.canManageNetworks,
    required this.canModifyNetworks,
    required this.securitySummary,
    required this.networks,
    required this.pendingRequests,
    required this.requestHistory,
  });

  factory StoreNetworkSnapshot.fromJson(Map<String, dynamic> json) {
    final rawNetworks = (json['networks'] as List?) ?? const [];
    final rawPendingRequests =
        (json['pending_network_requests'] as List?) ?? const [];
    final rawRequestHistory =
        (json['network_request_history'] as List?) ?? const [];
    return StoreNetworkSnapshot(
      storeId: json['store_id']?.toString(),
      storeName: json['store_name']?.toString(),
      detectedPublicIp: json['detected_public_ip']?.toString(),
      ssid: json['ssid']?.toString(),
      wifiIp: json['wifi_ip']?.toString(),
      wifiGatewayIp: json['wifi_gateway_ip']?.toString(),
      wifiBssid: json['wifi_bssid']?.toString(),
      canManageNetworks: json['can_manage_networks'] == true,
      canModifyNetworks: json['can_modify_networks'] == true,
      securitySummary: StoreSecuritySummary.fromJson(
        Map<String, dynamic>.from((json['security_summary'] as Map?) ?? {}),
      ),
      networks: rawNetworks
          .map((item) => StoreNetworkRecord.fromJson(
                Map<String, dynamic>.from(item as Map),
              ))
          .toList(),
      pendingRequests: rawPendingRequests
          .map((item) => StoreNetworkRequestRecord.fromJson(
                Map<String, dynamic>.from(item as Map),
              ))
          .toList(),
      requestHistory: rawRequestHistory
          .map((item) => StoreNetworkHistoryRecord.fromJson(
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
      ..._networkContext(context),
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
        wifiIp: decision.wifiIp,
        wifiGatewayIp: decision.wifiGatewayIp,
        wifiBssid: decision.wifiBssid,
        canManageNetworks: decision.canManageNetworks,
        canModifyNetworks: decision.canModifyNetworks,
      );
    }
    if (!decision.allowed) {
      throw LoginPolicyException(
        _policyBlockMessage(decision),
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
      ..._networkContext(context),
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
      ..._networkContext(context),
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
      ..._networkContext(context),
      if (storeId != null && storeId.isNotEmpty) 'store_id': storeId,
      if (storeName != null && storeName.isNotEmpty) 'store_name': storeName,
      if (label != null && label.isNotEmpty) 'label': label,
    });
    return StoreNetworkSnapshot.fromJson(data);
  }

  Future<StoreNetworkSnapshot> requestCurrentNetwork({
    String? storeId,
    String? storeName,
    String? label,
  }) async {
    final context = await deviceContextService.load();
    final data = await _invokePolicy({
      'action': 'request_current_network',
      ..._networkContext(context),
      if (storeId != null && storeId.isNotEmpty) 'store_id': storeId,
      if (storeName != null && storeName.isNotEmpty) 'store_name': storeName,
      if (label != null && label.isNotEmpty) 'label': label,
    });
    return StoreNetworkSnapshot.fromJson(data);
  }

  Future<StoreNetworkSnapshot> approveNetworkRequest({
    required String requestId,
  }) async {
    final context = await deviceContextService.load();
    final data = await _invokePolicy({
      'action': 'approve_network_request',
      ..._networkContext(context),
      'request_id': requestId,
    });
    return StoreNetworkSnapshot.fromJson(data);
  }

  Future<StoreNetworkSnapshot> rejectNetworkRequest({
    required String requestId,
  }) async {
    final context = await deviceContextService.load();
    final data = await _invokePolicy({
      'action': 'reject_network_request',
      ..._networkContext(context),
      'request_id': requestId,
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
      ..._networkContext(context),
      'network_id': networkId,
      if (storeId != null && storeId.isNotEmpty) 'store_id': storeId,
    });
    return StoreNetworkSnapshot.fromJson(data);
  }

  Future<StoreNetworkSnapshot> updateNetworkLabel({
    required String networkId,
    required String label,
    String? storeId,
  }) async {
    final context = await deviceContextService.load();
    final data = await _invokePolicy({
      'action': 'update_store_network_label',
      ..._networkContext(context),
      'network_id': networkId,
      'label': label,
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

  Map<String, dynamic> _networkContext(DeviceContext context) {
    return {
      'platform': context.platform,
      'ssid': context.ssid,
      'wifi_ip': context.wifiIp,
      'wifi_gateway_ip': context.wifiGatewayIp,
      'wifi_bssid': context.wifiBssid,
    };
  }

  String _policyBlockMessage(LoginPolicyDecision decision) {
    final message =
        decision.message.isEmpty ? '로그인이 허용되지 않습니다.' : decision.message;
    final details = <String>[
      if ((decision.storeName ?? '').trim().isNotEmpty)
        '매장: ${decision.storeName!.trim()}',
      if ((decision.detectedPublicIp ?? '').trim().isNotEmpty)
        '현재 공인 IP: ${decision.detectedPublicIp!.trim()}',
      if ((decision.ssid ?? '').trim().isNotEmpty)
        '현재 Wi-Fi: ${decision.ssid!.trim()}',
      if ((decision.wifiGatewayIp ?? '').trim().isNotEmpty)
        '현재 라우터: ${decision.wifiGatewayIp!.trim()}',
    ];

    if (decision.reasonCode == 'staff_network_blocked') {
      details.add('점장에게 현재 네트워크 등록 요청을 진행해 달라고 요청하세요.');
    }

    return details.isEmpty ? message : '$message\n\n${details.join('\n')}';
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
