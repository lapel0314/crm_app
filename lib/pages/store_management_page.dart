import 'package:crm_app/services/login_policy_service.dart';
import 'package:crm_app/utils/store_utils.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class StoreManagementPage extends StatefulWidget {
  final String role;
  final String currentStore;

  const StoreManagementPage({
    super.key,
    required this.role,
    required this.currentStore,
  });

  @override
  State<StoreManagementPage> createState() => _StoreManagementPageState();
}

class _StoreManagementPageState extends State<StoreManagementPage> {
  final loginPolicyService = LoginPolicyService(supabase);
  List<Map<String, dynamic>> stores = [];
  StoreNetworkSnapshot? selectedSnapshot;
  String? selectedStoreId;
  bool isLoadingStores = true;
  bool isLoadingNetworks = false;

  bool get canModifyNetworks => isPrivilegedRole(widget.role);

  @override
  void initState() {
    super.initState();
    _loadStores();
  }

  Future<void> _loadStores() async {
    setState(() {
      isLoadingStores = true;
    });

    try {
      final rows = await supabase
          .from('stores')
          .select('id, name, normalized_name, is_active')
          .order('name');
      final storeRows =
          rows.map((row) => Map<String, dynamic>.from(row)).toList();
      if (!mounted) return;
      setState(() {
        stores = storeRows;
        isLoadingStores = false;
      });

      if (storeRows.isNotEmpty) {
        final currentNormalized = normalizeStoreName(widget.currentStore);
        final currentStore = storeRows.firstWhere(
          (store) => normalizeStoreName(store['name']) == currentNormalized,
          orElse: () => storeRows.first,
        );
        await _selectStore(currentStore['id'].toString());
      }
    } catch (e) {
      debugPrint('store management load stores failed: $e');
      if (!mounted) return;
      setState(() {
        isLoadingStores = false;
      });
      _showSnack('매장 목록을 불러오지 못했습니다: $e');
    }
  }

  Future<void> _selectStore(String storeId) async {
    setState(() {
      selectedStoreId = storeId;
      isLoadingNetworks = true;
    });

    try {
      final snapshot =
          await loginPolicyService.fetchStoreNetworks(storeId: storeId);
      if (!mounted) return;
      setState(() {
        selectedSnapshot = snapshot;
        isLoadingNetworks = false;
      });
    } catch (e) {
      debugPrint('store management load networks failed: $e');
      if (!mounted) return;
      setState(() {
        isLoadingNetworks = false;
      });
      _showSnack('매장 네트워크를 불러오지 못했습니다: $e');
    }
  }

  Future<void> _registerCurrentNetwork() async {
    if (selectedStoreId == null) return;
    try {
      final snapshot = await loginPolicyService.registerCurrentNetwork(
        storeId: selectedStoreId,
      );
      if (!mounted) return;
      setState(() {
        selectedSnapshot = snapshot;
      });
      _showSnack('현재 네트워크를 허용 목록에 등록했습니다.');
    } catch (e) {
      _showSnack('네트워크 등록에 실패했습니다: $e');
    }
  }

  Future<void> _approveRequest(String requestId) async {
    try {
      final snapshot = await loginPolicyService.approveNetworkRequest(
        requestId: requestId,
      );
      if (!mounted) return;
      setState(() {
        selectedSnapshot = snapshot;
        selectedStoreId = snapshot.storeId ?? selectedStoreId;
      });
      _showSnack('네트워크 등록 요청을 승인했습니다.');
    } catch (e) {
      _showSnack('요청 승인에 실패했습니다: $e');
    }
  }

  Future<void> _rejectRequest(String requestId) async {
    try {
      final snapshot = await loginPolicyService.rejectNetworkRequest(
        requestId: requestId,
      );
      if (!mounted) return;
      setState(() {
        selectedSnapshot = snapshot;
        selectedStoreId = snapshot.storeId ?? selectedStoreId;
      });
      _showSnack('네트워크 등록 요청을 거절했습니다.');
    } catch (e) {
      _showSnack('요청 거절에 실패했습니다: $e');
    }
  }

  Future<void> _deactivateNetwork(String networkId) async {
    if (selectedStoreId == null) return;
    try {
      final snapshot = await loginPolicyService.deactivateNetwork(
        networkId: networkId,
        storeId: selectedStoreId,
      );
      if (!mounted) return;
      setState(() {
        selectedSnapshot = snapshot;
      });
      _showSnack('허용 네트워크를 비활성화했습니다.');
    } catch (e) {
      _showSnack('네트워크 비활성화에 실패했습니다: $e');
    }
  }

  Future<void> _editNetworkLabel(StoreNetworkRecord network) async {
    final label = await _showLabelDialog(network.label ?? '');
    if (label == null || selectedStoreId == null) return;

    try {
      final snapshot = await loginPolicyService.updateNetworkLabel(
        networkId: network.id,
        storeId: selectedStoreId,
        label: label,
      );
      if (!mounted) return;
      setState(() {
        selectedSnapshot = snapshot;
      });
      _showSnack('네트워크 메모를 수정했습니다.');
    } catch (e) {
      _showSnack('네트워크 메모 수정에 실패했습니다: $e');
    }
  }

  Future<String?> _showLabelDialog(String initialValue) async {
    final controller = TextEditingController(text: initialValue);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Text(
          '허용 IP 메모 수정',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '메모/별칭',
            hintText: '예: 이대점 메인 공유기',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC94C6E),
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFFE8E9EF)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0A000000),
          blurRadius: 8,
          offset: Offset(0, 2),
        ),
      ],
    );
  }

  Widget _badge(String text, {Color color = const Color(0xFF6B7280)}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _storeList(bool mobile) {
    if (isLoadingStores) {
      return const Center(child: CircularProgressIndicator());
    }

    if (stores.isEmpty) {
      return const Center(child: Text('등록된 매장이 없습니다.'));
    }

    return Container(
      width: mobile ? double.infinity : 280,
      padding: const EdgeInsets.all(12),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              '매장 목록',
              style: TextStyle(
                color: Color(0xFF111827),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 6),
          ...stores.map((store) {
            final id = store['id'].toString();
            final selected = id == selectedStoreId;
            final name = normalizeStoreName(store['name']);
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: InkWell(
                onTap: () => _selectStore(id),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFFC94C6E).withValues(alpha: 0.10)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          name.isEmpty ? '-' : name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected
                                ? const Color(0xFFC94C6E)
                                : const Color(0xFF374151),
                            fontWeight:
                                selected ? FontWeight.w900 : FontWeight.w700,
                          ),
                        ),
                      ),
                      if (store['is_active'] == false)
                        _badge('비활성', color: const Color(0xFF9CA3AF)),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _networkPanel() {
    final snapshot = selectedSnapshot;
    final networks = snapshot?.networks ?? const <StoreNetworkRecord>[];
    final pending =
        snapshot?.pendingRequests ?? const <StoreNetworkRequestRecord>[];

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _cardDecoration(),
      child: isLoadingNetworks
          ? const Center(child: CircularProgressIndicator())
          : snapshot == null
              ? const Center(child: Text('매장을 선택해 주세요.'))
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              snapshot.storeName ?? '매장 관리',
                              style: const TextStyle(
                                color: Color(0xFF111827),
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          if (pending.isNotEmpty)
                            _badge('승인 대기 ${pending.length}건',
                                color: const Color(0xFFD97706)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '매장별 허용 공인 IP와 승인 대기 요청을 관리합니다.',
                        style: TextStyle(
                          color: Color(0xFF9CA3AF),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _summaryGrid(snapshot.securitySummary),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _badge(
                              '현재 공인 IP: ${snapshot.detectedPublicIp ?? '-'}'),
                          if ((snapshot.ssid ?? '').trim().isNotEmpty)
                            _badge('SSID: ${snapshot.ssid!.trim()}'),
                          if ((snapshot.wifiGatewayIp ?? '').trim().isNotEmpty)
                            _badge('라우터: ${snapshot.wifiGatewayIp!.trim()}'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          ElevatedButton.icon(
                            onPressed: canModifyNetworks
                                ? _registerCurrentNetwork
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFC94C6E),
                              foregroundColor: Colors.white,
                              elevation: 0,
                            ),
                            icon: const Icon(Icons.add_link_rounded, size: 18),
                            label: const Text('현재 네트워크를 이 매장에 등록'),
                          ),
                          OutlinedButton.icon(
                            onPressed: selectedStoreId == null
                                ? null
                                : () => _selectStore(selectedStoreId!),
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('새로고침'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _sectionTitle('승인 대기 요청'),
                      const SizedBox(height: 10),
                      if (pending.isEmpty)
                        _emptyText('승인 대기 중인 요청이 없습니다.')
                      else
                        ...pending.map(_requestTile),
                      const SizedBox(height: 24),
                      _sectionTitle('허용 네트워크'),
                      const SizedBox(height: 10),
                      if (networks.isEmpty)
                        _emptyText('등록된 허용 공인 IP가 없습니다.')
                      else
                        ...networks.map(_networkTile),
                      const SizedBox(height: 24),
                      _sectionTitle('승인/거절 이력'),
                      const SizedBox(height: 10),
                      if (snapshot.requestHistory.isEmpty)
                        _emptyText('처리된 네트워크 요청 이력이 없습니다.')
                      else
                        ...snapshot.requestHistory.map(_historyTile),
                    ],
                  ),
                ),
    );
  }

  Widget _summaryGrid(StoreSecuritySummary summary) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile = constraints.maxWidth < 620;
        final itemWidth =
            mobile ? constraints.maxWidth : (constraints.maxWidth - 24) / 3;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _summaryCard(
                '활성 허용 IP', '${summary.activeNetworkCount}개', itemWidth),
            _summaryCard('승인 대기', '${summary.pendingRequestCount}건', itemWidth),
            _summaryCard('사원 수', '${summary.staffCount}명', itemWidth),
            _summaryCard(
                '비활성 IP', '${summary.inactiveNetworkCount}개', itemWidth),
            _summaryCard(
              '최근 사원 접속',
              (summary.recentStaffLoginAt ?? '').trim().isEmpty
                  ? '-'
                  : summary.recentStaffLoginAt!.split('T').first,
              itemWidth,
              subtitle: summary.recentStaffLoginName,
            ),
            _summaryCard(
              '마지막 접속 IP',
              summary.recentStaffLoginPublicIp ?? '-',
              itemWidth,
            ),
          ],
        );
      },
    );
  }

  Widget _summaryCard(
    String title,
    String value,
    double width, {
    String? subtitle,
  }) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE8E9EF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF111827),
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            if ((subtitle ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!.trim(),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFF111827),
        fontSize: 15,
        fontWeight: FontWeight.w900,
      ),
    );
  }

  Widget _emptyText(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE8E9EF)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF6B7280),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _requestTile(StoreNetworkRequestRecord request) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        children: [
          const Icon(Icons.pending_actions_rounded, color: Color(0xFFD97706)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.publicIp,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if ((request.requestedByName ?? '').trim().isNotEmpty)
                      '요청자: ${request.requestedByName!.trim()}',
                    if ((request.label ?? '').trim().isNotEmpty)
                      request.label!.trim(),
                    if ((request.ssidHint ?? '').trim().isNotEmpty)
                      'SSID: ${request.ssidHint!.trim()}',
                    if ((request.wifiGatewayIp ?? '').trim().isNotEmpty)
                      '라우터: ${request.wifiGatewayIp!.trim()}',
                    if ((request.requestedAt ?? '').trim().isNotEmpty)
                      '요청일: ${request.requestedAt!.split('T').first}',
                  ].join(' · '),
                  style: const TextStyle(
                    color: Color(0xFF92400E),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '승인',
            onPressed: () => _approveRequest(request.id),
            icon: const Icon(Icons.check_circle_rounded),
          ),
          IconButton(
            tooltip: '거절',
            onPressed: () => _rejectRequest(request.id),
            icon: const Icon(Icons.cancel_rounded),
          ),
        ],
      ),
    );
  }

  Widget _networkTile(StoreNetworkRecord network) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE8E9EF)),
      ),
      child: Row(
        children: [
          const Icon(Icons.public_rounded, color: Color(0xFF6B7280)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  network.publicIp,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if ((network.label ?? '').trim().isNotEmpty)
                      network.label!.trim(),
                    if ((network.ssidHint ?? '').trim().isNotEmpty)
                      'SSID: ${network.ssidHint!.trim()}',
                    if ((network.lastSeenAt ?? '').trim().isNotEmpty)
                      '최근 확인: ${network.lastSeenAt!.split('T').first}',
                  ].join(' · '),
                  style: const TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          _badge(network.isActive ? '활성' : '비활성'),
          const SizedBox(width: 8),
          IconButton(
            tooltip: '메모 수정',
            onPressed: () => _editNetworkLabel(network),
            icon: const Icon(Icons.edit_note_rounded),
          ),
          IconButton(
            tooltip: '비활성화',
            onPressed:
                network.isActive ? () => _deactivateNetwork(network.id) : null,
            icon: const Icon(Icons.block_rounded),
          ),
        ],
      ),
    );
  }

  Widget _historyTile(StoreNetworkHistoryRecord history) {
    final approved = history.status == 'approved';
    final color = approved ? const Color(0xFF059669) : const Color(0xFFDC2626);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          Icon(
            approved ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  history.publicIp,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    approved ? '승인' : '거절',
                    if ((history.requestedByName ?? '').trim().isNotEmpty)
                      '요청자: ${history.requestedByName!.trim()}',
                    if ((history.reviewedByName ?? '').trim().isNotEmpty)
                      '처리자: ${history.reviewedByName!.trim()}',
                    if ((history.label ?? '').trim().isNotEmpty)
                      history.label!.trim(),
                    if ((history.reviewedAt ?? '').trim().isNotEmpty)
                      '처리일: ${history.reviewedAt!.split('T').first}',
                  ].join(' · '),
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.of(context).size.width < 900;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(mobile ? 14 : 28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: mobile
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _storeList(true),
                      const SizedBox(height: 14),
                      SizedBox(height: 720, child: _networkPanel()),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _storeList(false),
                      const SizedBox(width: 18),
                      Expanded(child: _networkPanel()),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
