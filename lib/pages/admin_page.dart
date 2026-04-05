import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'audit_log_page.dart';

final supabase = Supabase.instance.client;

class AdminPage extends StatefulWidget {
  final String role;

  const AdminPage({super.key, required this.role});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final searchController = TextEditingController();

  List<Map<String, dynamic>> users = [];
  bool isLoading = true;

  bool isAdmin() {
    return widget.role == '대표' || widget.role == '개발자';
  }

  @override
  void initState() {
    super.initState();
    fetchUsers();
  }

  Future<void> fetchUsers({String keyword = ''}) async {
    if (!isAdmin()) {
      setState(() {
        isLoading = false;
      });
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final data = keyword.trim().isEmpty
          ? await supabase
              .from('profiles')
              .select()
              .order('created_at', ascending: true)
          : await supabase
              .from('profiles')
              .select()
              .or(
                'name.ilike.%${keyword.trim()}%,email.ilike.%${keyword.trim()}%,phone.ilike.%${keyword.trim()}%,role.ilike.%${keyword.trim()}%,store.ilike.%${keyword.trim()}%',
              )
              .order('created_at', ascending: true);

      setState(() {
        users = List<Map<String, dynamic>>.from(data);
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        isLoading = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('직원 조회 실패: $e')),
      );
    }
  }

  Future<void> approveUser(String id) async {
    try {
      await supabase.from('profiles').update({
        'approval_status': 'approved',
        'rejection_reason': null,
      }).eq('id', id);

      fetchUsers(keyword: searchController.text);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('승인 실패: $e')),
      );
    }
  }

  Future<void> deleteUser(String id) async {
    try {
      await supabase.from('profiles').delete().eq('id', id);
      if (mounted) Navigator.pop(context);
      fetchUsers(keyword: searchController.text);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('삭제 실패: $e')),
      );
    }
  }

  void showDeleteDialog(Map<String, dynamic> user) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('직원 삭제'),
        content: Text('${user['name'] ?? user['email']} 직원을 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => deleteUser(user['id'].toString()),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
  }

  void showEditDialog(Map<String, dynamic> user) {
    final nameController =
        TextEditingController(text: user['name']?.toString() ?? '');
    final phoneController =
        TextEditingController(text: user['phone']?.toString() ?? '');
    final storeController =
        TextEditingController(text: user['store']?.toString() ?? '');
    String role = user['role']?.toString() ?? '사원';

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('직원 수정'),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: '이름'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneController,
                    decoration: const InputDecoration(labelText: '전화번호'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: storeController,
                    decoration: const InputDecoration(labelText: '매장'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: role,
                    decoration: const InputDecoration(labelText: '직급'),
                    items: const [
                      DropdownMenuItem(value: '대표', child: Text('대표')),
                      DropdownMenuItem(value: '개발자', child: Text('개발자')),
                      DropdownMenuItem(value: '사장', child: Text('사장')),
                      DropdownMenuItem(value: '점장', child: Text('점장')),
                      DropdownMenuItem(value: '사원', child: Text('사원')),
                      DropdownMenuItem(value: '공개용', child: Text('공개용')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() {
                          role = value;
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('취소'),
              ),
              ElevatedButton(
                onPressed: () async {
                  try {
                    await supabase.from('profiles').update({
                      'name': nameController.text.trim(),
                      'phone': phoneController.text.trim(),
                      'store': storeController.text.trim(),
                      'role': role,
                    }).eq('id', user['id']);

                    if (mounted) Navigator.pop(context);
                    fetchUsers(keyword: searchController.text);
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('수정 실패: $e')),
                    );
                  }
                },
                child: const Text('저장'),
              ),
            ],
          );
        },
      ),
    );
  }

  DataColumn _column(String label) {
    return DataColumn(
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _headerActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
    );
  }

  String _value(dynamic value) =>
      value?.toString().isNotEmpty == true ? value.toString() : '-';

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!isAdmin()) {
      return const Scaffold(
        body: Center(child: Text('접근 권한 없음')),
      );
    }

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: searchController,
                    decoration: const InputDecoration(
                      hintText: '이름, 이메일, 전화, 직급, 매장 검색',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) => fetchUsers(keyword: value),
                  ),
                ),
                const SizedBox(width: 12),
                _headerActionButton(
                  icon: Icons.receipt_long_outlined,
                  label: '감사로그',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AuditLogPage(role: widget.role),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 12),
                _headerActionButton(
                  icon: Icons.refresh,
                  label: '새로고침',
                  onTap: () => fetchUsers(keyword: searchController.text),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFE7E9EE)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : users.isEmpty
                        ? const Center(child: Text('직원 정보가 없습니다'))
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: SingleChildScrollView(
                                child: DataTable(
                                  headingRowColor: WidgetStateProperty.all(
                                    const Color(0xFFF8FAFC),
                                  ),
                                  columns: [
                                    _column('이름'),
                                    _column('이메일'),
                                    _column('전화'),
                                    _column('직급'),
                                    _column('매장'),
                                    _column('상태'),
                                    _column('거절사유'),
                                    _column('작업'),
                                  ],
                                  rows: users.map((u) {
                                    final status = _value(u['approval_status']);
                                    return DataRow(
                                      cells: [
                                        DataCell(Text(_value(u['name']))),
                                        DataCell(Text(_value(u['email']))),
                                        DataCell(Text(_value(u['phone']))),
                                        DataCell(Text(_value(u['role']))),
                                        DataCell(Text(_value(u['store']))),
                                        DataCell(Text(status)),
                                        DataCell(Text(
                                            _value(u['rejection_reason']))),
                                        DataCell(
                                          Row(
                                            children: [
                                              IconButton(
                                                tooltip: '수정',
                                                onPressed: () =>
                                                    showEditDialog(u),
                                                icon: const Icon(
                                                    Icons.edit_outlined),
                                              ),
                                              if (status != 'approved')
                                                IconButton(
                                                  tooltip: '승인',
                                                  onPressed: () => approveUser(
                                                      u['id'].toString()),
                                                  icon: const Icon(Icons
                                                      .check_circle_outline),
                                                ),
                                              IconButton(
                                                tooltip: '삭제',
                                                onPressed: () =>
                                                    showDeleteDialog(u),
                                                icon: const Icon(
                                                    Icons.delete_outline),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
