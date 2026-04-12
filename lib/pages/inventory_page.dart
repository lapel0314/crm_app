import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crm_app/utils/store_utils.dart';

final supabase = Supabase.instance.client;

class InventoryPage extends StatefulWidget {
  final String role;
  final String currentStore;

  const InventoryPage({
    super.key,
    required this.role,
    required this.currentStore,
  });

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

  bool get canViewAllStores => isPrivilegedRole(widget.role);

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

      final inventoryItems =
          data.map((e) => Map<String, dynamic>.from(e)).where((item) {
        return canViewAllStores ||
            isSameStore(item['store'], widget.currentStore);
      }).toList();

      setState(() {
        items = inventoryItems;
      });
    } catch (e) {
      debugPrint('inventory load failed: $e');
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
    final normalizedStore = normalizeStoreName(
      storeController.text.trim().isEmpty
          ? widget.currentStore
          : storeController.text.trim(),
    );

    if (normalizedStore.isEmpty || serialController.text.trim().isEmpty) {
      showMessage('매장과 일련번호는 필수입니다.');
      return;
    }

    try {
      final user = supabase.auth.currentUser;

      final inserted = await supabase
          .from('device_inventory')
          .insert({
            'store': normalizedStore,
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
          'store': normalizedStore,
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
        debugPrint('inventory create failed: ${e.message}');
      }
    } catch (e) {
      debugPrint('inventory create failed: $e');
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
    final normalizedStore = normalizeStoreName(store);

    try {
      await supabase.from('device_inventory').update({
        'store': normalizedStore,
        'model_name': modelName,
        'serial_number': serialNumber,
        'status': status,
        'memo': memo,
      }).eq('id', id);

      await insertAuditLog(
        action: 'update_inventory',
        targetId: id,
        detail: {
          'store': normalizedStore,
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
        debugPrint('inventory update failed: ${e.message}');
      }
    } catch (e) {
      debugPrint('inventory update failed: $e');
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
      debugPrint('inventory delete failed: $e');
    }
  }

  void showCreateDialog() {
    final createStoreController =
        TextEditingController(text: widget.currentStore);
    final createModelController = TextEditingController();
    final createSerialController = TextEditingController();
    final createMemoController = TextEditingController();
    String createStatus = '보유';

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            title: const Text(
              '재고 등록',
              style: TextStyle(
                color: Color(0xFF111827),
                fontWeight: FontWeight.w900,
              ),
            ),
            content: SizedBox(
              width: 680,
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
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
                    _input('메모', createMemoController, maxLines: 3, width: 492),
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
                style: _primaryButtonStyle(),
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
            backgroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            title: const Text(
              '재고 수정',
              style: TextStyle(
                color: Color(0xFF111827),
                fontWeight: FontWeight.w900,
              ),
            ),
            content: SizedBox(
              width: 680,
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
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
                    _input('메모', editMemoController, maxLines: 3, width: 492),
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
                style: _primaryButtonStyle(),
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
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: Text(
          item['model_name']?.toString().isNotEmpty == true
              ? item['model_name'].toString()
              : '재고 상세',
          style: const TextStyle(
            color: Color(0xFF111827),
            fontWeight: FontWeight.w900,
          ),
        ),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 18,
              runSpacing: 0,
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
    double width = 240,
  }) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        style: const TextStyle(
          color: Color(0xFF111827),
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        decoration: _inputDecoration(label),
      ),
    );
  }

  Widget _dropdown<T>({
    required String label,
    required T value,
    required List<T> items,
    required ValueChanged<T?> onChanged,
  }) {
    return SizedBox(
      width: 240,
      child: DropdownButtonFormField<T>(
        initialValue: value,
        decoration: _inputDecoration(label),
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
    return SizedBox(
      width: 250,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color(0xFFF3F4F6)),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 86,
              child: Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF8B95A1),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value?.toString().trim().isNotEmpty == true
                    ? value.toString()
                    : '-',
                maxLines: 2,
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

  ButtonStyle _primaryButtonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFFC94C6E),
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

  Widget _inventoryTable() {
    const baseWidths = <double>[140, 180, 190, 110, 260, 120];
    const headers = ['매장', '모델명', '일련번호', '상태', '메모', '작업'];

    return LayoutBuilder(
      builder: (context, constraints) {
        final baseWidth = baseWidths.reduce((a, b) => a + b);
        final tableWidth =
            constraints.maxWidth > baseWidth ? constraints.maxWidth : baseWidth;
        final extraWidth = tableWidth - baseWidth;
        final widths = [...baseWidths];
        if (extraWidth > 0) {
          widths[1] += extraWidth * 0.22;
          widths[2] += extraWidth * 0.20;
          widths[4] += extraWidth * 0.46;
          widths[5] += extraWidth * 0.12;
        }

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: Column(
              children: [
                Container(
                  height: 44,
                  color: const Color(0xFFF9FAFB),
                  child: Row(
                    children: [
                      for (var i = 0; i < headers.length; i++)
                        _tableHeader(headers[i], widths[i]),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: items.map((item) {
                        return InkWell(
                          onTap: () => showDetail(item),
                          child: Container(
                            height: 62,
                            decoration: const BoxDecoration(
                              border: Border(
                                bottom: BorderSide(color: Color(0xFFF3F4F6)),
                              ),
                            ),
                            child: Row(
                              children: [
                                _tableCell(
                                    Text(_value(item['store'])), widths[0]),
                                _tableCell(Text(_value(item['model_name'])),
                                    widths[1]),
                                _tableCell(Text(_value(item['serial_number'])),
                                    widths[2]),
                                _tableCell(_statusBadge(_value(item['status'])),
                                    widths[3]),
                                _tableCell(
                                  Text(
                                    _value(item['memo']),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  widths[4],
                                ),
                                _tableCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _compactIconButton(
                                        tooltip: '상세',
                                        onPressed: () => showDetail(item),
                                        icon: const Icon(
                                            Icons.visibility_outlined,
                                            size: 18),
                                      ),
                                      if (canEdit())
                                        _compactIconButton(
                                          tooltip: '수정',
                                          onPressed: () => showEditDialog(item),
                                          icon: const Icon(Icons.edit_outlined,
                                              size: 18),
                                        ),
                                      if (canDelete())
                                        _compactIconButton(
                                          tooltip: '삭제',
                                          onPressed: () =>
                                              showDeleteDialog(item),
                                          icon: const Icon(Icons.delete_outline,
                                              size: 18),
                                        ),
                                    ],
                                  ),
                                  widths[5],
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _tableHeader(String label, double width) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF9CA3AF),
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _tableCell(Widget child, double width) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(alignment: Alignment.centerLeft, child: child),
      ),
    );
  }

  Widget _statusBadge(String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFF374151),
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _compactIconButton({
    required String tooltip,
    required VoidCallback onPressed,
    required Widget icon,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: icon,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
    );
  }

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
                      hintText: '매장, 모델명, 일련번호, 상태 검색...',
                      prefixIcon: const Icon(
                        Icons.search,
                        size: 17,
                        color: Color(0xFF9CA3AF),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12),
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
                    onChanged: (value) => fetchInventory(keyword: value),
                  ),
                ),
                const Spacer(),
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
                  borderRadius: BorderRadius.circular(8),
                ),
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : items.isEmpty
                        ? const Center(child: Text('등록된 재고가 없습니다'))
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: _inventoryTable(),
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
