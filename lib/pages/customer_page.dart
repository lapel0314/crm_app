import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crm_app/utils/store_utils.dart';

final supabase = Supabase.instance.client;

class CustomerPage extends StatefulWidget {
  final String role;
  final String currentStore;

  const CustomerPage({
    super.key,
    required this.role,
    required this.currentStore,
  });

  @override
  State<CustomerPage> createState() => _CustomerPageState();
}

class _CustomerPageState extends State<CustomerPage> {
  final searchController = TextEditingController();
  final dateSearchController = TextEditingController();
  final phoneSearchController = TextEditingController();
  final NumberFormat moneyFormat = NumberFormat('#,###');

  List<Map<String, dynamic>> customers = [];
  bool isLoading = true;
  String selectedCarrierFilter = '전체';
  String selectedJoinTypeFilter = '전체';
  int currentPage = 0;
  static const int pageSize = 20;

  bool get isPublicRole => widget.role == '공개용';
  bool get canEdit => !isPublicRole;
  bool get canDelete => !isPublicRole;
  bool get canViewAllStores => isPrivilegedRole(widget.role);

  @override
  void initState() {
    super.initState();
    fetchCustomers();
  }

  int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    final text = value.toString().replaceAll(',', '').trim();
    return int.tryParse(text) ?? 0;
  }

  String _money(dynamic value) {
    return '${moneyFormat.format(_toInt(value))}원';
  }

  String _formatMoneyInput(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleaned.isEmpty) return '';
    return moneyFormat.format(int.parse(cleaned));
  }

  void _applyMoneyFormat(TextEditingController controller, String value) {
    final formatted = _formatMoneyInput(value);
    controller.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  String _date(dynamic value) {
    if (value == null) return '-';
    if (value is DateTime) return DateFormat('yyyy-MM-dd').format(value);
    final text = value.toString();
    return text.length >= 10 ? text.substring(0, 10) : text;
  }

  String _text(dynamic value) {
    if (value == null) return '-';
    final t = value.toString().trim();
    return t.isEmpty ? '-' : t;
  }

  String _formatPhone(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length <= 3) return digits;
    if (digits.length <= 7) {
      return '${digits.substring(0, 3)}-${digits.substring(3)}';
    }
    final cut = digits.length > 11 ? 11 : digits.length;
    return '${digits.substring(0, 3)}-${digits.substring(3, 7)}-${digits.substring(7, cut)}';
  }

  String _maskName(String name) {
    if (name.isEmpty) return '';
    if (name.length == 1) return '*';
    if (name.length == 2) return '${name[0]}*';
    return name[0] + ('*' * (name.length - 2)) + name[name.length - 1];
  }

  String _maskPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length >= 11) {
      return '${digits.substring(0, 3)}-****-${digits.substring(7, 11)}';
    }
    return phone;
  }

  String _maskBankInfo(String text) {
    final value = text.trim();
    if (value.isEmpty) return '-';
    if (value.length <= 4) return '****';
    return '${value.substring(0, 2)}****${value.substring(value.length - 2)}';
  }

  String _displayName(String name) => isPublicRole ? _maskName(name) : name;
  String _displayPhone(String phone) =>
      isPublicRole ? _maskPhone(phone) : phone;
  String _displayBankInfo(String bankInfo) =>
      isPublicRole ? _maskBankInfo(bankInfo) : bankInfo;

  int _calcTotalRebate({
    required int rebate,
    required int addRebate,
    required int hiddenRebate,
    required int deduction,
    required int supportMoney,
    required int payment,
    required int deposit,
    required int tradePrice,
  }) {
    return rebate +
        addRebate +
        hiddenRebate -
        deduction -
        supportMoney -
        payment -
        deposit +
        tradePrice;
  }

  int _calcTax(int totalRebate) {
    return (totalRebate * 0.13).round();
  }

  int _calcMargin(int totalRebate, int tax) {
    return totalRebate - tax;
  }

  void _showCenterMessage(String message) {
    if (!mounted) return;
    var closed = false;
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '알림',
      barrierColor: Colors.black.withValues(alpha: 0.06),
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (dialogContext, _, __) => Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 360),
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE8E9EF)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 22,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.info_outline_rounded,
                    color: Color(0xFFC94C6E), size: 20),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: Color(0xFF111827),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).then((_) => closed = true);

    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!closed && mounted) {
        Navigator.of(context, rootNavigator: true).maybePop();
      }
    });
  }

  void _logUiError(String message) {
    debugPrint(message);
  }

  String _normalizeCarrier(String value) {
    return value.toUpperCase().replaceAll(RegExp(r'[\s_-]'), '');
  }

  bool _matchesCarrierFilter(dynamic value) {
    if (selectedCarrierFilter == '전체') return true;

    final carrier = _normalizeCarrier(_text(value));
    final filter = _normalizeCarrier(selectedCarrierFilter);

    if (filter == 'SKT') {
      return carrier.contains('SKT') || carrier.contains('SK');
    }
    if (filter == 'LGU+') {
      return carrier.contains('LGU+') ||
          carrier.contains('LGU') ||
          carrier.contains('LG');
    }

    return carrier.contains(filter);
  }

  Color _carrierColor(dynamic value) {
    final carrier = _normalizeCarrier(_text(value));
    if (carrier.contains('SK')) return const Color(0xFF2563EB);
    if (carrier.contains('KT')) return const Color(0xFFEF4444);
    if (carrier.contains('LG')) return const Color(0xFFC94C6E);
    return const Color(0xFF6B7280);
  }

  Color _joinTypeColor(dynamic value) {
    final type = _text(value);
    if (type.contains('신규')) return const Color(0xFF10B981);
    if (type.contains('번호') || type.contains('이동')) {
      return const Color(0xFF2563EB);
    }
    if (type.contains('기변') || type.contains('기기')) {
      return const Color(0xFFF59E0B);
    }
    return const Color(0xFF6B7280);
  }

  Color _contractTypeColor(dynamic value) {
    final type = _text(value);
    if (type.contains('공시')) return const Color(0xFFF59E0B);
    if (type.contains('선약')) return const Color(0xFF8B5CF6);
    return const Color(0xFF6B7280);
  }

  Color _staffColor(dynamic value) {
    final staff = _text(value);
    const palette = [
      Color(0xFF2563EB),
      Color(0xFF10B981),
      Color(0xFFF59E0B),
      Color(0xFF8B5CF6),
      Color(0xFFC94C6E),
      Color(0xFFEF4444),
      Color(0xFF14B8A6),
    ];
    final hash = staff.codeUnits.fold<int>(0, (sum, unit) => sum + unit);
    return palette[hash % palette.length];
  }

  Future<void> fetchCustomers({String keyword = ''}) async {
    setState(() {
      isLoading = true;
    });

    try {
      final List<dynamic> data = await supabase
          .from('customers')
          .select()
          .order('join_date', ascending: true)
          .order('created_at', ascending: true);

      final dateFilter = dateSearchController.text.trim();
      final nameFilter = searchController.text.trim().toLowerCase();
      final phoneFilter =
          phoneSearchController.text.replaceAll(RegExp(r'[^0-9]'), '');
      final legacyKeyword = keyword.trim().toLowerCase();

      bool matches(Map<String, dynamic> item) {
        final matchesStore =
            canViewAllStores || isSameStore(item['store'], widget.currentStore);
        final dateText = _date(item['join_date']);
        final nameText = _text(item['name']).toLowerCase();
        final phoneText = _text(item['phone']);
        final phoneDigits = phoneText.replaceAll(RegExp(r'[^0-9]'), '');

        final matchesDate = dateFilter.isEmpty || dateText.contains(dateFilter);
        final matchesName = nameFilter.isEmpty || nameText.contains(nameFilter);
        final matchesPhone =
            phoneFilter.isEmpty || phoneDigits.contains(phoneFilter);
        final joinTypeText = _text(item['join_type']);
        final matchesCarrier = _matchesCarrierFilter(item['carrier']);
        final matchesJoinType = selectedJoinTypeFilter == '전체' ||
            joinTypeText.contains(selectedJoinTypeFilter) ||
            (selectedJoinTypeFilter == '기기변경' && joinTypeText.contains('기변'));
        final matchesLegacy = legacyKeyword.isEmpty ||
            [
              item['name'],
              item['phone'],
              item['carrier'],
              item['model'],
              item['store'],
              item['staff'],
              item['memo'],
            ].any(
                (value) => _text(value).toLowerCase().contains(legacyKeyword));

        return matchesDate &&
            matchesStore &&
            matchesName &&
            matchesPhone &&
            matchesCarrier &&
            matchesJoinType &&
            matchesLegacy;
      }

      setState(() {
        customers = data
            .map((e) => Map<String, dynamic>.from(e))
            .where(matches)
            .toList();
        currentPage = 0;
      });
    } catch (e) {
      _logUiError('고객 조회 실패: $e');
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> deleteCustomer(String id) async {
    try {
      await supabase.from('customers').delete().eq('id', id);
      if (mounted) Navigator.pop(context);
      _showCenterMessage('고객 삭제 완료');
      fetchCustomers(keyword: searchController.text);
    } catch (e) {
      _logUiError('삭제 실패: $e');
    }
  }

  void showDeleteDialog(Map<String, dynamic> customer) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('고객 삭제'),
        content: Text('${customer['name'] ?? '-'} 고객을 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => deleteCustomer(customer['id'].toString()),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, dynamic value) {
    return SizedBox(
      width: 270,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color(0xFFF3F4F6)),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 92,
              child: Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF8B95A1),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Expanded(
              child: Text(
                _text(value),
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

  Widget _detailDivider() {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: const Color(0xFFE8E9EF),
    );
  }

  Widget _sectionCard({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE8E9EF)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 18,
                    decoration: BoxDecoration(
                      color: const Color(0xFF6B7280),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF111827),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 18,
                runSpacing: 0,
                children: [
                  for (final child in children)
                    if (child is Divider)
                      SizedBox(
                        width: constraints.maxWidth,
                        child: _detailDivider(),
                      )
                    else
                      child,
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _input(
    String label,
    TextEditingController controller, {
    TextInputType? keyboardType,
    int maxLines = 1,
    Function(String)? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          alignLabelWithHint: maxLines > 1,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  Widget _detailMoneyRow(String label, dynamic value) {
    return _detailRow(label, _money(value));
  }

  Widget _dropdown<T>({
    required String label,
    required T? value,
    required List<T> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<T>(
        initialValue: value,
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

  void showEditDialog(Map<String, dynamic> customer) {
    final nameController =
        TextEditingController(text: customer['name']?.toString() ?? '');
    final phoneController =
        TextEditingController(text: customer['phone']?.toString() ?? '');
    final carrierController =
        TextEditingController(text: customer['carrier']?.toString() ?? '');
    final previousCarrierController = TextEditingController(
        text: customer['previous_carrier']?.toString() ?? '');
    final modelController =
        TextEditingController(text: customer['model']?.toString() ?? '');
    final planController =
        TextEditingController(text: customer['plan']?.toString() ?? '');
    final addServiceController =
        TextEditingController(text: customer['add_service']?.toString() ?? '');
    final memoController =
        TextEditingController(text: customer['memo']?.toString() ?? '');
    final hiddenNoteController =
        TextEditingController(text: customer['hidden_note']?.toString() ?? '');
    final deductionNoteController = TextEditingController(
        text: customer['deduction_note']?.toString() ?? '');
    final paymentNoteController =
        TextEditingController(text: customer['payment_note']?.toString() ?? '');
    final bankInfoController =
        TextEditingController(text: customer['bank_info']?.toString() ?? '');
    final tradeModelController =
        TextEditingController(text: customer['trade_model']?.toString() ?? '');
    final storeController =
        TextEditingController(text: customer['store']?.toString() ?? '');
    final mobileController =
        TextEditingController(text: customer['mobile']?.toString() ?? '');
    final secondController =
        TextEditingController(text: customer['second']?.toString() ?? '');
    final staffController =
        TextEditingController(text: customer['staff']?.toString() ?? '');

    final rebateController = TextEditingController(
        text: _formatMoneyInput('${_toInt(customer['rebate'])}'));
    final addRebateController = TextEditingController(
        text: _formatMoneyInput('${_toInt(customer['add_rebate'])}'));
    final hiddenRebateController = TextEditingController(
        text: _formatMoneyInput('${_toInt(customer['hidden_rebate'])}'));
    final deductionController = TextEditingController(
        text: _formatMoneyInput('${_toInt(customer['deduction'])}'));
    final supportMoneyController = TextEditingController(
        text: _formatMoneyInput('${_toInt(customer['support_money'])}'));
    final paymentController = TextEditingController(
        text: _formatMoneyInput('${_toInt(customer['payment'])}'));
    final depositController = TextEditingController(
        text: _formatMoneyInput('${_toInt(customer['deposit'])}'));
    final tradePriceController = TextEditingController(
        text: _formatMoneyInput('${_toInt(customer['trade_price'])}'));

    String? joinType = customer['join_type']?.toString().isNotEmpty == true
        ? customer['join_type'].toString()
        : null;
    String? contractType =
        customer['contract_type']?.toString().isNotEmpty == true
            ? customer['contract_type'].toString()
            : null;
    int? installment = customer['installment'] is int
        ? customer['installment'] as int
        : int.tryParse('${customer['installment'] ?? ''}');
    String? tradeIn;
    if (customer['trade_in'] == true) {
      tradeIn = 'O';
    } else if (customer['trade_in'] == false) {
      tradeIn = 'X';
    }

    int currentTotalRebate() {
      return _calcTotalRebate(
        rebate: _toInt(rebateController.text),
        addRebate: _toInt(addRebateController.text),
        hiddenRebate: _toInt(hiddenRebateController.text),
        deduction: _toInt(deductionController.text),
        supportMoney: _toInt(supportMoneyController.text),
        payment: _toInt(paymentController.text),
        deposit: _toInt(depositController.text),
        tradePrice: _toInt(tradePriceController.text),
      );
    }

    int currentTax() => _calcTax(currentTotalRebate());
    int currentMargin() => _calcMargin(currentTotalRebate(), currentTax());

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          void onMoneyChanged(TextEditingController controller, String value) {
            _applyMoneyFormat(controller, value);
            setDialogState(() {});
          }

          return AlertDialog(
            title: const Text('고객 수정'),
            content: SizedBox(
              width: 600,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _input('고객명', nameController),
                    _input(
                      '휴대폰번호',
                      phoneController,
                      keyboardType: TextInputType.phone,
                      onChanged: (value) {
                        final formatted = _formatPhone(value);
                        phoneController.value = TextEditingValue(
                          text: formatted,
                          selection:
                              TextSelection.collapsed(offset: formatted.length),
                        );
                      },
                    ),
                    _input('통신사/거래처', carrierController),
                    _input('기존통신사', previousCarrierController),
                    _input('모델명', modelController),
                    _input('요금제', planController),
                    _input('부가서비스', addServiceController),
                    _dropdown<String>(
                      label: '가입유형',
                      value: joinType,
                      items: const ['신규', '번호이동', '기변'],
                      onChanged: (v) => setDialogState(() => joinType = v),
                    ),
                    _dropdown<String>(
                      label: '공시/선약',
                      value: contractType,
                      items: const ['공시', '선약'],
                      onChanged: (v) => setDialogState(() => contractType = v),
                    ),
                    _dropdown<int>(
                      label: '할부개월',
                      value: installment,
                      items: const [0, 12, 24, 36, 48],
                      onChanged: (v) => setDialogState(() => installment = v),
                    ),
                    _dropdown<String>(
                      label: '중고폰반납',
                      value: tradeIn,
                      items: const ['O', 'X'],
                      onChanged: (v) => setDialogState(() => tradeIn = v),
                    ),
                    _input(
                      '리베이트',
                      rebateController,
                      keyboardType: TextInputType.number,
                      onChanged: (v) => onMoneyChanged(rebateController, v),
                    ),
                    _input(
                      '부가리베이트',
                      addRebateController,
                      keyboardType: TextInputType.number,
                      onChanged: (v) => onMoneyChanged(addRebateController, v),
                    ),
                    _input(
                      '히든리베이트',
                      hiddenRebateController,
                      keyboardType: TextInputType.number,
                      onChanged: (v) =>
                          onMoneyChanged(hiddenRebateController, v),
                    ),
                    _input(
                      '차감항목',
                      deductionController,
                      keyboardType: TextInputType.number,
                      onChanged: (v) => onMoneyChanged(deductionController, v),
                    ),
                    _input(
                      '유통망지원금',
                      supportMoneyController,
                      keyboardType: TextInputType.number,
                      onChanged: (v) =>
                          onMoneyChanged(supportMoneyController, v),
                    ),
                    _input(
                      '결제',
                      paymentController,
                      keyboardType: TextInputType.number,
                      onChanged: (v) => onMoneyChanged(paymentController, v),
                    ),
                    _input(
                      '입금',
                      depositController,
                      keyboardType: TextInputType.number,
                      onChanged: (v) => onMoneyChanged(depositController, v),
                    ),
                    _input(
                      '매입금액',
                      tradePriceController,
                      keyboardType: TextInputType.number,
                      onChanged: (v) => onMoneyChanged(tradePriceController, v),
                    ),
                    _input('히든내용', hiddenNoteController),
                    _input('차감내용', deductionNoteController),
                    _input('결제내용', paymentNoteController),
                    _input('은행/계좌/예금주', bankInfoController),
                    _input('반납모델', tradeModelController),
                    _input('메모', memoController, maxLines: 4),
                    _input('개통매장', storeController),
                    _input('모바일', mobileController),
                    _input('2nd', secondController),
                    _input('담당자', staffController),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3F8),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFFFD3E5)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '총리베이트: ${_money(currentTotalRebate())}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '세금: ${_money(currentTax())}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '마진: ${_money(currentMargin())}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
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
                onPressed: () async {
                  final totalRebate = currentTotalRebate();
                  final tax = currentTax();
                  final margin = currentMargin();

                  try {
                    await supabase.from('customers').update({
                      'name': nameController.text.trim(),
                      'phone': phoneController.text.trim(),
                      'carrier': carrierController.text.trim(),
                      'previous_carrier': previousCarrierController.text.trim(),
                      'model': modelController.text.trim(),
                      'plan': planController.text.trim(),
                      'add_service': addServiceController.text.trim(),
                      'join_type': joinType,
                      'contract_type': contractType,
                      'installment': installment,
                      'trade_in': tradeIn == null ? null : tradeIn == 'O',
                      'rebate': _toInt(rebateController.text),
                      'add_rebate': _toInt(addRebateController.text),
                      'hidden_rebate': _toInt(hiddenRebateController.text),
                      'deduction': _toInt(deductionController.text),
                      'support_money': _toInt(supportMoneyController.text),
                      'payment': _toInt(paymentController.text),
                      'deposit': _toInt(depositController.text),
                      'trade_price': _toInt(tradePriceController.text),
                      'hidden_note': hiddenNoteController.text.trim(),
                      'deduction_note': deductionNoteController.text.trim(),
                      'payment_note': paymentNoteController.text.trim(),
                      'bank_info': bankInfoController.text.trim(),
                      'trade_model': tradeModelController.text.trim(),
                      'memo': memoController.text.trim(),
                      'store': normalizeStoreName(storeController.text.trim()),
                      'mobile': mobileController.text.trim(),
                      'second': secondController.text.trim(),
                      'staff': staffController.text.trim(),
                      'total_rebate': totalRebate,
                      'tax': tax,
                      'margin': margin,
                    }).eq('id', customer['id']);

                    if (mounted) Navigator.pop(context);
                    _showCenterMessage('고객 수정 완료');
                    fetchCustomers(keyword: searchController.text);
                  } catch (e) {
                    _logUiError('수정 실패: $e');
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

  void showDetail(Map<String, dynamic> customer) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF7F8FA),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.9,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Container(
                    width: 56,
                    height: 6,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD1D5DB),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0xFFE7E9EE)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.person_rounded,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _displayName(
                                    customer['name']?.toString() ?? ''),
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF111827),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_displayPhone(customer['phone']?.toString() ?? '')} · ${_text(customer['carrier'])}',
                                style: const TextStyle(
                                  color: Color(0xFF6B7280),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _sectionCard(
                    title: '기본 정보',
                    children: [
                      _detailRow('가입일', _date(customer['join_date'])),
                      _detailRow('M+3', customer['m3']),
                      _detailRow('M+6', customer['m6']),
                      _detailRow('고객명',
                          _displayName(customer['name']?.toString() ?? '')),
                      _detailRow('담당자', customer['staff']),
                      _detailRow('휴대폰번호',
                          _displayPhone(customer['phone']?.toString() ?? '')),
                      _detailRow('개통매장', customer['store']),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _sectionCard(
                    title: '개통 정보',
                    children: [
                      _detailRow('가입유형', customer['join_type']),
                      _detailRow('통신사/거래처', customer['carrier']),
                      _detailRow('기존통신사', customer['previous_carrier']),
                      _detailRow('모델명', customer['model']),
                      _detailRow('요금제', customer['plan']),
                      _detailRow('부가서비스', customer['add_service']),
                      _detailRow('공시/선약', customer['contract_type']),
                      _detailRow('할부개월', customer['installment']),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _sectionCard(
                    title: '정산 정보',
                    children: [
                      _detailMoneyRow('리베이트', customer['rebate']),
                      _detailMoneyRow('부가리베이트', customer['add_rebate']),
                      _detailMoneyRow('히든리베이트', customer['hidden_rebate']),
                      _detailMoneyRow('차감항목', customer['deduction']),
                      _detailMoneyRow('유통망지원금', customer['support_money']),
                      _detailMoneyRow('결제', customer['payment']),
                      _detailMoneyRow('입금', customer['deposit']),
                      _detailMoneyRow('매입금액', customer['trade_price']),
                      const Divider(height: 24),
                      _detailMoneyRow('총리베이트', customer['total_rebate']),
                      _detailMoneyRow('세금', customer['tax']),
                      _detailMoneyRow('마진', customer['margin']),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _sectionCard(
                    title: '추가 / 메모 정보',
                    children: [
                      _detailRow('메모', customer['memo']),
                      _detailRow('모바일', customer['mobile']),
                      _detailRow('2nd', customer['second']),
                      _detailRow('히든내용', customer['hidden_note']),
                      _detailRow('차감내용', customer['deduction_note']),
                      _detailRow('결제내용', customer['payment_note']),
                      _detailRow(
                        '은행/계좌/예금주',
                        _displayBankInfo(
                            customer['bank_info']?.toString() ?? ''),
                      ),
                      _detailRow(
                        '중고폰반납',
                        customer['trade_in'] == null
                            ? '-'
                            : customer['trade_in'] == true
                                ? 'O'
                                : 'X',
                      ),
                      _detailRow('반납모델', customer['trade_model']),
                    ],
                  ),
                  if (canEdit) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              showEditDialog(customer);
                            },
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('수정'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              showDeleteDialog(customer);
                            },
                            icon: const Icon(Icons.delete_outline),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                            label: const Text('삭제'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _summaryTile({
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        height: 88,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
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
        ),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 34,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    value,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF111827),
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
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

  Widget _filterField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    double width = 220,
  }) {
    return SizedBox(
      width: width,
      height: 38,
      child: TextField(
        controller: controller,
        onChanged: (_) => fetchCustomers(),
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, size: 17, color: const Color(0xFF9CA3AF)),
          filled: true,
          fillColor: const Color(0xFFF9FAFB),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
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
            borderSide: const BorderSide(color: Color(0xFFC94C6E)),
          ),
        ),
      ),
    );
  }

  Widget _segmentedFilter({
    required List<String> options,
    required String selected,
    required ValueChanged<String> onSelected,
  }) {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE8E9EF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.map((option) {
          final active = option == selected;
          return InkWell(
            onTap: () => onSelected(option),
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? const Color(0xFFC94C6E) : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                option,
                style: TextStyle(
                  color: active ? Colors.white : const Color(0xFF6B7280),
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _customerTable(List<Map<String, dynamic>> visibleCustomers) {
    const baseWidths = <double>[
      104,
      92,
      108,
      138,
      92,
      118,
      110,
      150,
      170,
      150,
      92,
      86,
      126,
    ];
    const headers = [
      '가입일',
      '담당자',
      '고객명',
      '휴대폰번호',
      '가입유형',
      '통신사/거래처',
      '기존통신사',
      '모델명',
      '요금제',
      '부가서비스',
      '공시/선약',
      '할부개월',
      '',
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final baseWidth = baseWidths.reduce((a, b) => a + b);
        final tableWidth =
            constraints.maxWidth > baseWidth ? constraints.maxWidth : baseWidth;
        final extraWidth = tableWidth - baseWidth;
        final widths = [...baseWidths];
        widths[8] += extraWidth;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: tableWidth,
            child: Column(
              children: [
                Container(
                  height: 44,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF9FAFB),
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFF3F4F6)),
                    ),
                  ),
                  child: Row(
                    children: [
                      for (var i = 0; i < headers.length; i++)
                        _headerCell(headers[i], widths[i]),
                    ],
                  ),
                ),
                ...visibleCustomers.map((customer) {
                  final phone =
                      _displayPhone(customer['phone']?.toString() ?? '');
                  return InkWell(
                    onTap: () => showDetail(customer),
                    child: Container(
                      height: 58,
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Color(0xFFF9FAFB)),
                        ),
                      ),
                      child: Row(
                        children: [
                          _tableCell(_tableText(_date(customer['join_date'])),
                              widths[0]),
                          _tableCell(
                            _tableBadge(
                              _text(customer['staff']),
                              color: _staffColor(customer['staff']),
                            ),
                            widths[1],
                          ),
                          _tableCell(
                            _tableText(
                              _displayName(customer['name']?.toString() ?? ''),
                              strong: true,
                            ),
                            widths[2],
                          ),
                          _tableCell(_tableText(phone), widths[3]),
                          _tableCell(
                            _tableBadge(
                              _text(customer['join_type']),
                              color: _joinTypeColor(customer['join_type']),
                            ),
                            widths[4],
                          ),
                          _tableCell(
                            _tableBadge(
                              _text(customer['carrier']),
                              color: _carrierColor(customer['carrier']),
                            ),
                            widths[5],
                          ),
                          _tableCell(
                            _tableText(_text(customer['previous_carrier'])),
                            widths[6],
                          ),
                          _tableCell(
                            _tableText(_text(customer['model']), strong: true),
                            widths[7],
                          ),
                          _tableCell(
                              _tableText(_text(customer['plan'])), widths[8]),
                          _tableCell(
                            _tableText(_text(customer['add_service'])),
                            widths[9],
                          ),
                          _tableCell(
                            _tableBadge(
                              _text(customer['contract_type']),
                              color:
                                  _contractTypeColor(customer['contract_type']),
                            ),
                            widths[10],
                          ),
                          _tableCell(
                            _tableText('${_text(customer['installment'])}개월'),
                            widths[11],
                          ),
                          _tableCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _compactIconButton(
                                  tooltip: '상세',
                                  onPressed: () => showDetail(customer),
                                  icon: const Icon(Icons.visibility_outlined,
                                      size: 18),
                                ),
                                if (canEdit)
                                  _compactIconButton(
                                    tooltip: '수정',
                                    onPressed: () => showEditDialog(customer),
                                    icon: const Icon(Icons.edit_outlined,
                                        size: 18),
                                  ),
                                if (canDelete)
                                  _compactIconButton(
                                    tooltip: '삭제',
                                    onPressed: () => showDeleteDialog(customer),
                                    icon: const Icon(Icons.delete_outline,
                                        size: 18),
                                  ),
                              ],
                            ),
                            widths[12],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _headerCell(String label, double width) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF9CA3AF),
            fontSize: 11,
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
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Align(
          alignment: Alignment.centerLeft,
          child: child,
        ),
      ),
    );
  }

  Widget _tableText(String value, {bool strong = false}) {
    return Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: strong ? const Color(0xFF111827) : const Color(0xFF374151),
        fontSize: 12,
        fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
      ),
    );
  }

  Widget _tableBadge(String value, {Color color = const Color(0xFFC94C6E)}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 11,
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

  Widget _pagination({
    required int totalItems,
    required int safePage,
    required int totalPages,
  }) {
    final start = totalItems == 0 ? 0 : safePage * pageSize + 1;
    var end = (safePage + 1) * pageSize;
    if (end > totalItems) end = totalItems;

    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Color(0xFFF3F4F6)),
        ),
      ),
      child: Row(
        children: [
          Text(
            '$start-$end / 총 $totalItems건',
            style: const TextStyle(
              color: Color(0xFF9CA3AF),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: '이전',
            onPressed: safePage <= 0
                ? null
                : () => setState(() => currentPage = safePage - 1),
            icon: const Icon(Icons.chevron_left, size: 20),
          ),
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFC94C6E).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${safePage + 1} / $totalPages',
              style: const TextStyle(
                color: Color(0xFFC94C6E),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            tooltip: '다음',
            onPressed: safePage >= totalPages - 1
                ? null
                : () => setState(() => currentPage = safePage + 1),
            icon: const Icon(Icons.chevron_right, size: 20),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    searchController.dispose();
    dateSearchController.dispose();
    phoneSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalCustomers = customers.length;
    final newJoinCount =
        customers.where((e) => _text(e['join_type']).contains('신규')).length;
    final transferCount =
        customers.where((e) => _text(e['join_type']).contains('이동')).length;
    final deviceChangeCount = customers
        .where((e) =>
            _text(e['join_type']).contains('기기변경') ||
            _text(e['join_type']).contains('기변'))
        .length;
    final totalPages =
        customers.isEmpty ? 1 : ((customers.length + pageSize - 1) ~/ pageSize);
    final safePage = currentPage >= totalPages ? totalPages - 1 : currentPage;
    final pageStart = safePage * pageSize;
    var pageEnd = pageStart + pageSize;
    if (pageEnd > customers.length) pageEnd = customers.length;
    final visibleCustomers = customers.sublist(pageStart, pageEnd);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      body: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _summaryTile(
                  label: '전체고객',
                  value: '$totalCustomers명',
                  color: const Color(0xFF6B7280),
                ),
                const SizedBox(width: 14),
                _summaryTile(
                  label: '신규개통',
                  value: '$newJoinCount명',
                  color: const Color(0xFF10B981),
                ),
                const SizedBox(width: 14),
                _summaryTile(
                  label: '번호이동',
                  value: '$transferCount명',
                  color: const Color(0xFF3B82F6),
                ),
                const SizedBox(width: 14),
                _summaryTile(
                  label: '기기변경',
                  value: '$deviceChangeCount명',
                  color: const Color(0xFFF59E0B),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
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
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                      child: Row(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _filterField(
                                    controller: dateSearchController,
                                    hint: '가입일 검색',
                                    icon: Icons.calendar_today_outlined,
                                    width: 160,
                                  ),
                                  const SizedBox(width: 8),
                                  _filterField(
                                    controller: searchController,
                                    hint: '고객명 검색',
                                    icon: Icons.person_search_outlined,
                                    width: 190,
                                  ),
                                  const SizedBox(width: 8),
                                  _filterField(
                                    controller: phoneSearchController,
                                    hint: '연락처 검색',
                                    icon: Icons.phone_iphone_outlined,
                                    width: 190,
                                  ),
                                  const SizedBox(width: 8),
                                  _segmentedFilter(
                                    options: const ['전체', 'SKT', 'KT', 'LGU+'],
                                    selected: selectedCarrierFilter,
                                    onSelected: (value) {
                                      setState(() {
                                        selectedCarrierFilter = value;
                                        currentPage = 0;
                                      });
                                      fetchCustomers();
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  _segmentedFilter(
                                    options: const ['전체', '신규', '번호이동', '기기변경'],
                                    selected: selectedJoinTypeFilter,
                                    onSelected: (value) {
                                      setState(() {
                                        selectedJoinTypeFilter = value;
                                        currentPage = 0;
                                      });
                                      fetchCustomers();
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: () => fetchCustomers(),
                            icon: const Icon(Icons.refresh, size: 17),
                            label: const Text('새로고침'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF6B7280),
                              elevation: 0,
                              side: const BorderSide(color: Color(0xFFE8E9EF)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFFF3F4F6)),
                    Expanded(
                      child: isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : customers.isEmpty
                              ? const Center(child: Text('고객 정보가 없습니다'))
                              : Scrollbar(
                                  thumbVisibility: true,
                                  child: SingleChildScrollView(
                                    child: _customerTable(visibleCustomers),
                                  ),
                                ),
                    ),
                    _pagination(
                      totalItems: totalCustomers,
                      safePage: safePage,
                      totalPages: totalPages,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
