import 'package:flutter/material.dart';
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

  bool get isAdmin => isPrivilegedRole(widget.role);

  @override
  void initState() {
    super.initState();
    fetchUsers();
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('직원 계정을 승인했습니다.')),
      );
    } catch (e) {
      debugPrint('dashboard approve failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('승인 실패: $e')),
      );
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

  int _countStatus(String status) {
    return users.where((user) => _status(user) == status).length;
  }

  Map<String, int> get _roleCounts {
    final counts = <String, int>{};
    for (final user in users) {
      final role = _text(user['role_code'] ?? user['role']);
      counts[role] = (counts[role] ?? 0) + 1;
    }
    return counts;
  }

  Map<String, int> get _storeCounts {
    final counts = <String, int>{};
    for (final user in users) {
      final store = _text(user['store']);
      counts[store] = (counts[store] ?? 0) + 1;
    }
    return counts;
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

  Widget _pendingRow(Map<String, dynamic> user) {
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
          SizedBox(width: 150, child: Text(_date(user['created_at']))),
          SizedBox(
            width: 92,
            child: ElevatedButton(
              onPressed: () => approveUser(user['id'].toString()),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF111827),
                foregroundColor: Colors.white,
                elevation: 0,
              ),
              child: const Text('승인'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!isAdmin) {
      return const Scaffold(body: Center(child: Text('접근 권한 없음')));
    }

    final pendingUsers = users.where((user) => _status(user) == '대기').toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      body: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
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
              Row(
                children: [
                  _summaryTile('전체 가입', users.length, const Color(0xFF111827)),
                  const SizedBox(width: 12),
                  _summaryTile(
                      '승인 대기', _countStatus('대기'), const Color(0xFFD97706)),
                  const SizedBox(width: 12),
                  _summaryTile(
                      '승인 완료', _countStatus('승인'), const Color(0xFF059669)),
                  const SizedBox(width: 12),
                  _summaryTile(
                      '반려', _countStatus('반려'), const Color(0xFFDC2626)),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 220,
                child: Row(
                  children: [
                    _breakdownPanel('권한별 현황', _roleCounts),
                    const SizedBox(width: 12),
                    _breakdownPanel('매장별 현황', _storeCounts),
                  ],
                ),
              ),
              const SizedBox(height: 14),
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
                                itemBuilder: (_, index) =>
                                    _pendingRow(pendingUsers[index]),
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
