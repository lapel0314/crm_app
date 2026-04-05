import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class InventoryPage extends StatefulWidget {
  final String role;

  const InventoryPage({super.key, required this.role});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  final storeController = TextEditingController();
  final modelController = TextEditingController();
  final serialController = TextEditingController();
  final memoController = TextEditingController();
  final searchController = TextEditingController();

  String status = '보유';
  bool isLoading = false;
  List<Map<String, dynamic>> items = [];

  bool canEdit() {
    return ['대표', '개발자', '사장', '점장', '사원'].contains(widget.role);
  }

  bool canDelete() {
    return ['대표', '개발자', '사장', '점장'].contains(widget.role);
  }

  @override
  void initState() {
    super.initState();
    fetchInventory();
  }

  Future<void> insertAuditLog({
    required String action,
    String? targetId,
    Map<String, dynamic>? detail,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      await supabase.from('audit_logs').insert({
        'actor_id': user.id,
        'action': action,
        'target_table': 'device_inventory',
        'target_id': targetId,
        'detail': detail ?? {},
      });
    } catch (_) {}
  }

  Future<void> fetchInventory({String keyword = ''}) async {
    setState(() {
      isLoading = true;
    });

    try {
      final List<dynamic> data = keyword.trim().isEmpty
          ? await supabase
              .from('device_inventory')
              .select()
              .order('created_at', ascending: false)
          : await supabase
              .from('device_inventory')
              .select()
              .or(
                'store.ilike.%${keyword.trim()}%,model_name.ilike.%${keyword.trim()}%,serial_number.ilike.%${keyword.trim()}%,status.ilike.%${keyword.trim()}%',
              )
              .order('created_at', ascending: false);

      setState(() {
        items = data.map((e) => Map<String, dynamic>.from(e)).toList();
      });
    } catch (e) {
      showMessage('재고 조회 실패: $e');
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  void showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<void> addInventory() async {
    if (storeController.text.trim().isEmpty ||
        serialController.text.trim().isEmpty) {
      showMessage('매장과 일련번호는 필수입니다.');
      return;
    }

    try {
      final user = supabase.auth.currentUser;

      final inserted = await supabase
          .from('device_inventory')
          .insert({
            'store': storeController.text.trim(),
            'model_name': modelController.text.trim(),
            'serial_number': serialController.text.trim(),
            'status': status,
            'memo': memoController.text.trim(),
            'created_by': user?.id,
          })
          .select('id')
          .single();

      await insertAuditLog(
        action: 'create_inventory',
        targetId: inserted['id'].toString(),
        detail: {
          'store': storeController.text.trim(),
          'model_name': modelController.text.trim(),
          'serial_number': serialController.text.trim(),
          'status': status,
        },
      );

      storeController.clear();
      modelController.clear();
      serialController.clear();
      memoController.clear();

      setState(() {
        status = '보유';
      });

      showMessage('재고 등록 완료');
      await fetchInventory(keyword: searchController.text);
    } on PostgrestException catch (e) {
      if (e.message.contains('device_inventory_store_serial_unique')) {
        showMessage('같은 매장에 동일한 일련번호가 이미 등록되어 있습니다.');
      } else {
        showMessage('재고 등록 실패: ${e.message}');
      }
    } catch (e) {
      showMessage('재고 등록 실패: $e');
    }
  }

  Future<void> updateInventory({
    required String id,
    required String store,
    required String modelName,
    required String serialNumber,
    required String status,
    required String memo,
  }) async {
    try {
      await supabase.from('device_inventory').update({
        'store': store,
        'model_name': modelName,
        'serial_number': serialNumber,
        'status': status,
        'memo': memo,
      }).eq('id', id);

      await insertAuditLog(
        action: 'update_inventory',
        targetId: id,
        detail: {
          'store': store,
          'model_name': modelName,
          'serial_number': serialNumber,
          'status': status,
        },
      );

      if (mounted) {
        Navigator.pop(context);
      }

      showMessage('재고 수정 완료');
      await fetchInventory(keyword: searchController.text);
    } on PostgrestException catch (e) {
      if (e.message.contains('device_inventory_store_serial_unique')) {
        showMessage('같은 매장에 동일한 일련번호가 이미 등록되어 있습니다.');
      } else {
        showMessage('재고 수정 실패: ${e.message}');
      }
    } catch (e) {
      showMessage('재고 수정 실패: $e');
    }
  }

  Future<void> deleteInventory(Map<String, dynamic> item) async {
    try {
      await supabase.from('device_inventory').delete().eq('id', item['id']);

      await insertAuditLog(
        action: 'delete_inventory',
        targetId: item['id'].toString(),
        detail: {
          'store': item['store'],
          'model_name': item['model_name'],
          'serial_number': item['serial_number'],
          'status': item['status'],
        },
      );

      if (mounted) {
        Navigator.pop(context);
      }

      showMessage('재고 삭제 완료');
      await fetchInventory(keyword: searchController.text);
    } catch (e) {
      showMessage('재고 삭제 실패: $e');
    }
  }

  void showCreateDialog() {
    final createStoreController = TextEditingController();
    final createModelController = TextEditingController();
    final createSerialController = TextEditingController();
    final createMemoController = TextEditingController();
    String createStatus = '보유';

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('재고 등록'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _input('매장', createStoreController),
                    _input('모델명', createModelController),
                    _input('일련번호', createSerialController),
                    _dropdown<String>(
                      label: '상태',
                      value: createStatus,
                      items: const ['보유', '판매', '불량', '이동'],
                      onChanged: (v) {
                        if (v != null) {
                          setDialogState(() {
                            createStatus = v;
                          });
                        }
                      },
                    ),
                    _input('메모', createMemoController, maxLines: 3),
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
                onPressed: () async {
                  storeController.text = createStoreController.text;
                  modelController.text = createModelController.text;
                  serialController.text = createSerialController.text;
                  memoController.text = createMemoController.text;

                  setState(() {
                    status = createStatus;
                  });

                  Navigator.pop(context);
                  await addInventory();
                },
                child: const Text('등록'),
              ),
            ],
          );
        },
      ),
    );
  }

  void showEditDialog(Map<String, dynamic> item) {
    final editStoreController =
        TextEditingController(text: item['store']?.toString() ?? '');
    final editModelController =
        TextEditingController(text: item['model_name']?.toString() ?? '');
    final editSerialController =
        TextEditingController(text: item['serial_number']?.toString() ?? '');
    final editMemoController =
        TextEditingController(text: item['memo']?.toString() ?? '');
    String editStatus = item['status']?.toString() ?? '보유';

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('재고 수정'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _input('매장', editStoreController),
                    _input('모델명', editModelController),
                    _input('일련번호', editSerialController),
                    _dropdown<String>(
                      label: '상태',
                      value: editStatus,
                      items: const ['보유', '판매', '불량', '이동'],
                      onChanged: (v) {
                        if (v != null) {
                          setDialogState(() {
                            editStatus = v;
                          });
                        }
                      },
                    ),
                    _input('메모', editMemoController, maxLines: 3),
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
                onPressed: () => updateInventory(
                  id: item['id'].toString(),
                  store: editStoreController.text.trim(),
                  modelName: editModelController.text.trim(),
                  serialNumber: editSerialController.text.trim(),
                  status: editStatus,
                  memo: editMemoController.text.trim(),
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
        title: const Text('재고 삭제'),
        content: const Text('정말 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => deleteInventory(item),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
  }

  void showDetail(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(item['model_name']?.toString().isNotEmpty == true
            ? item['model_name'].toString()
            : '재고 상세'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detail('매장', item['store']),
                _detail('모델명', item['model_name']),
                _detail('일련번호', item['serial_number']),
                _detail('상태', item['status']),
                _detail('메모', item['memo']),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
          if (canEdit())
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                showEditDialog(item);
              },
              child: const Text('수정'),
            ),
        ],
      ),
    );
  }

  Widget _input(
    String label,
    TextEditingController controller, {
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  Widget _dropdown<T>({
    required String label,
    required T value,
    required List<T> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<T>(
        value: value,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        items: items
            .map(
              (e) => DropdownMenuItem<T>(
                value: e,
                child: Text('$e'),
              ),
            )
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _detail(String title, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text('$title : ${value ?? ''}'),
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
    storeController.dispose();
    modelController.dispose();
    serialController.dispose();
    memoController.dispose();
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('재고관리'),
      ),
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
                      hintText: '매장, 모델명, 일련번호, 상태 검색...',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) => fetchInventory(keyword: value),
                  ),
                ),
                const SizedBox(width: 12),
                _headerActionButton(
                  icon: Icons.add,
                  label: '재고 등록',
                  onTap: showCreateDialog,
                ),
                const SizedBox(width: 12),
                _headerActionButton(
                  icon: Icons.refresh,
                  label: '새로고침',
                  onTap: () => fetchInventory(keyword: searchController.text),
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
                    : items.isEmpty
                        ? const Center(child: Text('등록된 재고가 없습니다'))
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: SingleChildScrollView(
                                child: DataTable(
                                  headingRowColor: WidgetStateProperty.all(
                                    const Color(0xFFF8FAFC),
                                  ),
                                  dataRowMinHeight: 64,
                                  dataRowMaxHeight: 72,
                                  columnSpacing: 28,
                                  horizontalMargin: 18,
                                  columns: [
                                    _column('매장'),
                                    _column('모델명'),
                                    _column('일련번호'),
                                    _column('상태'),
                                    _column('메모'),
                                    _column('작업'),
                                  ],
                                  rows: items.map((item) {
                                    return DataRow(
                                      cells: [
                                        DataCell(Text(_value(item['store']))),
                                        DataCell(
                                            Text(_value(item['model_name']))),
                                        DataCell(Text(
                                            _value(item['serial_number']))),
                                        DataCell(Text(_value(item['status']))),
                                        DataCell(
                                          SizedBox(
                                            width: 200,
                                            child: Text(
                                              _value(item['memo']),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          Row(
                                            children: [
                                              IconButton(
                                                tooltip: '상세',
                                                onPressed: () =>
                                                    showDetail(item),
                                                icon: const Icon(
                                                    Icons.visibility_outlined),
                                              ),
                                              if (canEdit())
                                                IconButton(
                                                  tooltip: '수정',
                                                  onPressed: () =>
                                                      showEditDialog(item),
                                                  icon: const Icon(
                                                      Icons.edit_outlined),
                                                ),
                                              if (canDelete())
                                                IconButton(
                                                  tooltip: '삭제',
                                                  onPressed: () =>
                                                      showDeleteDialog(item),
                                                  icon: Icon(
                                                    Icons.delete_outline,
                                                    color:
                                                        theme.colorScheme.error,
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
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
