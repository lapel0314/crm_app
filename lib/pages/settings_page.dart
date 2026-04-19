import 'package:crm_app/pages/login_page.dart';
import 'package:crm_app/services/login_policy_service.dart';
import 'package:crm_app/utils/store_utils.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class SettingsPage extends StatefulWidget {
  final String role;
  final String currentStore;

  const SettingsPage({
    super.key,
    required this.role,
    required this.currentStore,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool isLoading = true;
  Map<String, dynamic>? myProfile;
  List<Map<String, dynamic>> members = [];
  final loginPolicyService = LoginPolicyService(supabase);
  StoreNetworkSnapshot? networkSnapshot;
  bool isNetworkLoading = false;

  bool get canViewAllStores => isPrivilegedRole(widget.role);
  bool get canManageStoreNetworks => canManageNetworks(widget.role);

  @override
  void initState() {
    super.initState();
    _loadSettings();
    if (canManageStoreNetworks) {
      _loadStoreNetworks();
    }
  }

  Future<void> _loadSettings() async {
    setState(() {
      isLoading = true;
    });

    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() {
        isLoading = false;
      });
      return;
    }

    try {
      final results = await Future.wait<List<dynamic>>([
        supabase.from('profiles').select().eq('id', user.id),
        supabase
            .from('profiles')
            .select()
            .eq('approval_status', 'approved')
            .order('store')
            .order('role')
            .order('name'),
      ]);

      final profileRows =
          results[0].map((row) => Map<String, dynamic>.from(row)).toList();
      var memberRows =
          results[1].map((row) => Map<String, dynamic>.from(row)).toList();

      memberRows = memberRows
          .where((row) => !isPrivilegedRole(row['role']))
          .map((row) {
            return {
              ...row,
              'store': normalizeStoreName(row['store']),
            };
          })
          .where((row) =>
              canViewAllStores ||
              isSameStore(row['store'], widget.currentStore))
          .toList();

      if (!mounted) return;
      setState(() {
        myProfile = profileRows.isEmpty ? null : profileRows.first;
        members = memberRows;
        isLoading = false;
      });
    } catch (e) {
      debugPrint('settings load failed: $e');
      if (!mounted) return;
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> logout(BuildContext context) async {
    try {
      await supabase.auth.signOut();
      if (!context.mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    } catch (e) {
      debugPrint('logout failed: $e');
    }
  }

  Future<void> _loadStoreNetworks() async {
    setState(() {
      isNetworkLoading = true;
    });

    try {
      final snapshot = await loginPolicyService.fetchStoreNetworks();
      if (!mounted) return;
      setState(() {
        networkSnapshot = snapshot;
        isNetworkLoading = false;
      });
    } catch (e) {
      debugPrint('store networks load failed: $e');
      if (!mounted) return;
      setState(() {
        isNetworkLoading = false;
      });
    }
  }

  Future<void> _registerCurrentNetwork() async {
    try {
      final snapshot = await loginPolicyService.registerCurrentNetwork(
        storeId: networkSnapshot?.storeId,
        storeName: widget.currentStore,
      );
      if (!mounted) return;
      setState(() {
        networkSnapshot = snapshot;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('현재 네트워크를 허용 목록에 등록했습니다.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('네트워크 등록에 실패했습니다: $e')),
      );
    }
  }

  Future<void> _deactivateNetwork(String networkId) async {
    try {
      final snapshot = await loginPolicyService.deactivateNetwork(
        networkId: networkId,
        storeId: networkSnapshot?.storeId,
      );
      if (!mounted) return;
      setState(() {
        networkSnapshot = snapshot;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('허용 네트워크를 비활성화했습니다.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('네트워크 비활성화에 실패했습니다: $e')),
      );
    }
  }

  String _value(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? '-' : text;
  }

  String _displayStore(dynamic value) {
    final store = normalizeStoreName(value);
    return store.isEmpty ? '-' : store;
  }

  String _initials(Map<String, dynamic> row) {
    final name = _value(row['name']);
    if (name != '-') return name.characters.take(2).toString().toUpperCase();
    final email = _value(row['email']);
    return email.characters.take(2).toString().toUpperCase();
  }

  Map<String, List<Map<String, dynamic>>> _groupedMembers() {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final member in members) {
      final store = _displayStore(member['store']);
      grouped.putIfAbsent(store, () => []).add(member);
    }
    return grouped;
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

  Widget _tabRail() {
    const tabs = [
      (Icons.person_outline_rounded, '내 정보'),
      (Icons.groups_2_outlined, '매장 그룹'),
      (Icons.logout_rounded, '로그아웃'),
    ];

    return Container(
      width: 200,
      padding: const EdgeInsets.all(12),
      decoration: _cardDecoration(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final tab in tabs)
            InkWell(
              onTap: tab.$2 == '로그아웃' ? () => logout(context) : null,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: tab.$2 == '내 정보'
                      ? const Color(0xFFC94C6E).withValues(alpha: 0.10)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      tab.$1,
                      size: 17,
                      color: tab.$2 == '내 정보'
                          ? const Color(0xFFC94C6E)
                          : const Color(0xFF6B7280),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      tab.$2,
                      style: TextStyle(
                        color: tab.$2 == '내 정보'
                            ? const Color(0xFFC94C6E)
                            : const Color(0xFF6B7280),
                        fontSize: 13,
                        fontWeight: tab.$2 == '내 정보'
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _readonlyField(String label, String value) {
    return SizedBox(
      width: 260,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF374151),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xFFFAFAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE8E9EF)),
            ),
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF111827),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileCard() {
    final user = supabase.auth.currentUser;
    final profile = myProfile ?? {};
    final name = _value(profile['name']);
    final email = user?.email ?? _value(profile['email']);
    final store = _displayStore(profile['store'] ?? widget.currentStore);
    final mobile = MediaQuery.of(context).size.width < 900;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '내 정보',
            style: TextStyle(
              color: Color(0xFF111827),
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 20),
          mobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _avatar(name, email),
                    const SizedBox(height: 14),
                    _profileTextBlock(name, email, profile, store),
                  ],
                )
              : Row(
                  children: [
                    _avatar(name, email),
                    const SizedBox(width: 18),
                    Expanded(
                      child: _profileTextBlock(name, email, profile, store),
                    ),
                  ],
                ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              _readonlyField('이름', name),
              _readonlyField('이메일', email),
              _readonlyField('휴대폰번호', _value(profile['phone'])),
              _readonlyField('권한', _value(profile['role'] ?? widget.role)),
              _readonlyField('매장', store),
              _readonlyField('계정 상태', _value(profile['approval_status'])),
            ],
          ),
        ],
      ),
    );
  }

  Widget _avatar(String name, String email) {
    return Container(
      width: 64,
      height: 64,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Color(0xFFC94C6E),
        shape: BoxShape.circle,
      ),
      child: Text(
        _initials({'name': name, 'email': email}),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _profileTextBlock(
    String name,
    String email,
    Map<String, dynamic> profile,
    String store,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name == '-' ? email : name,
          style: const TextStyle(
            color: Color(0xFF111827),
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          '${_value(profile['role'] ?? widget.role)} $store',
          style: const TextStyle(
            color: Color(0xFF6B7280),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          '내 정보는 관리자 승인 정보 기준으로 표시됩니다.',
          style: TextStyle(
            color: Color(0xFF9CA3AF),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _teamGroups() {
    final grouped = _groupedMembers();

    return Container(
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 12),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '매장별 그룹',
                        style: TextStyle(
                          color: Color(0xFF111827),
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '같은 매장 직원만 볼 수 있습니다. 대표/개발자는 전체 매장을 조회합니다.',
                        style: TextStyle(
                          color: Color(0xFF9CA3AF),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                _storeBadge(canViewAllStores ? '전체 매장' : widget.currentStore),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF3F4F6)),
          if (grouped.isEmpty)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Center(child: Text('표시할 매장 구성원이 없습니다.')),
            )
          else
            ...grouped.entries.map((entry) => _storeGroup(entry.key, entry.value)),
        ],
      ),
    );
  }

  Widget _storeGroup(String store, List<Map<String, dynamic>> rows) {
    final managers =
        rows.where((row) => _value(row['role']).contains('매장')).toList();
    final staff =
        rows.where((row) => !_value(row['role']).contains('매장')).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _storeBadge(store),
              const SizedBox(width: 10),
              Text(
                '${rows.length}명',
                style: const TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (managers.isNotEmpty) ...[
            const Text(
              '매장',
              style: TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            ...managers.map(_memberRow),
            const SizedBox(height: 10),
          ],
          if (staff.isNotEmpty) ...[
            const Text(
              '직원',
              style: TextStyle(
                color: Color(0xFF9CA3AF),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            ...staff.map(_memberRow),
          ],
          const Divider(height: 22, color: Color(0xFFF3F4F6)),
        ],
      ),
    );
  }

  Widget _memberRow(Map<String, dynamic> member) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE8E9EF)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFFC94C6E),
              shape: BoxShape.circle,
            ),
            child: Text(
              _initials(member),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _value(member['name']),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _value(member['email']),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          _roleBadge(_value(member['role'])),
        ],
      ),
    );
  }

  Widget _storeBadge(String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFC94C6E).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        value.isEmpty ? '-' : value,
        style: const TextStyle(
          color: Color(0xFFC94C6E),
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _roleBadge(String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        value,
        style: const TextStyle(
          color: Color(0xFF6B7280),
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _networkManagementCard() {
    final snapshot = networkSnapshot;
    final networks = snapshot?.networks ?? const <StoreNetworkRecord>[];

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '매장 네트워크',
            style: TextStyle(
              color: Color(0xFF111827),
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '사원 로그인은 모바일 + 등록된 매장 공인 IP에서만 허용됩니다.',
            style: TextStyle(
              color: Color(0xFF9CA3AF),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              _readonlyField('매장', snapshot?.storeName ?? widget.currentStore),
              _readonlyField('현재 공인 IP', snapshot?.detectedPublicIp ?? '-'),
              _readonlyField('현재 Wi-Fi SSID', snapshot?.ssid ?? '-'),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: isNetworkLoading ? null : _registerCurrentNetwork,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC94C6E),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.wifi_protected_setup_rounded, size: 18),
                label: const Text('현재 네트워크 등록'),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: isNetworkLoading ? null : _loadStoreNetworks,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('새로고침'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (isNetworkLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (networks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text(
                '등록된 허용 공인 IP가 없습니다.',
                style: TextStyle(
                  color: Color(0xFF6B7280),
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            ...networks.map(
              (network) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE8E9EF)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.public_rounded,
                      size: 18,
                      color: Color(0xFF6B7280),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            network.publicIp,
                            style: const TextStyle(
                              color: Color(0xFF111827),
                              fontWeight: FontWeight.w800,
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
                    const SizedBox(width: 10),
                    _roleBadge(network.isActive ? '활성' : '비활성'),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: '비활성화',
                      onPressed: network.isActive
                          ? () => _deactivateNetwork(network.id)
                          : null,
                      icon: const Icon(Icons.block_rounded),
                    ),
                  ],
                ),
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
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(mobile ? 14 : 28),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: mobile
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: _tabRail(),
                            ),
                            const SizedBox(height: 18),
                            _profileCard(),
                            const SizedBox(height: 18),
                            if (canManageStoreNetworks) ...[
                              _networkManagementCard(),
                              const SizedBox(height: 18),
                            ],
                            _teamGroups(),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _tabRail(),
                            const SizedBox(width: 22),
                            Expanded(
                              child: Column(
                                children: [
                                  _profileCard(),
                                  const SizedBox(height: 18),
                                  if (canManageStoreNetworks) ...[
                                    _networkManagementCard(),
                                    const SizedBox(height: 18),
                                  ],
                                  _teamGroups(),
                                ],
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
    );
  }
}
