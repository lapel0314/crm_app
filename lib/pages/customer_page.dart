import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class CustomerPage extends StatefulWidget {
  final String role;

  const CustomerPage({super.key, required this.role});

  @override
  State<CustomerPage> createState() => _CustomerPageState();
}

class _CustomerPageState extends State<CustomerPage> {
  final searchController = TextEditingController();
  final NumberFormat moneyFormat = NumberFormat('#,###');

  List<Map<String, dynamic>> customers = [];
  bool isLoading = true;

  bool get isPublicRole => widget.role == '공개용';
  bool get canEdit => !isPublicRole;
  bool get canDelete => !isPublicRole;

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

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> fetchCustomers({String keyword = ''}) async {
    setState(() {
      isLoading = true;
    });

    try {
      final List<dynamic> data = keyword.trim().isEmpty
          ? await supabase
              .from('customers')
              .select()
              .order('join_date', ascending: true)
              .order('created_at', ascending: true)
          : await supabase
              .from('customers')
              .select()
              .or(
                'name.ilike.%${keyword.trim()}%,phone.ilike.%${keyword.trim()}%,carrier.ilike.%${keyword.trim()}%,model.ilike.%${keyword.trim()}%,store.ilike.%${keyword.trim()}%,staff.ilike.%${keyword.trim()}%,memo.ilike.%${keyword.trim()}%',
              )
              .order('join_date', ascending: true)
              .order('created_at', ascending: true);

      setState(() {
        customers = data.map((e) => Map<String, dynamic>.from(e)).toList();
      });
    } catch (e) {
      _showSnackBar('고객 조회 실패: $e');
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
      _showSnackBar('고객 삭제 완료');
      fetchCustomers(keyword: searchController.text);
    } catch (e) {
      _showSnackBar('삭제 실패: $e');
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

  Widget _mainField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              '$label:',
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Color(0xFF111827),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              _text(value),
              style: const TextStyle(
                color: Color(0xFF111827),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailMoneyRow(String label, dynamic value) {
    return _detailRow(label, _money(value));
  }

  Widget _sectionCard({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE7E9EE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
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
                      'store': storeController.text.trim(),
                      'mobile': mobileController.text.trim(),
                      'second': secondController.text.trim(),
                      'staff': staffController.text.trim(),
                      'total_rebate': totalRebate,
                      'tax': tax,
                      'margin': margin,
                    }).eq('id', customer['id']);

                    if (mounted) Navigator.pop(context);
                    _showSnackBar('고객 수정 완료');
                    fetchCustomers(keyword: searchController.text);
                  } catch (e) {
                    _showSnackBar('수정 실패: $e');
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
                          decoration: const BoxDecoration(
                            color: Color(0xFFFFEEF5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.person_rounded,
                            color: Color(0xFFFF2D8D),
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

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('고객 DB (${widget.role})'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: '이름 / 전화번호 / 모델명 / 담당자 / 매장 검색',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onChanged: (value) => fetchCustomers(keyword: value),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () =>
                      fetchCustomers(keyword: searchController.text),
                  icon: const Icon(Icons.refresh),
                  label: const Text('새로고침'),
                ),
              ],
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : customers.isEmpty
                    ? const Center(child: Text('고객 정보가 없습니다'))
                    : ListView.builder(
                        itemCount: customers.length,
                        itemBuilder: (context, index) {
                          final customer = customers[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            child: ListTile(
                              onTap: () => showDetail(customer),
                              title: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _mainField(
                                      '가입일', _date(customer['join_date'])),
                                  _mainField('M+3', _text(customer['m3'])),
                                  _mainField('M+6', _text(customer['m6'])),
                                  _mainField(
                                    '고객명',
                                    _displayName(
                                        customer['name']?.toString() ?? ''),
                                  ),
                                  _mainField(
                                      '통신사/거래처', _text(customer['carrier'])),
                                  _mainField(
                                    '휴대폰번호',
                                    _displayPhone(
                                        customer['phone']?.toString() ?? ''),
                                  ),
                                  _mainField('모델명', _text(customer['model'])),
                                  _mainField('메모', _text(customer['memo'])),
                                  _mainField('개통매장', _text(customer['store'])),
                                  _mainField('담당자', _text(customer['staff'])),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: '상세',
                                    onPressed: () => showDetail(customer),
                                    icon: const Icon(Icons.visibility_outlined),
                                  ),
                                  if (canEdit)
                                    IconButton(
                                      tooltip: '수정',
                                      onPressed: () => showEditDialog(customer),
                                      icon: const Icon(Icons.edit_outlined),
                                    ),
                                  if (canDelete)
                                    IconButton(
                                      tooltip: '삭제',
                                      onPressed: () =>
                                          showDeleteDialog(customer),
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
