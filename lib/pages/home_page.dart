import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crm_app/services/rate_card_service.dart';
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
  String defaultManagerName = '';
  String rateCardMessage = '';
  Timer? rateCardDebounce;
  bool isApplyingRateCard = false;

  String? joinType;
  String? previousCarrier;
  String? contractType;
  int? installment;
  String? tradeIn;

  final NumberFormat moneyFormat = NumberFormat('#,###');
  late final RateCardService rateCardService;

  @override
  void initState() {
    super.initState();
    rateCardService = RateCardService(supabase);
    _setTodayJoinDate();
    _loadDefaultManagerName();
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
    rateCardDebounce?.cancel();
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

  Future<void> _loadDefaultManagerName() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final profile = await supabase
          .from('profiles')
          .select('name')
          .eq('id', user.id)
          .maybeSingle();
      final name = profile?['name']?.toString().trim() ?? '';
      final managerName = name.isEmpty ? (user.email ?? '') : name;
      if (!mounted || managerName.isEmpty) return;

      setState(() {
        defaultManagerName = managerName;
        if (managerController.text.trim().isEmpty) {
          managerController.text = managerName;
        }
      });
    } catch (e) {
      logUiError('manager profile load failed: $e');
    }
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

  void scheduleRateCardLookup() {
    if (isApplyingRateCard) return;
    rateCardDebounce?.cancel();
    rateCardDebounce = Timer(
      const Duration(milliseconds: 350),
      applyRateCardIfMatched,
    );
  }

  Future<void> applyRateCardIfMatched() async {
    final modelName = modelController.text.trim();
    final planName = planController.text.trim();
    if (modelName.isEmpty || planName.isEmpty) {
      if (mounted && rateCardMessage.isNotEmpty) {
        setState(() => rateCardMessage = '');
      }
      return;
    }

    try {
      final rule = await rateCardService.findBestMatch(
        carrier: carrierController.text.trim(),
        modelName: modelName,
        planName: planName,
        addServiceName: addServiceController.text.trim(),
        joinType: joinType,
        contractType: contractType,
      );
      if (!mounted) return;

      if (rule == null) {
        setState(() {
          rateCardMessage = '단가표에서 일치하는 항목을 찾지 못했습니다.';
        });
        return;
      }

      isApplyingRateCard = true;
      rebateController.text = moneyFormat.format(rule.baseRebate);
      addRebateController.text = moneyFormat.format(rule.addRebate);
      deductionController.text = moneyFormat.format(rule.deduction);
      isApplyingRateCard = false;

      setState(() {
        rateCardMessage =
            '단가표 적용: ${rule.carrier} / ${rule.modelName} / ${rule.planName}';
      });
    } catch (e) {
      debugPrint('rate card lookup failed: $e');
    }
  }

  int calcTotalRebate() {
    return parseInt(rebateController.text) +
        parseInt(addRebateController.text) +
        parseInt(hiddenRebateController.text);
  }

  int calcMargin() {
    return calcTotalRebate() -
        parseInt(supportMoneyController.text) -
        parseInt(paymentController.text) -
        parseInt(depositController.text);
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

    final totalRebate = rebate + addRebate + hiddenRebate;

    final tax = 0;
    final margin = totalRebate - supportMoney - payment - deposit;

    try {
      await supabase.from('customers').insert({
        'join_date': currentJoinDate.toIso8601String(),
        'm3': formatMonth(currentJoinDate.add(const Duration(days: 90))),
        'm6': formatMonth(currentJoinDate.add(const Duration(days: 180))),
        'staff': managerController.text.trim().isEmpty
            ? (defaultManagerName.isEmpty
                ? (user.email ?? '')
                : defaultManagerName)
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
      managerController.text = defaultManagerName;
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

  Widget formRow(
    List<Widget> children, {
    required bool mobile,
  }) {
    if (mobile) {
      return Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1) const SizedBox(height: 12),
          ],
        ],
      );
    }

    return Row(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          Expanded(child: children[i]),
          if (i < children.length - 1) const SizedBox(width: 12),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.of(context).size.width < 900;
    final currentJoinDate = _formJoinDate();
    final m3 = currentJoinDate == null
        ? '-'
        : formatMonth(currentJoinDate.add(const Duration(days: 90)));
    final m6 = currentJoinDate == null
        ? '-'
        : formatMonth(currentJoinDate.add(const Duration(days: 180)));

    final totalRebate = calcTotalRebate();
    final margin = calcMargin();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(mobile ? 14 : 28),
        child: Column(
          children: [
            sectionCard(
              title: '고객 등록',
              subtitle: '가입일, 고객명, 휴대폰번호만 필수입니다.',
              child: Column(
                children: [
                  formRow([
                    pair(
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
                    pair(
                      label: '담당자',
                      field: inputBox(managerController),
                    ),
                    pair(
                      label: '고객명',
                      field: inputBox(nameController),
                    ),
                    pair(
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
                  ], mobile: mobile),
                  const SizedBox(height: 12),
                  formRow([
                    pair(
                      label: '가입유형',
                      field: dropdownBox<String>(
                        value: joinType,
                        hint: '선택',
                        items: const ['신규', '번호이동', '기변'],
                        onChanged: (value) {
                          setState(() {
                            joinType = value;
                          });
                          scheduleRateCardLookup();
                        },
                      ),
                    ),
                    pair(
                      label: '통신사/거래처',
                      field: inputBox(
                        carrierController,
                        onChanged: (_) => scheduleRateCardLookup(),
                      ),
                    ),
                    pair(
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
                    pair(
                      label: '모델명',
                      field: inputBox(
                        modelController,
                        onChanged: (_) => scheduleRateCardLookup(),
                      ),
                    ),
                  ], mobile: mobile),
                  const SizedBox(height: 12),
                  formRow([
                    pair(
                      label: '요금제',
                      field: inputBox(
                        planController,
                        onChanged: (_) => scheduleRateCardLookup(),
                      ),
                    ),
                    pair(
                      label: '부가서비스',
                      field: inputBox(
                        addServiceController,
                        onChanged: (_) => scheduleRateCardLookup(),
                      ),
                    ),
                    pair(
                      label: '공시/선약',
                      field: dropdownBox<String>(
                        value: contractType,
                        hint: '선택',
                        items: const ['공시', '선약'],
                        onChanged: (value) {
                          setState(() {
                            contractType = value;
                          });
                          scheduleRateCardLookup();
                        },
                      ),
                    ),
                    pair(
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
                  ], mobile: mobile),
                  const SizedBox(height: 12),
                  if (rateCardMessage.isNotEmpty) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        rateCardMessage,
                        style: const TextStyle(
                          color: Color(0xFFC94C6E),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  formRow([
                    pair(
                      label: '리베이트',
                      field: inputBox(
                        rebateController,
                        keyboardType: TextInputType.number,
                        onChanged: (value) =>
                            applyMoneyFormat(rebateController, value),
                      ),
                    ),
                    pair(
                      label: '부가리베이트',
                      field: inputBox(
                        addRebateController,
                        keyboardType: TextInputType.number,
                        onChanged: (value) =>
                            applyMoneyFormat(addRebateController, value),
                      ),
                    ),
                    pair(
                      label: '히든리베이트',
                      field: inputBox(
                        hiddenRebateController,
                        keyboardType: TextInputType.number,
                        onChanged: (value) =>
                            applyMoneyFormat(hiddenRebateController, value),
                      ),
                    ),
                    pair(
                      label: '차감항목',
                      field: inputBox(
                        deductionController,
                        keyboardType: TextInputType.number,
                        onChanged: (value) =>
                            applyMoneyFormat(deductionController, value),
                      ),
                    ),
                  ], mobile: mobile),
                  const SizedBox(height: 12),
                  formRow([
                    pair(
                      label: '유통망지원금',
                      field: inputBox(
                        supportMoneyController,
                        keyboardType: TextInputType.number,
                        onChanged: (value) =>
                            applyMoneyFormat(supportMoneyController, value),
                      ),
                    ),
                    pair(
                      label: '결제',
                      field: inputBox(
                        paymentController,
                        keyboardType: TextInputType.number,
                        onChanged: (value) =>
                            applyMoneyFormat(paymentController, value),
                      ),
                    ),
                    pair(
                      label: '입금',
                      field: inputBox(
                        depositController,
                        keyboardType: TextInputType.number,
                        onChanged: (value) =>
                            applyMoneyFormat(depositController, value),
                      ),
                    ),
                    pair(
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
                  ], mobile: mobile),
                  const SizedBox(height: 18),
                  formRow([
                    summaryBox('총리베이트', moneyText(totalRebate)),
                    summaryBox('마진', moneyText(margin)),
                  ], mobile: mobile),
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
                    formRow([
                      pair(
                        label: '히든내용',
                        field: inputBox(hiddenNoteController),
                      ),
                      pair(
                        label: '차감내용',
                        field: inputBox(deductionNoteController),
                      ),
                      pair(
                        label: '결제내용',
                        field: inputBox(paymentNoteController),
                      ),
                      pair(
                        label: '은행/계좌/예금주',
                        field: inputBox(bankController),
                      ),
                    ], mobile: mobile),
                    const SizedBox(height: 12),
                    formRow([
                      pair(
                        label: '매입금액',
                        field: inputBox(
                          tradePriceController,
                          keyboardType: TextInputType.number,
                          onChanged: (value) =>
                              applyMoneyFormat(tradePriceController, value),
                        ),
                      ),
                      pair(
                        label: '마진(자동)',
                        field: Container(
                          height: 52,
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE7E9EE)),
                          ),
                          child: Text(moneyText(margin)),
                        ),
                      ),
                      pair(
                        label: '반납모델',
                        field: inputBox(tradeModelController),
                      ),
                    ], mobile: mobile),
                    const SizedBox(height: 12),
                    formRow([
                      pair(
                        label: '개통매장',
                        field: inputBox(storeController),
                      ),
                      pair(
                        label: '모바일',
                        field: inputBox(mobileController),
                      ),
                      pair(
                        label: '2nd',
                        field: inputBox(secondController),
                      ),
                      pair(
                        label: '회차',
                        field: Container(
                          height: 52,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE7E9EE)),
                          ),
                          child: Text('M+3: $m3 / M+6: $m6'),
                        ),
                      ),
                    ], mobile: mobile),
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
                      width: mobile ? double.infinity : 168,
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
