import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crm_app/services/notice_service.dart';
import 'package:crm_app/utils/store_utils.dart';
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
  final noticeService = NoticeService(supabase);

  List<Map<String, dynamic>> users = [];
  bool isLoading = true;

  bool isAdmin() {
    return isPrivilegedRole(widget.role);
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

      debugPrint('admin users load failed: $e');
    }
  }

  Future<void> approveUser(String id) async {
    try {
      await supabase
          .from('profiles')
          .update({'approval_status': 'approved', 'rejection_reason': null}).eq(
              'id', id);

      fetchUsers(keyword: searchController.text);
    } catch (e) {
      debugPrint('admin approve failed: $e');
    }
  }

  Future<void> deleteUser(String id) async {
    try {
      await supabase.from('profiles').delete().eq('id', id);
      if (mounted) Navigator.pop(context);
      fetchUsers(keyword: searchController.text);
    } catch (e) {
      debugPrint('admin delete failed: $e');
    }
  }

  void showNoticeDialog() {
    final titleController = TextEditingController(text: '공지사항');
    final contentController = TextEditingController();
    Uint8List? imageBytes;
    String? imageName;
    String? imageContentType;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            title: const Text(
              '공지사항 작성',
              style: TextStyle(
                color: Color(0xFF111827),
                fontWeight: FontWeight.w900,
              ),
            ),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: _inputDecoration('제목'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: contentController,
                    minLines: 6,
                    maxLines: 8,
                    decoration: _inputDecoration('내용'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      const imageTypes = XTypeGroup(
                        label: 'images',
                        extensions: ['jpg', 'jpeg', 'png', 'webp', 'gif'],
                      );
                      final file = await openFile(
                        acceptedTypeGroups: const [imageTypes],
                      );
                      if (file == null) return;
                      final bytes = await file.readAsBytes();
                      setDialogState(() {
                        imageBytes = bytes;
                        imageName = file.name;
                        imageContentType =
                            switch (file.name.split('.').last.toLowerCase()) {
                          'png' => 'image/png',
                          'webp' => 'image/webp',
                          'gif' => 'image/gif',
                          _ => 'image/jpeg',
                        };
                      });
                    },
                    icon: const Icon(Icons.image_outlined),
                    label: Text(imageName == null ? '이미지 첨부' : imageName!),
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
                style: _primaryButtonStyle(),
                onPressed: () async {
                  if (contentController.text.trim().isEmpty) return;
                  try {
                    await noticeService.createNotice(
                      title: titleController.text,
                      content: contentController.text,
                      imageBytes: imageBytes,
                      imageName: imageName,
                      contentType: imageContentType,
                    );
                    if (!mounted) return;
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).clearSnackBars();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('공지사항이 등록되었습니다.')),
                    );
                  } catch (e) {
                    debugPrint('notice create failed: $e');
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).clearSnackBars();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('공지사항 등록 실패: $e')),
                    );
                  }
                },
                child: const Text('등록'),
              ),
            ],
          );
        },
      ),
    );
  }

  void showDeleteDialog(Map<String, dynamic> user) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Text(
          '직원 삭제',
          style: TextStyle(
            color: Color(0xFF111827),
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Text('${user['name'] ?? user['email']} 직원을 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            style: _primaryButtonStyle(danger: true),
            onPressed: () => deleteUser(user['id'].toString()),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
  }

  void showEditDialog(Map<String, dynamic> user) {
    final nameController = TextEditingController(
      text: user['name']?.toString() ?? '',
    );
    final phoneController = TextEditingController(
      text: user['phone']?.toString() ?? '',
    );
    final storeController = TextEditingController(
      text: user['store']?.toString() ?? '',
    );
    String role = user['role']?.toString() ?? '사원';

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            title: const Text(
              '직원 수정',
              style: TextStyle(
                color: Color(0xFF111827),
                fontWeight: FontWeight.w900,
              ),
            ),
            content: SizedBox(
              width: 680,
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 240,
                    child: TextField(
                      controller: nameController,
                      decoration: _inputDecoration('이름'),
                    ),
                  ),
                  SizedBox(
                    width: 240,
                    child: TextField(
                      controller: phoneController,
                      decoration: _inputDecoration('전화번호'),
                    ),
                  ),
                  SizedBox(
                    width: 240,
                    child: TextField(
                      controller: storeController,
                      decoration: _inputDecoration('매장'),
                    ),
                  ),
                  SizedBox(
                    width: 240,
                    child: DropdownButtonFormField<String>(
                      initialValue: role,
                      decoration: _inputDecoration('직급'),
                      items: const [
                        DropdownMenuItem(value: '대표', child: Text('대표')),
                        DropdownMenuItem(value: '개발자', child: Text('개발자')),
                        DropdownMenuItem(value: '사장', child: Text('사장')),
                        DropdownMenuItem(value: '점장', child: Text('점장')),
                        DropdownMenuItem(value: '사원', child: Text('사원')),
                        DropdownMenuItem(value: '조회용', child: Text('조회용')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() {
                            role = value;
                          });
                        }
                      },
                    ),
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
                style: _primaryButtonStyle(),
                onPressed: () async {
                  try {
                    await supabase.from('profiles').update({
                      'name': nameController.text.trim(),
                      'phone': phoneController.text.trim(),
                      'store': normalizeStoreName(
                        storeController.text.trim(),
                      ),
                      'role': role,
                    }).eq('id', user['id']);

                    if (mounted) Navigator.pop(context);
                    fetchUsers(keyword: searchController.text);
                  } catch (e) {
                    debugPrint('admin update failed: $e');
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
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
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
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF374151),
        elevation: 0,
        side: const BorderSide(color: Color(0xFFE8E9EF)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      ),
    );
  }

  ButtonStyle _primaryButtonStyle({bool danger = false}) {
    return ElevatedButton.styleFrom(
      backgroundColor:
          danger ? const Color(0xFFDC2626) : const Color(0xFFC94C6E),
      foregroundColor: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: const Color(0xFFFAFAFC),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFE8E9EF)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFE8E9EF)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFC94C6E), width: 1.4),
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
      return const Scaffold(body: Center(child: Text('접근 권한 없음')));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      body: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Row(
              children: [
                SizedBox(
                  width: 360,
                  height: 38,
                  child: TextField(
                    controller: searchController,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: '이름, 이메일, 전화, 직급, 매장 검색',
                      prefixIcon: const Icon(
                        Icons.search,
                        size: 17,
                        color: Color(0xFF9CA3AF),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFE8E9EF)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFE8E9EF)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF6B7280)),
                      ),
                    ),
                    onChanged: (value) => fetchUsers(keyword: value),
                  ),
                ),
                const Spacer(),
                const SizedBox(width: 12),
                _headerActionButton(
                  icon: Icons.campaign_outlined,
                  label: '공지사항 작성',
                  onTap: showNoticeDialog,
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
                  borderRadius: BorderRadius.circular(8),
                ),
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : users.isEmpty
                        ? const Center(child: Text('직원 정보가 없습니다'))
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minWidth: constraints.maxWidth,
                                    ),
                                    child: SingleChildScrollView(
                                      child: DataTable(
                                        headingRowColor:
                                            WidgetStateProperty.all(
                                          const Color(0xFFF8FAFC),
                                        ),
                                        dataRowMinHeight: 62,
                                        dataRowMaxHeight: 68,
                                        columnSpacing: 32,
                                        horizontalMargin: 18,
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
                                          final status = _value(
                                            u['approval_status'],
                                          );
                                          return DataRow(
                                            cells: [
                                              DataCell(Text(_value(u['name']))),
                                              DataCell(
                                                  Text(_value(u['email']))),
                                              DataCell(
                                                  Text(_value(u['phone']))),
                                              DataCell(Text(_value(u['role']))),
                                              DataCell(
                                                  Text(_value(u['store']))),
                                              DataCell(Text(status)),
                                              DataCell(
                                                Text(_value(
                                                    u['rejection_reason'])),
                                              ),
                                              DataCell(
                                                Row(
                                                  children: [
                                                    IconButton(
                                                      tooltip: '수정',
                                                      onPressed: () =>
                                                          showEditDialog(u),
                                                      icon: const Icon(
                                                        Icons.edit_outlined,
                                                      ),
                                                    ),
                                                    if (status != 'approved')
                                                      IconButton(
                                                        tooltip: '승인',
                                                        onPressed: () =>
                                                            approveUser(
                                                          u['id'].toString(),
                                                        ),
                                                        icon: const Icon(
                                                          Icons
                                                              .check_circle_outline,
                                                        ),
                                                      ),
                                                    IconButton(
                                                      tooltip: '삭제',
                                                      onPressed: () =>
                                                          showDeleteDialog(u),
                                                      icon: const Icon(
                                                        Icons.delete_outline,
                                                      ),
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
                                );
                              },
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
