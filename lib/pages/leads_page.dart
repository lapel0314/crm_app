import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class LeadsPage extends StatefulWidget {
  final String role;

  const LeadsPage({super.key, required this.role});

  @override
  State<LeadsPage> createState() => _LeadsPageState();
}

class _LeadsPageState extends State<LeadsPage> {
  final searchController = TextEditingController();

  bool isLoading = true;
  List<Map<String, dynamic>> leads = [];

  bool get canView => widget.role != '공개용';
  bool get canEdit => widget.role != '공개용';

  @override
  void initState() {
    super.initState();
    if (canView) {
      fetchLeads(silent: true);
    } else {
      isLoading = false;
    }
  }

  String formatPhone(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length <= 3) return digits;
    if (digits.length <= 7)
      return '${digits.substring(0, 3)}-${digits.substring(3)}';
    final cut = digits.length > 11 ? 11 : digits.length;
    return '${digits.substring(0, 3)}-${digits.substring(3, 7)}-${digits.substring(7, cut)}';
  }

  bool isValidPhone(String value) {
    return RegExp(r'^01[0-9]-\d{3,4}-\d{4}$').hasMatch(value.trim());
  }

  String shortDate(dynamic value) {
    if (value == null) return '-';
    if (value is DateTime) {
      return DateFormat('yyyy-MM-dd').format(value);
    }
    final text = value.toString();
    return text.length >= 10 ? text.substring(0, 10) : text;
  }

  void showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<void> fetchLeads({String keyword = '', bool silent = false}) async {
    setState(() {
      isLoading = true;
    });

    try {
      final List<dynamic> data = keyword.trim().isEmpty
          ? await supabase
              .from('leads')
              .select()
              .order('lead_date', ascending: true)
              .order('created_at', ascending: true)
          : await supabase
              .from('leads')
              .select()
              .or(
                'manager.ilike.%${keyword.trim()}%,subscriber.ilike.%${keyword.trim()}%,phone.ilike.%${keyword.trim()}%,previous_carrier.ilike.%${keyword.trim()}%,target_carrier.ilike.%${keyword.trim()}%,memo.ilike.%${keyword.trim()}%',
              )
              .order('lead_date', ascending: true)
              .order('created_at', ascending: true);

      setState(() {
        leads = data.map((e) => Map<String, dynamic>.from(e)).toList();
      });
    } catch (e) {
      if (!silent) {
        showMessage('가망고객 조회 실패: $e');
      }
      setState(() {
        leads = [];
      });
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> addLead({
    required DateTime? leadDate,
    required String manager,
    required String subscriber,
    required String phone,
    required String previousCarrier,
    required String targetCarrier,
    required String memo,
  }) async {
    if (subscriber.trim().isEmpty) {
      showMessage('가입자는 필수입니다.');
      return;
    }

    if (phone.trim().isNotEmpty && !isValidPhone(phone)) {
      showMessage('휴대폰번호 형식은 010-1234-1234 입니다.');
      return;
    }

    try {
      await supabase.from('leads').insert({
        'lead_date': leadDate?.toIso8601String(),
        'manager': manager.trim(),
        'subscriber': subscriber.trim(),
        'phone': phone.trim(),
        'previous_carrier': previousCarrier.trim(),
        'target_carrier': targetCarrier.trim(),
        'memo': memo.trim(),
      });

      if (mounted) Navigator.pop(context);
      showMessage('가망고객 등록 완료');
      fetchLeads(keyword: searchController.text, silent: true);
    } catch (e) {
      showMessage('가망고객 등록 실패: $e');
    }
  }

  Future<void> updateLead({
    required String id,
    required DateTime? leadDate,
    required String manager,
    required String subscriber,
    required String phone,
    required String previousCarrier,
    required String targetCarrier,
    required String memo,
  }) async {
    if (subscriber.trim().isEmpty) {
      showMessage('가입자는 필수입니다.');
      return;
    }

    if (phone.trim().isNotEmpty && !isValidPhone(phone)) {
      showMessage('휴대폰번호 형식은 010-1234-1234 입니다.');
      return;
    }

    try {
      await supabase.from('leads').update({
        'lead_date': leadDate?.toIso8601String(),
        'manager': manager.trim(),
        'subscriber': subscriber.trim(),
        'phone': phone.trim(),
        'previous_carrier': previousCarrier.trim(),
        'target_carrier': targetCarrier.trim(),
        'memo': memo.trim(),
      }).eq('id', id);

      if (mounted) Navigator.pop(context);
      showMessage('가망고객 수정 완료');
      fetchLeads(keyword: searchController.text, silent: true);
    } catch (e) {
      showMessage('가망고객 수정 실패: $e');
    }
  }

  Future<void> deleteLead(String id) async {
    try {
      await supabase.from('leads').delete().eq('id', id);
      if (mounted) Navigator.pop(context);
      showMessage('가망고객 삭제 완료');
      fetchLeads(keyword: searchController.text, silent: true);
    } catch (e) {
      showMessage('가망고객 삭제 실패: $e');
    }
  }

  void showCreateDialog() {
    final managerController = TextEditingController();
    final subscriberController = TextEditingController();
    final phoneController = TextEditingController();
    final previousCarrierController = TextEditingController();
    final targetCarrierController = TextEditingController();
    final memoController = TextEditingController();
    DateTime? leadDate;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('가망고객 등록'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: leadDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setDialogState(() {
                              leadDate = picked;
                            });
                          }
                        },
                        child: Text(
                          leadDate == null
                              ? '날짜 선택'
                              : DateFormat('yyyy-MM-dd').format(leadDate!),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: managerController,
                      decoration: const InputDecoration(labelText: '담당자'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: subscriberController,
                      decoration: const InputDecoration(labelText: '가입자'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneController,
                      decoration: const InputDecoration(labelText: '휴대폰번호'),
                      onChanged: (value) {
                        final formatted = formatPhone(value);
                        phoneController.value = TextEditingValue(
                          text: formatted,
                          selection:
                              TextSelection.collapsed(offset: formatted.length),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: previousCarrierController,
                      decoration: const InputDecoration(labelText: '기존통신사'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: targetCarrierController,
                      decoration: const InputDecoration(labelText: '변경통신사'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: memoController,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: '메모'),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('취소'),
              ),
              ElevatedButton(
                onPressed: () => addLead(
                  leadDate: leadDate,
                  manager: managerController.text.trim(),
                  subscriber: subscriberController.text.trim(),
                  phone: phoneController.text.trim(),
                  previousCarrier: previousCarrierController.text.trim(),
                  targetCarrier: targetCarrierController.text.trim(),
                  memo: memoController.text.trim(),
                ),
                child: const Text('저장'),
              ),
            ],
          );
        },
      ),
    );
  }

  void showEditDialog(Map<String, dynamic> item) {
    final managerController =
        TextEditingController(text: item['manager']?.toString() ?? '');
    final subscriberController =
        TextEditingController(text: item['subscriber']?.toString() ?? '');
    final phoneController =
        TextEditingController(text: item['phone']?.toString() ?? '');
    final previousCarrierController =
        TextEditingController(text: item['previous_carrier']?.toString() ?? '');
    final targetCarrierController =
        TextEditingController(text: item['target_carrier']?.toString() ?? '');
    final memoController =
        TextEditingController(text: item['memo']?.toString() ?? '');

    DateTime? leadDate = item['lead_date'] != null
        ? DateTime.tryParse(item['lead_date'].toString())
        : null;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('가망고객 수정'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: leadDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setDialogState(() {
                              leadDate = picked;
                            });
                          }
                        },
                        child: Text(
                          leadDate == null
                              ? '날짜 선택'
                              : DateFormat('yyyy-MM-dd').format(leadDate!),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: managerController,
                      decoration: const InputDecoration(labelText: '담당자'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: subscriberController,
                      decoration: const InputDecoration(labelText: '가입자'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneController,
                      decoration: const InputDecoration(labelText: '휴대폰번호'),
                      onChanged: (value) {
                        final formatted = formatPhone(value);
                        phoneController.value = TextEditingValue(
                          text: formatted,
                          selection:
                              TextSelection.collapsed(offset: formatted.length),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: previousCarrierController,
                      decoration: const InputDecoration(labelText: '기존통신사'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: targetCarrierController,
                      decoration: const InputDecoration(labelText: '변경통신사'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: memoController,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: '메모'),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('취소'),
              ),
              ElevatedButton(
                onPressed: () => updateLead(
                  id: item['id'].toString(),
                  leadDate: leadDate,
                  manager: managerController.text.trim(),
                  subscriber: subscriberController.text.trim(),
                  phone: phoneController.text.trim(),
                  previousCarrier: previousCarrierController.text.trim(),
                  targetCarrier: targetCarrierController.text.trim(),
                  memo: memoController.text.trim(),
                ),
                child: const Text('저장'),
              ),
            ],
          );
        },
      ),
    );
  }

  void showDeleteDialog(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('가망고객 삭제'),
        content: const Text('정말 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => deleteLead(item['id'].toString()),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!canView) {
      return const Scaffold(
        body: Center(
          child: Text('접근 권한 없음'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('가망고객')),
      body: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: searchController,
                    decoration: const InputDecoration(
                      hintText: '담당자, 가입자, 휴대폰번호, 통신사, 메모 검색',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) =>
                        fetchLeads(keyword: value, silent: true),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: showCreateDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('등록'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () => fetchLeads(
                    keyword: searchController.text,
                    silent: true,
                  ),
                  icon: const Icon(Icons.refresh),
                  label: const Text('새로고침'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : leads.isEmpty
                      ? const Center(child: Text('등록된 가망고객이 없습니다'))
                      : ListView.builder(
                          itemCount: leads.length,
                          itemBuilder: (context, index) {
                            final item = leads[index];
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              child: ListTile(
                                onTap: () => showEditDialog(item),
                                title: Text(
                                  '${shortDate(item['lead_date'])} | ${item['subscriber'] ?? '-'}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 6),
                                    Text('담당자: ${item['manager'] ?? '-'}'),
                                    Text('휴대폰번호: ${item['phone'] ?? '-'}'),
                                    Text(
                                        '기존통신사: ${item['previous_carrier'] ?? '-'}'),
                                    Text(
                                        '변경통신사: ${item['target_carrier'] ?? '-'}'),
                                    Text('메모: ${item['memo'] ?? '-'}'),
                                  ],
                                ),
                                trailing: canEdit
                                    ? PopupMenuButton<String>(
                                        onSelected: (value) {
                                          if (value == 'edit') {
                                            showEditDialog(item);
                                          } else if (value == 'delete') {
                                            showDeleteDialog(item);
                                          }
                                        },
                                        itemBuilder: (_) => const [
                                          PopupMenuItem(
                                            value: 'edit',
                                            child: Text('수정'),
                                          ),
                                          PopupMenuItem(
                                            value: 'delete',
                                            child: Text('삭제'),
                                          ),
                                        ],
                                      )
                                    : null,
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
