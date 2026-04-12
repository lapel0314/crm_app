import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crm_app/utils/store_utils.dart';

final supabase = Supabase.instance.client;

class HomePage extends StatefulWidget {
  final String role;
  final String currentStore;

  const HomePage({super.key, required this.role, required this.currentStore});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final managerController = TextEditingController();
  final joinDateController = TextEditingController();
  final nameController = TextEditingController();
  final phoneController = TextEditingController();

  final carrierController = TextEditingController();
  final modelController = TextEditingController();
  final planController = TextEditingController();
  final addServiceController = TextEditingController();

  final rebateController = TextEditingController();
  final addRebateController = TextEditingController();
  final hiddenRebateController = TextEditingController();
  final deductionController = TextEditingController();
  final supportMoneyController = TextEditingController();
  final paymentController = TextEditingController();
  final depositController = TextEditingController();
  final tradeModelController = TextEditingController();

  final hiddenNoteController = TextEditingController();
  final deductionNoteController = TextEditingController();
  final paymentNoteController = TextEditingController();
  final bankController = TextEditingController();
  final tradePriceController = TextEditingController();
  final memoController = TextEditingController();
  final storeController = TextEditingController();
  final mobileController = TextEditingController();
  final secondController = TextEditingController();

  DateTime? joinDate;
  bool showMore = false;

  String? joinType;
  String? previousCarrier;
  String? contractType;
  int? installment;
  String? tradeIn;

  final NumberFormat moneyFormat = NumberFormat('#,###');

  @override
  void initState() {
    super.initState();
    _setTodayJoinDate();
  }

  @override
  void dispose() {
    for (final c in [
      managerController,
      joinDateController,
      nameController,
      phoneController,
      carrierController,
      modelController,
      planController,
      addServiceController,
      rebateController,
      addRebateController,
      hiddenRebateController,
      deductionController,
      supportMoneyController,
      paymentController,
      depositController,
      tradeModelController,
      hiddenNoteController,
      deductionNoteController,
      paymentNoteController,
      bankController,
      tradePriceController,
      memoController,
      storeController,
      mobileController,
      secondController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String formatMonth(DateTime date) => DateFormat('yy-MM').format(date);

  void _setTodayJoinDate() {
    final today = DateTime.now();
    joinDate = today;
    joinDateController.text = DateFormat('yyyy-MM-dd').format(today);
  }

  DateTime? _formJoinDate() {
    final text = joinDateController.text.trim();
    if (text.isEmpty) return null;
    final parsed = DateTime.tryParse(text);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  String formatPhone(String input) {
    final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length <= 3) return digits;
    if (digits.length <= 7) {
      return '${digits.substring(0, 3)}-${digits.substring(3)}';
    }
    final cut = digits.length > 11 ? 11 : digits.length;
    return '${digits.substring(0, 3)}-${digits.substring(3, 7)}-${digits.substring(7, cut)}';
  }

  int parseInt(String value) {
    final cleaned = value.replaceAll(',', '').trim();
    return int.tryParse(cleaned) ?? 0;
  }

  String formatMoneyInput(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleaned.isEmpty) return '';
    return moneyFormat.format(int.parse(cleaned));
  }

  void applyMoneyFormat(TextEditingController controller, String value) {
    final formatted = formatMoneyInput(value);
    controller.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
    setState(() {});
  }

  int calcTotalRebate() {
    return parseInt(rebateController.text) +
        parseInt(addRebateController.text) +
        parseInt(hiddenRebateController.text) -
        parseInt(deductionController.text) -
        parseInt(supportMoneyController.text) -
        parseInt(paymentController.text) -
        parseInt(depositController.text) +
        parseInt(tradePriceController.text);
  }

  int calcTax() {
    return (calcTotalRebate() * 0.13).round();
  }

  int calcMargin() {
    return calcTotalRebate() - calcTax();
  }

  String moneyText(int value) => '${moneyFormat.format(value)}원';

  void showMessage(String text) {
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
                    text,
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

  void logUiError(String text) {
    debugPrint(text);
  }

  Future<void> save() async {
    final currentJoinDate = _formJoinDate();

    if (currentJoinDate == null ||
        nameController.text.trim().isEmpty ||
        phoneController.text.trim().isEmpty) {
      showMessage('가입일 / 고객명 / 휴대폰번호는 필수입니다.');
      return;
    }

    final user = supabase.auth.currentUser;
    if (user == null) {
      showMessage('로그인 정보를 확인해주세요.');
      return;
    }

    final rebate = parseInt(rebateController.text);
    final addRebate = parseInt(addRebateController.text);
    final hiddenRebate = parseInt(hiddenRebateController.text);
    final deduction = parseInt(deductionController.text);
    final supportMoney = parseInt(supportMoneyController.text);
    final payment = parseInt(paymentController.text);
    final deposit = parseInt(depositController.text);
    final tradePrice = parseInt(tradePriceController.text);

    final totalRebate = rebate +
        addRebate +
        hiddenRebate -
        deduction -
        supportMoney -
        payment -
        deposit +
        tradePrice;

    final tax = (totalRebate * 0.13).round();
    final margin = totalRebate - tax;

    try {
      await supabase.from('customers').insert({
        'join_date': currentJoinDate.toIso8601String(),
        'm3': formatMonth(currentJoinDate.add(const Duration(days: 90))),
        'm6': formatMonth(currentJoinDate.add(const Duration(days: 180))),
        'staff': managerController.text.trim().isEmpty
            ? (user.email ?? '')
            : managerController.text.trim(),
        'name': nameController.text.trim(),
        'phone': phoneController.text.trim(),
        'join_type': joinType,
        'carrier': carrierController.text.trim(),
        'previous_carrier': previousCarrier,
        'model': modelController.text.trim(),
        'plan': planController.text.trim(),
        'add_service': addServiceController.text.trim(),
        'contract_type': contractType,
        'installment': installment,
        'rebate': rebate,
        'add_rebate': addRebate,
        'hidden_rebate': hiddenRebate,
        'hidden_note': hiddenNoteController.text.trim(),
        'deduction': deduction,
        'deduction_note': deductionNoteController.text.trim(),
        'support_money': supportMoney,
        'payment': payment,
        'payment_note': paymentNoteController.text.trim(),
        'deposit': deposit,
        'bank_info': bankController.text.trim(),
        'trade_in': tradeIn == 'O',
        'trade_model': tradeModelController.text.trim(),
        'trade_price': tradePrice,
        'total_rebate': totalRebate,
        'tax': tax,
        'margin': margin,
        'memo': memoController.text.trim(),
        'store': normalizeStoreName(storeController.text.trim().isEmpty
            ? widget.currentStore
            : storeController.text.trim()),
        'mobile': mobileController.text.trim(),
        'second': secondController.text.trim(),
        'created_by': user.id,
      });

      clearForm();
      showMessage('고객 등록 완료');
    } catch (e) {
      logUiError('저장 실패: $e');
    }
  }

  void clearForm() {
    for (final c in [
      managerController,
      nameController,
      phoneController,
      carrierController,
      modelController,
      planController,
      addServiceController,
      rebateController,
      addRebateController,
      hiddenRebateController,
      deductionController,
      supportMoneyController,
      paymentController,
      depositController,
      tradeModelController,
      hiddenNoteController,
      deductionNoteController,
      paymentNoteController,
      bankController,
      tradePriceController,
      memoController,
      storeController,
      mobileController,
      secondController,
    ]) {
      c.clear();
    }

    setState(() {
      _setTodayJoinDate();
      showMore = false;
      joinType = null;
      previousCarrier = null;
      contractType = null;
      installment = null;
      tradeIn = null;
    });
  }

  Widget sectionCard({
    required String title,
    required Widget child,
    String? subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: Color(0xFF111827),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(
                color: Color(0xFF6B7280),
              ),
            ),
          ],
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget labelBox(String text) {
    return Text(
      text,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Color(0xFF6B7280),
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget inputBox(
    TextEditingController controller, {
    TextInputType? keyboardType,
    int maxLines = 1,
    int? minLines,
    void Function(String)? onChanged,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      minLines: minLines,
      onChanged: onChanged,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
    );
  }

  Widget dropdownBox<T>({
    required T? value,
    required String hint,
    required List<T> items,
    required void Function(T?) onChanged,
  }) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
      items: items
          .map(
            (e) => DropdownMenuItem<T>(
              value: e,
              child: Text('$e'),
            ),
          )
          .toList(),
    );
  }

  Widget pair({
    required String label,
    required Widget field,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        labelBox(label),
        const SizedBox(height: 6),
        field,
      ],
    );
  }

  Widget summaryBox(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE8E9EF)),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFFC94C6E),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF6B7280),
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 18,
              color: Color(0xFF111827),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentJoinDate = _formJoinDate();
    final m3 = currentJoinDate == null
        ? '-'
        : formatMonth(currentJoinDate.add(const Duration(days: 90)));
    final m6 = currentJoinDate == null
        ? '-'
        : formatMonth(currentJoinDate.add(const Duration(days: 180)));

    final totalRebate = calcTotalRebate();
    final tax = calcTax();
    final margin = calcMargin();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            sectionCard(
              title: '고객 등록',
              subtitle: '가입일, 고객명, 휴대폰번호만 필수입니다.',
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: pair(
                          label: '가입일',
                          field: inputBox(
                            joinDateController,
                            keyboardType: TextInputType.datetime,
                            onChanged: (value) {
                              setState(() {
                                joinDate = DateTime.tryParse(value);
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: pair(
                          label: '담당자',
                          field: inputBox(managerController),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: pair(
                          label: '고객명',
                          field: inputBox(nameController),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: pair(
                          label: '휴대폰번호',
                          field: inputBox(
                            phoneController,
                            keyboardType: TextInputType.phone,
                            onChanged: (value) {
                              final formatted = formatPhone(value);
                              phoneController.value = TextEditingValue(
                                text: formatted,
                                selection: TextSelection.collapsed(
                                  offset: formatted.length,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: pair(
                          label: '가입유형',
                          field: dropdownBox<String>(
                            value: joinType,
                            hint: '선택',
                            items: const ['신규', '번호이동', '기변'],
                            onChanged: (value) {
                              setState(() {
                                joinType = value;
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: pair(
                          label: '통신사/거래처',
                          field: inputBox(carrierController),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: pair(
                          label: '기존통신사',
                          field: dropdownBox<String>(
                            value: previousCarrier,
                            hint: '선택',
                            items: const ['SK', 'KT', 'LG'],
                            onChanged: (value) {
                              setState(() {
                                previousCarrier = value;
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: pair(
                          label: '모델명',
                          field: inputBox(modelController),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: pair(
                          label: '요금제',
                          field: inputBox(planController),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: pair(
                          label: '부가서비스',
                          field: inputBox(addServiceController),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: pair(
                          label: '공시/선약',
                          field: dropdownBox<String>(
                            value: contractType,
                            hint: '선택',
                            items: const ['공시', '선약'],
                            onChanged: (value) {
                              setState(() {
                                contractType = value;
                              });
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: pair(
                          label: '할부개월',
                          field: dropdownBox<int>(
                            value: installment,
                            hint: '선택',
                            items: const [0, 12, 24, 36, 48],
                            onChanged: (value) {
                              setState(() {
                                installment = value;
                              });
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: pair(
                          label: '리베이트',
                          field: inputBox(
                            rebateController,
                            keyboardType: TextInputType.number,
                            onChanged: (value) =>
                                applyMoneyFormat(rebateController, value),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: pair(
                          label: '부가리베이트',
                          field: inputBox(
                            addRebateController,
                            keyboardType: TextInputType.number,
                            onChanged: (value) =>
                                applyMoneyFormat(addRebateController, value),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: pair(
                          label: '히든리베이트',
                          field: inputBox(
                            hiddenRebateController,
                            keyboardType: TextInputType.number,
                            onChanged: (value) =>
                                applyMoneyFormat(hiddenRebateController, value),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: pair(
                          label: '차감항목',
                          field: inputBox(
                            deductionController,
                            keyboardType: TextInputType.number,
                            onChanged: (value) =>
                                applyMoneyFormat(deductionController, value),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: pair(
                          label: '유통망지원금',
                          field: inputBox(
                            supportMoneyController,
                            keyboardType: TextInputType.number,
                            onChanged: (value) =>
                                applyMoneyFormat(supportMoneyController, value),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: pair(
                          label: '결제',
                          field: inputBox(
                            paymentController,
                            keyboardType: TextInputType.number,
                            onChanged: (value) =>
                                applyMoneyFormat(paymentController, value),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: pair(
                          label: '입금',
                          field: inputBox(
                            depositController,
                            keyboardType: TextInputType.number,
                            onChanged: (value) =>
                                applyMoneyFormat(depositController, value),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: pair(
                          label: '중고폰반납',
                          field: dropdownBox<String>(
                            value: tradeIn,
                            hint: '선택',
                            items: const ['O', 'X'],
                            onChanged: (value) {
                              setState(() {
                                tradeIn = value;
                              });
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: summaryBox('총리베이트', moneyText(totalRebate)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: summaryBox('세금', moneyText(tax)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: summaryBox('마진', moneyText(margin)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          showMore = !showMore;
                        });
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFC94C6E),
                        side: const BorderSide(color: Color(0xFFC94C6E)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: Icon(
                        showMore
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                      ),
                      label: Text(showMore ? '추가 항목 숨기기' : '추가 항목 펼치기'),
                    ),
                  ),
                  if (showMore) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: pair(
                            label: '히든내용',
                            field: inputBox(hiddenNoteController),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: pair(
                            label: '차감내용',
                            field: inputBox(deductionNoteController),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: pair(
                            label: '결제내용',
                            field: inputBox(paymentNoteController),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: pair(
                            label: '은행/계좌/예금주',
                            field: inputBox(bankController),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: pair(
                            label: '매입금액',
                            field: inputBox(
                              tradePriceController,
                              keyboardType: TextInputType.number,
                              onChanged: (value) =>
                                  applyMoneyFormat(tradePriceController, value),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: pair(
                            label: '세금(자동)',
                            field: Container(
                              height: 52,
                              alignment: Alignment.centerLeft,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(8),
                                border:
                                    Border.all(color: const Color(0xFFE7E9EE)),
                              ),
                              child: Text(moneyText(tax)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: pair(
                            label: '마진(자동)',
                            field: Container(
                              height: 52,
                              alignment: Alignment.centerLeft,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(8),
                                border:
                                    Border.all(color: const Color(0xFFE7E9EE)),
                              ),
                              child: Text(moneyText(margin)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: pair(
                            label: '반납모델',
                            field: inputBox(tradeModelController),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: pair(
                            label: '개통매장',
                            field: inputBox(storeController),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: pair(
                            label: '모바일',
                            field: inputBox(mobileController),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: pair(
                            label: '2nd',
                            field: inputBox(secondController),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            height: 52,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(8),
                              border:
                                  Border.all(color: const Color(0xFFE7E9EE)),
                            ),
                            child: Text('M+3: $m3 / M+6: $m6'),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  pair(
                    label: '메모',
                    field: inputBox(
                      memoController,
                      maxLines: 6,
                      minLines: 4,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      width: 168,
                      height: 44,
                      child: ElevatedButton(
                        onPressed: save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFC94C6E),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          '고객 등록',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
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
}
