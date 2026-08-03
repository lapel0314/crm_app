import 'package:flutter/material.dart';
import 'package:crm_app/widgets/app_toast.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crm_app/utils/store_utils.dart';

final supabase = Supabase.instance.client;

class SignupApprovalDashboardPage extends StatefulWidget {
  final String role;

  const SignupApprovalDashboardPage({super.key, required this.role});

  @override
  State<SignupApprovalDashboardPage> createState() =>
      _SignupApprovalDashboardPageState();
}

class _SignupApprovalDashboardPageState
    extends State<SignupApprovalDashboardPage> {
  final dateFormat = DateFormat('yyyy-MM-dd HH:mm');
  List<Map<String, dynamic>> users = [];
  bool isLoading = true;

  // 집계는 fetch 시 1회만 계산한다 — 이전에는 매 빌드마다 users 전체를
  // 4~6회 순회해서 좁은 화면에서 프레임 드랍을 유발했다.
  List<Map<String, dynamic>> pendingUsers = [];
  int pendingCount = 0;
  int approvedCount = 0;
  int rejectedCount = 0;
  Map<String, int> roleCounts = {};
  Map<String, int> storeCounts = {};

  bool get isAdmin => isPrivilegedRole(widget.role);

  @override
  void initState() {
    super.initState();
    fetchUsers();
  }

  void _recomputeStats() {
    pendingUsers = [];
    pendingCount = 0;
    approvedCount = 0;
    rejectedCount = 0;
    roleCounts = {};
    storeCounts = {};
    for (final user in users) {
      user['created_at_label'] = _date(user['created_at']);
      final status = _status(user);
      if (status == '대기') {
        pendingCount++;
        pendingUsers.add(user);
      } else if (status == '승인') {
        approvedCount++;
      } else if (status == '반려') {
        rejectedCount++;
      }
      final role = _text(user['role_code'] ?? user['role']);
      roleCounts[role] = (roleCounts[role] ?? 0) + 1;
      final store = _text(user['store']);
      storeCounts[store] = (storeCounts[store] ?? 0) + 1;
    }
  }

  Future<void> fetchUsers() async {
    if (!isAdmin) {
      setState(() => isLoading = false);
      return;
    }
    setState(() => isLoading = true);
    try {
      final rows = await supabase
          .from('profiles')
          .select()
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() {
        users = List<Map<String, dynamic>>.from(rows);
        _recomputeStats();
        isLoading = false;
      });
    } catch (e) {
      debugPrint('signup approval dashboard load failed: $e');
      if (!mounted) return;
      setState(() => isLoading = false);
    }
  }

  Future<void> approveUser(String userId) async {
    try {
      final response = await supabase.functions.invoke(
        'auth-policy',
        body: {
          'action': 'admin_approve_user',
          'access_token': supabase.auth.currentSession?.accessToken,
          'user_id': userId,
        },
      );
      final data = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      if (response.status >= 400 || data['success'] == false) {
        throw Exception((data['message'] ?? '승인에 실패했습니다.').toString());
      }
      await fetchUsers();
      if (!mounted) return;
      showToast(context, '직원 계정을 승인했습니다.');
    } catch (e) {
      debugPrint('dashboard approve failed: $e');
      if (!mounted) return;
      showToast(context, '승인 실패: $e', error: true);
    }
  }

  String _text(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? '-' : text;
  }

  String _status(Map<String, dynamic> user) {
    final status = _text(user['approval_status']).toLowerCase();
    if (status == '-' || status == 'pending') return '대기';
    if (status == 'approved') return '승인';
    if (status == 'rejected') return '반려';
    return _text(user['approval_status']);
  }

  String _date(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    return parsed == null ? '-' : dateFormat.format(parsed);
  }

  Widget _summaryTile(String label, int count, Color color) {
    return Expanded(
      child: Container(
        height: 88,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$count명',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _breakdownPanel(String title, Map<String, int> counts) {
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 12),
            for (final entry in entries.take(8))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.key,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      '${entry.value}명',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF374151),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _pendingRow(Map<String, dynamic> user, {required bool mobile}) {
    final approveButton = ElevatedButton(
      onPressed: () => approveUser(user['id'].toString()),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF111827),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      child: const Text('승인'),
    );

    if (mobile) {
      // 좁은 화면에서는 고정폭 6열 Row가 잘리므로 카드형으로 표시한다.
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFF1F3F5))),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_text(user['name'])} · ${_text(user['role_code'] ?? user['role'])} · ${_text(user['store'])}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_text(user['email'])}\n${_text(user['phone'])} · ${_text(user['created_at_label'])}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(width: 76, child: approveButton),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF1F3F5))),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              '${_text(user['name'])}\n${_text(user['email'])}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(child: Text(_text(user['phone']))),
          Expanded(child: Text(_text(user['store']))),
          Expanded(child: Text(_text(user['role_code'] ?? user['role']))),
          SizedBox(width: 150, child: Text(_text(user['created_at_label']))),
          SizedBox(width: 92, child: approveButton),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!isAdmin) {
      return const Scaffold(body: Center(child: Text('접근 권한 없음')));
    }

    final mobile = MediaQuery.of(context).size.width < 900;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      body: Padding(
        padding: EdgeInsets.all(mobile ? 14 : 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded),
                  tooltip: '뒤로가기',
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '가입/승인 상태',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF111827),
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '직원 가입, 승인 대기, 권한과 매장 분포를 확인합니다',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: fetchUsers,
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                  label: const Text('새로고침'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF111827),
                    foregroundColor: Colors.white,
                    elevation: 0,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (isLoading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else ...[
              if (mobile) ...[
                Row(
                  children: [
                    _summaryTile(
                        '전체 가입', users.length, const Color(0xFF111827)),
                    const SizedBox(width: 12),
                    _summaryTile('승인 대기', pendingCount,
                        const Color(0xFFD97706)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _summaryTile('승인 완료', approvedCount,
                        const Color(0xFF059669)),
                    const SizedBox(width: 12),
                    _summaryTile('반려', rejectedCount, const Color(0xFFDC2626)),
                  ],
                ),
              ] else
                Row(
                  children: [
                    _summaryTile(
                        '전체 가입', users.length, const Color(0xFF111827)),
                    const SizedBox(width: 12),
                    _summaryTile('승인 대기', pendingCount,
                        const Color(0xFFD97706)),
                    const SizedBox(width: 12),
                    _summaryTile('승인 완료', approvedCount,
                        const Color(0xFF059669)),
                    const SizedBox(width: 12),
                    _summaryTile('반려', rejectedCount, const Color(0xFFDC2626)),
                  ],
                ),
              const SizedBox(height: 14),
              // 모바일에서는 권한/매장 분포 패널을 숨겨 승인 목록에 집중한다
              // (220px 고정 높이 패널 2개가 좁은 화면 절반을 차지하던 문제).
              if (!mobile)
                SizedBox(
                  height: 220,
                  child: Row(
                    children: [
                      _breakdownPanel('권한별 현황', roleCounts),
                      const SizedBox(width: 12),
                      _breakdownPanel('매장별 현황', storeCounts),
                    ],
                  ),
                ),
              if (!mobile) const SizedBox(height: 14),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: pendingUsers.isEmpty
                      ? const Center(child: Text('승인 대기 계정이 없습니다'))
                      : Column(
                          children: [
                            Container(
                              height: 46,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              alignment: Alignment.centerLeft,
                              decoration: const BoxDecoration(
                                color: Color(0xFFF8FAFC),
                                border: Border(
                                  bottom: BorderSide(color: Color(0xFFE5E7EB)),
                                ),
                              ),
                              child: Text(
                                '승인 대기 ${pendingUsers.length}명',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF111827),
                                ),
                              ),
                            ),
                            Expanded(
                              child: ListView.builder(
                                itemCount: pendingUsers.length,
                                itemBuilder: (_, index) => _pendingRow(
                                  pendingUsers[index],
                                  mobile: mobile,
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
