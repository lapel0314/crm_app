import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crm_app/utils/store_utils.dart';

final supabase = Supabase.instance.client;

class WiredMembersPage extends StatefulWidget {
  final String role;
  final String currentStore;

  const WiredMembersPage({
    super.key,
    required this.role,
    required this.currentStore,
  });

  @override
  State<WiredMembersPage> createState() => _WiredMembersPageState();
}

class _WiredMembersPageState extends State<WiredMembersPage> {
  final searchController = TextEditingController();
  final NumberFormat moneyFormat = NumberFormat('#,###');

  bool isLoading = false;
  List<Map<String, dynamic>> members = [];
  String selectedCarrierFilter = '전체';
  int currentPage = 0;
  static const int pageSize = 20;

  bool get canEdit => ['대표', '개발자', '사장', '점장', '사원'].contains(widget.role);
  bool get canDelete => ['대표', '개발자', '사장', '점장'].contains(widget.role);
  bool get canViewAllStores => isPrivilegedRole(widget.role);

  @override
  void initState() {
    super.initState();
    fetchMembers();
  }

  String formatPhone(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length <= 3) return digits;
    if (digits.length <= 7) {
      return '${digits.substring(0, 3)}-${digits.substring(3)}';
    }
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

  int parseInt(dynamic value) {
    if (value == null) return 0;
    final cleaned = value.toString().replaceAll(',', '').trim();
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
  }

  String money(dynamic value) => '${moneyFormat.format(parseInt(value))}원';

  int calcTax({
    required int rebate,
    required int extra,
  }) {
    return ((rebate + extra) * 0.133).round();
  }

  int calcMargin({
    required int rebate,
    required int prepaid,
    required int postpaid,
    required int extra,
    required int tax,
  }) {
    return rebate - prepaid - postpaid + extra + tax;
  }

  int calcIncentive({
    required int margin,
  }) {
    return margin;
  }

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

  Future<void> fetchMembers({String keyword = ''}) async {
    setState(() {
      isLoading = true;
    });

    try {
      final List<dynamic> data = keyword.trim().isEmpty
          ? await supabase
              .from('wired_members')
              .select()
              .order('subscription_date', ascending: true)
              .order('created_at', ascending: true)
          : await supabase
              .from('wired_members')
              .select()
              .or(
                'phone.ilike.%${keyword.trim()}%,seller.ilike.%${keyword.trim()}%,subscriber.ilike.%${keyword.trim()}%,carrier.ilike.%${keyword.trim()}%,activation_center.ilike.%${keyword.trim()}%,internet_type.ilike.%${keyword.trim()}%',
              )
              .order('subscription_date', ascending: true)
              .order('created_at', ascending: true);

      setState(() {
        members = data.map((e) => Map<String, dynamic>.from(e)).toList();
        if (!canViewAllStores) {
          members = members
              .where(
                (member) => isSameStore(member['store'], widget.currentStore),
              )
              .toList();
        }
        currentPage = 0;
      });
    } catch (e) {
      logUiError('유선회원 조회 실패: $e');
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> addMember({
    required DateTime? subscriptionDate,
    required String carrier,
    required String activationCenter,
    required String seller,
    required String subscriber,
    required String phone,
    required String internetType,
    required int giftCard,
    required int prepaidAmount,
    required int postpaidAmount,
    required int rebate,
    required int extraRebate,
    required String bankName,
    required String accountHolder,
    required String accountNumber,
    required String memo,
  }) async {
    if (subscriber.trim().isEmpty) {
      showMessage('가입자는 필수입니다.');
      return;
    }

    if (phone.trim().isNotEmpty && !isValidPhone(phone)) {
      showMessage('번호 형식은 010-1234-1234 입니다.');
      return;
    }

    final tax = calcTax(rebate: rebate, extra: extraRebate);
    final margin = calcMargin(
      rebate: rebate,
      prepaid: prepaidAmount,
      postpaid: postpaidAmount,
      extra: extraRebate,
      tax: tax,
    );
    final incentive = calcIncentive(margin: margin);

    try {
      await supabase.from('wired_members').insert({
        'customer_name': subscriber,
        'phone': phone.trim(),
        'subscription_date': subscriptionDate?.toIso8601String(),
        'carrier': carrier.trim(),
        'activation_center': activationCenter.trim(),
        'seller': seller.trim(),
        'subscriber': subscriber.trim(),
        'internet_type': internetType.trim(),
        'gift_card': giftCard,
        'prepaid_amount': prepaidAmount,
        'postpaid_amount': postpaidAmount,
        'rebate': rebate,
        'extra_rebate': extraRebate,
        'tax': tax,
        'margin': margin,
        'incentive': incentive,
        'bank_name': bankName.trim(),
        'account_holder': accountHolder.trim(),
        'account_number': accountNumber.trim(),
        'memo': memo.trim(),
        'store': normalizeStoreName(widget.currentStore),
      });

      if (mounted) Navigator.pop(context);
      showMessage('유선회원 등록 완료');
      fetchMembers(keyword: searchController.text);
    } catch (e) {
      logUiError('유선회원 등록 실패: $e');
    }
  }

  Future<void> updateMember({
    required String id,
    required String store,
    required DateTime? subscriptionDate,
    required String carrier,
    required String activationCenter,
    required String seller,
    required String subscriber,
    required String phone,
    required String internetType,
    required int giftCard,
    required int prepaidAmount,
    required int postpaidAmount,
    required int rebate,
    required int extraRebate,
    required String bankName,
    required String accountHolder,
    required String accountNumber,
    required String memo,
  }) async {
    if (subscriber.trim().isEmpty) {
      showMessage('가입자는 필수입니다.');
      return;
    }

    if (phone.trim().isNotEmpty && !isValidPhone(phone)) {
      showMessage('번호 형식은 010-1234-1234 입니다.');
      return;
    }

    final tax = calcTax(rebate: rebate, extra: extraRebate);
    final margin = calcMargin(
      rebate: rebate,
      prepaid: prepaidAmount,
      postpaid: postpaidAmount,
      extra: extraRebate,
      tax: tax,
    );
    final incentive = calcIncentive(margin: margin);

    try {
      await supabase.from('wired_members').update({
        'customer_name': subscriber.trim(),
        'phone': phone.trim(),
        'subscription_date': subscriptionDate?.toIso8601String(),
        'carrier': carrier.trim(),
        'activation_center': activationCenter.trim(),
        'seller': seller.trim(),
        'subscriber': subscriber.trim(),
        'internet_type': internetType.trim(),
        'gift_card': giftCard,
        'prepaid_amount': prepaidAmount,
        'postpaid_amount': postpaidAmount,
        'rebate': rebate,
        'extra_rebate': extraRebate,
        'tax': tax,
        'margin': margin,
        'incentive': incentive,
        'bank_name': bankName.trim(),
        'account_holder': accountHolder.trim(),
        'account_number': accountNumber.trim(),
        'memo': memo.trim(),
        'store': normalizeStoreName(
          store.trim().isEmpty ? widget.currentStore : store,
        ),
      }).eq('id', id);

      if (mounted) Navigator.pop(context);
      showMessage('유선회원 수정 완료');
      fetchMembers(keyword: searchController.text);
    } catch (e) {
      logUiError('유선회원 수정 실패: $e');
    }
  }

  Future<void> deleteMember(String id) async {
    try {
      await supabase.from('wired_members').delete().eq('id', id);
      if (mounted) Navigator.pop(context);
      showMessage('유선회원 삭제 완료');
      fetchMembers(keyword: searchController.text);
    } catch (e) {
      logUiError('유선회원 삭제 실패: $e');
    }
  }

  InputDecoration _wiredInputDecoration(String label) {
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

  Widget _dialogSectionTitle(String title) {
    return SizedBox(
      width: double.infinity,
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF111827),
          fontSize: 13,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _wiredInput({
    required String label,
    required TextEditingController controller,
    double width = 244,
    TextInputType? keyboardType,
    int maxLines = 1,
    ValueChanged<String>? onChanged,
  }) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        onChanged: onChanged,
        style: const TextStyle(
          color: Color(0xFF111827),
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        decoration: _wiredInputDecoration(label),
      ),
    );
  }

  Widget _summaryCard({
    required int rebate,
    required int extra,
    required int prepaid,
    required int postpaid,
    double? width,
  }) {
    final tax = calcTax(rebate: rebate, extra: extra);
    final margin = calcMargin(
      rebate: rebate,
      prepaid: prepaid,
      postpaid: postpaid,
      extra: extra,
      tax: tax,
    );
    final incentive = calcIncentive(margin: margin);

    return Container(
      width: width ?? double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE8E9EF)),
      ),
      child: Row(
        children: [
          Expanded(child: _calcPreviewItem('세금', money(tax))),
          Expanded(child: _calcPreviewItem('마진', money(margin))),
          Expanded(child: _calcPreviewItem('인센', money(incentive))),
        ],
      ),
    );
  }

  Widget _calcPreviewItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF9CA3AF),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF111827),
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  void showCreateDialog() {
    final carrierController = TextEditingController();
    final activationCenterController = TextEditingController();
    final sellerController = TextEditingController();
    final subscriberController = TextEditingController();
    final phoneController = TextEditingController();

    final internetTypeController = TextEditingController();
    final giftCardController = TextEditingController();
    final prepaidAmountController = TextEditingController();
    final postpaidAmountController = TextEditingController();

    final rebateController = TextEditingController();
    final extraRebateController = TextEditingController();

    final bankNameController = TextEditingController();
    final accountHolderController = TextEditingController();
    final accountNumberController = TextEditingController();
    final memoController = TextEditingController();

    DateTime? subscriptionDate;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          final rebate = parseInt(rebateController.text);
          final extra = parseInt(extraRebateController.text);
          final prepaid = parseInt(prepaidAmountController.text);
          final postpaid = parseInt(postpaidAmountController.text);

          return AlertDialog(
            backgroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            title: const Text(
              '유선회원 등록',
              style: TextStyle(
                color: Color(0xFF111827),
                fontWeight: FontWeight.w900,
              ),
            ),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _dialogSectionTitle('기본 정보'),
                    SizedBox(
                      width: 244,
                      child: ElevatedButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: subscriptionDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setDialogState(() {
                              subscriptionDate = picked;
                            });
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF374151),
                          elevation: 0,
                          side: const BorderSide(color: Color(0xFFE8E9EF)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          subscriptionDate == null
                              ? '청약일 선택'
                              : DateFormat('yyyy-MM-dd')
                                  .format(subscriptionDate!),
                        ),
                      ),
                    ),
                    _wiredInput(label: '통신사', controller: carrierController),
                    _wiredInput(
                        label: '개통처', controller: activationCenterController),
                    _wiredInput(label: '판매자', controller: sellerController),
                    _wiredInput(label: '가입자', controller: subscriberController),
                    _wiredInput(
                      label: '번호',
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      onChanged: (value) {
                        final formatted = formatPhone(value);
                        phoneController.value = TextEditingValue(
                          text: formatted,
                          selection:
                              TextSelection.collapsed(offset: formatted.length),
                        );
                      },
                    ),
                    _wiredInput(
                        label: '인터넷유형', controller: internetTypeController),
                    _dialogSectionTitle('정산 정보'),
                    _wiredInput(
                      label: '리베이트',
                      controller: rebateController,
                      keyboardType: TextInputType.number,
                      onChanged: (v) {
                        applyMoneyFormat(rebateController, v);
                        setDialogState(() {});
                      },
                    ),
                    _wiredInput(
                      label: '추가',
                      controller: extraRebateController,
                      keyboardType: TextInputType.number,
                      onChanged: (v) {
                        applyMoneyFormat(extraRebateController, v);
                        setDialogState(() {});
                      },
                    ),
                    _wiredInput(
                      label: '선입금',
                      controller: prepaidAmountController,
                      keyboardType: TextInputType.number,
                      onChanged: (v) {
                        applyMoneyFormat(prepaidAmountController, v);
                        setDialogState(() {});
                      },
                    ),
                    _wiredInput(
                      label: '후입금',
                      controller: postpaidAmountController,
                      keyboardType: TextInputType.number,
                      onChanged: (v) {
                        applyMoneyFormat(postpaidAmountController, v);
                        setDialogState(() {});
                      },
                    ),
                    _wiredInput(
                      label: '상품권',
                      controller: giftCardController,
                      keyboardType: TextInputType.number,
                      onChanged: (v) {
                        applyMoneyFormat(giftCardController, v);
                        setDialogState(() {});
                      },
                    ),
                    _summaryCard(
                      rebate: rebate,
                      extra: extra,
                      prepaid: prepaid,
                      postpaid: postpaid,
                      width: 500,
                    ),
                    _dialogSectionTitle('입금 계좌 및 메모'),
                    _wiredInput(label: '은행명', controller: bankNameController),
                    _wiredInput(
                        label: '이름', controller: accountHolderController),
                    _wiredInput(
                        label: '계좌번호', controller: accountNumberController),
                    _wiredInput(
                      label: '메모',
                      controller: memoController,
                      width: 500,
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF6B7280),
                ),
                child: const Text('취소'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC94C6E),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => addMember(
                  subscriptionDate: subscriptionDate,
                  carrier: carrierController.text.trim(),
                  activationCenter: activationCenterController.text.trim(),
                  seller: sellerController.text.trim(),
                  subscriber: subscriberController.text.trim(),
                  phone: phoneController.text.trim(),
                  internetType: internetTypeController.text.trim(),
                  giftCard: parseInt(giftCardController.text),
                  prepaidAmount: parseInt(prepaidAmountController.text),
                  postpaidAmount: parseInt(postpaidAmountController.text),
                  rebate: parseInt(rebateController.text),
                  extraRebate: parseInt(extraRebateController.text),
                  bankName: bankNameController.text.trim(),
                  accountHolder: accountHolderController.text.trim(),
                  accountNumber: accountNumberController.text.trim(),
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
    final carrierController =
        TextEditingController(text: item['carrier']?.toString() ?? '');
    final activationCenterController = TextEditingController(
        text: item['activation_center']?.toString() ?? '');
    final sellerController =
        TextEditingController(text: item['seller']?.toString() ?? '');
    final subscriberController =
        TextEditingController(text: item['subscriber']?.toString() ?? '');
    final phoneController =
        TextEditingController(text: item['phone']?.toString() ?? '');

    final internetTypeController =
        TextEditingController(text: item['internet_type']?.toString() ?? '');
    final giftCardController = TextEditingController(
        text: formatMoneyInput('${parseInt(item['gift_card'])}'));
    final prepaidAmountController = TextEditingController(
        text: formatMoneyInput('${parseInt(item['prepaid_amount'])}'));
    final postpaidAmountController = TextEditingController(
        text: formatMoneyInput('${parseInt(item['postpaid_amount'])}'));
    final rebateController = TextEditingController(
        text: formatMoneyInput('${parseInt(item['rebate'])}'));
    final extraRebateController = TextEditingController(
        text: formatMoneyInput('${parseInt(item['extra_rebate'])}'));

    final bankNameController =
        TextEditingController(text: item['bank_name']?.toString() ?? '');
    final accountHolderController =
        TextEditingController(text: item['account_holder']?.toString() ?? '');
    final accountNumberController =
        TextEditingController(text: item['account_number']?.toString() ?? '');
    final memoController =
        TextEditingController(text: item['memo']?.toString() ?? '');

    DateTime? subscriptionDate = item['subscription_date'] != null
        ? DateTime.tryParse(item['subscription_date'].toString())
        : null;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          final rebate = parseInt(rebateController.text);
          final extra = parseInt(extraRebateController.text);
          final prepaid = parseInt(prepaidAmountController.text);
          final postpaid = parseInt(postpaidAmountController.text);

          return AlertDialog(
            backgroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            title: const Text(
              '유선회원 수정',
              style: TextStyle(
                color: Color(0xFF111827),
                fontWeight: FontWeight.w900,
              ),
            ),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _dialogSectionTitle('기본 정보'),
                    SizedBox(
                      width: 244,
                      child: ElevatedButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: subscriptionDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setDialogState(() {
                              subscriptionDate = picked;
                            });
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF374151),
                          elevation: 0,
                          side: const BorderSide(color: Color(0xFFE8E9EF)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          subscriptionDate == null
                              ? '청약일 선택'
                              : DateFormat('yyyy-MM-dd')
                                  .format(subscriptionDate!),
                        ),
                      ),
                    ),
                    _wiredInput(label: '통신사', controller: carrierController),
                    _wiredInput(
                        label: '개통처', controller: activationCenterController),
                    _wiredInput(label: '판매자', controller: sellerController),
                    _wiredInput(label: '가입자', controller: subscriberController),
                    _wiredInput(
                      label: '번호',
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      onChanged: (value) {
                        final formatted = formatPhone(value);
                        phoneController.value = TextEditingValue(
                          text: formatted,
                          selection:
                              TextSelection.collapsed(offset: formatted.length),
                        );
                      },
                    ),
                    _wiredInput(
                        label: '인터넷유형', controller: internetTypeController),
                    _dialogSectionTitle('정산 정보'),
                    _wiredInput(
                      label: '리베이트',
                      controller: rebateController,
                      keyboardType: TextInputType.number,
                      onChanged: (v) {
                        applyMoneyFormat(rebateController, v);
                        setDialogState(() {});
                      },
                    ),
                    _wiredInput(
                      label: '추가',
                      controller: extraRebateController,
                      keyboardType: TextInputType.number,
                      onChanged: (v) {
                        applyMoneyFormat(extraRebateController, v);
                        setDialogState(() {});
                      },
                    ),
                    _wiredInput(
                      label: '선입금',
                      controller: prepaidAmountController,
                      keyboardType: TextInputType.number,
                      onChanged: (v) {
                        applyMoneyFormat(prepaidAmountController, v);
                        setDialogState(() {});
                      },
                    ),
                    _wiredInput(
                      label: '후입금',
                      controller: postpaidAmountController,
                      keyboardType: TextInputType.number,
                      onChanged: (v) {
                        applyMoneyFormat(postpaidAmountController, v);
                        setDialogState(() {});
                      },
                    ),
                    _wiredInput(
                      label: '상품권',
                      controller: giftCardController,
                      keyboardType: TextInputType.number,
                      onChanged: (v) {
                        applyMoneyFormat(giftCardController, v);
                        setDialogState(() {});
                      },
                    ),
                    _summaryCard(
                      rebate: rebate,
                      extra: extra,
                      prepaid: prepaid,
                      postpaid: postpaid,
                      width: 500,
                    ),
                    _dialogSectionTitle('입금 계좌 및 메모'),
                    _wiredInput(label: '은행명', controller: bankNameController),
                    _wiredInput(
                        label: '이름', controller: accountHolderController),
                    _wiredInput(
                        label: '계좌번호', controller: accountNumberController),
                    _wiredInput(
                      label: '메모',
                      controller: memoController,
                      width: 500,
                      maxLines: 3,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF6B7280),
                ),
                child: const Text('취소'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC94C6E),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => updateMember(
                  id: item['id'].toString(),
                  store: item['store']?.toString() ?? '',
                  subscriptionDate: subscriptionDate,
                  carrier: carrierController.text.trim(),
                  activationCenter: activationCenterController.text.trim(),
                  seller: sellerController.text.trim(),
                  subscriber: subscriberController.text.trim(),
                  phone: phoneController.text.trim(),
                  internetType: internetTypeController.text.trim(),
                  giftCard: parseInt(giftCardController.text),
                  prepaidAmount: parseInt(prepaidAmountController.text),
                  postpaidAmount: parseInt(postpaidAmountController.text),
                  rebate: parseInt(rebateController.text),
                  extraRebate: parseInt(extraRebateController.text),
                  bankName: bankNameController.text.trim(),
                  accountHolder: accountHolderController.text.trim(),
                  accountNumber: accountNumberController.text.trim(),
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
        title: const Text('유선회원 삭제'),
        content: const Text('정말 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => deleteMember(item['id'].toString()),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, dynamic value) {
    return SizedBox(
      width: 300,
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
              width: 96,
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
                textValue(value),
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

  Widget _detailSection(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE8E9EF)),
      ),
      child: Column(
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
                  color: Color(0xFF111827),
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 18,
            runSpacing: 0,
            children: children,
          ),
        ],
      ),
    );
  }

  void showDetailDialog(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: Text(
          item['subscriber']?.toString() ?? '유선회원 상세',
          style: const TextStyle(
            color: Color(0xFF111827),
            fontWeight: FontWeight.w900,
          ),
        ),
        content: SizedBox(
          width: 760,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detailSection('개통 정보', [
                  _detailRow('청약일', shortDate(item['subscription_date'])),
                  _detailRow('통신사', item['carrier']),
                  _detailRow('개통처', item['activation_center']),
                  _detailRow('판매자', item['seller']),
                  _detailRow('가입자', item['subscriber']),
                  _detailRow('번호', item['phone']),
                ]),
                const SizedBox(height: 12),
                _detailSection('상품 정보', [
                  _detailRow('인터넷유형', item['internet_type']),
                  _detailRow('상품권', money(item['gift_card'])),
                  _detailRow('선입금', money(item['prepaid_amount'])),
                  _detailRow('후입금', money(item['postpaid_amount'])),
                ]),
                const SizedBox(height: 12),
                _detailSection('정산 정보', [
                  _detailRow('리베이트', money(item['rebate'])),
                  _detailRow('추가', money(item['extra_rebate'])),
                  _detailRow('세금', money(item['tax'])),
                  _detailRow('마진', money(item['margin'])),
                  _detailRow('인센', money(item['incentive'])),
                ]),
                const SizedBox(height: 12),
                _detailSection('계좌 / 메모', [
                  _detailRow('은행명', item['bank_name']),
                  _detailRow('이름', item['account_holder']),
                  _detailRow('계좌번호', item['account_number']),
                  _detailRow('메모', item['memo']),
                ]),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
          if (canEdit)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                showEditDialog(item);
              },
              child: const Text('수정'),
            ),
          if (canDelete)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                showDeleteDialog(item);
              },
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

  String textValue(dynamic value) {
    if (value == null) return '-';
    final text = value.toString().trim();
    return text.isEmpty ? '-' : text;
  }

  String _normalizeCarrier(String value) {
    return value.toUpperCase().replaceAll(RegExp(r'[\s_-]'), '');
  }

  bool _matchesCarrierFilter(dynamic value) {
    if (selectedCarrierFilter == '전체') return true;

    final carrier = _normalizeCarrier(textValue(value));
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
    final carrier = _normalizeCarrier(textValue(value));
    if (carrier.contains('SK')) return const Color(0xFF2563EB);
    if (carrier.contains('KT')) return const Color(0xFFEF4444);
    if (carrier.contains('LG')) return const Color(0xFFC94C6E);
    return const Color(0xFF6B7280);
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

  Widget _wiredTable(List<Map<String, dynamic>> visibleMembers) {
    const baseWidths = <double>[
      92,
      170,
      120,
      130,
      140,
      190,
      118,
      118,
      118,
      112,
    ];
    const headers = [
      '통신사',
      '개통처',
      '판매자',
      '가입자',
      '번호',
      '인터넷유형',
      '상품권',
      '선입금',
      '후입금',
      '',
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final baseWidth = baseWidths.reduce((a, b) => a + b);
        final tableWidth =
            constraints.maxWidth > baseWidth ? constraints.maxWidth : baseWidth;
        final extraWidth = tableWidth - baseWidth;
        final widths = [...baseWidths];
        if (extraWidth > 0) {
          widths[1] += extraWidth * 0.18;
          widths[2] += extraWidth * 0.10;
          widths[3] += extraWidth * 0.12;
          widths[4] += extraWidth * 0.12;
          widths[5] += extraWidth * 0.20;
          widths[6] += extraWidth * 0.08;
          widths[7] += extraWidth * 0.08;
          widths[8] += extraWidth * 0.08;
          widths[9] += extraWidth * 0.04;
        }

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
                ...visibleMembers.map((item) {
                  return InkWell(
                    onTap: () => showDetailDialog(item),
                    child: Container(
                      height: 62,
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Color(0xFFF9FAFB)),
                        ),
                      ),
                      child: Row(
                        children: [
                          _tableCell(
                              _tableBadge(
                                textValue(item['carrier']),
                                color: _carrierColor(item['carrier']),
                              ),
                              widths[0]),
                          _tableCell(
                            _tableText(textValue(item['activation_center'])),
                            widths[1],
                          ),
                          _tableCell(
                              _tableText(textValue(item['seller'])), widths[2]),
                          _tableCell(
                            _tableText(textValue(item['subscriber']),
                                strong: true),
                            widths[3],
                          ),
                          _tableCell(
                              _tableText(textValue(item['phone'])), widths[4]),
                          _tableCell(
                            _tableBadge(
                              textValue(item['internet_type']),
                              color: const Color(0xFF3B82F6),
                            ),
                            widths[5],
                          ),
                          _tableCell(
                            _tableText(money(item['gift_card']),
                                color: const Color(0xFFF59E0B), strong: true),
                            widths[6],
                          ),
                          _tableCell(
                            _tableText(money(item['prepaid_amount']),
                                color: const Color(0xFF10B981), strong: true),
                            widths[7],
                          ),
                          _tableCell(
                            _tableText(money(item['postpaid_amount']),
                                color: const Color(0xFFC94C6E), strong: true),
                            widths[8],
                          ),
                          _tableCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _compactIconButton(
                                  tooltip: '상세',
                                  onPressed: () => showDetailDialog(item),
                                  icon: const Icon(Icons.visibility_outlined,
                                      size: 18),
                                ),
                                if (canEdit)
                                  _compactIconButton(
                                    tooltip: '수정',
                                    onPressed: () => showEditDialog(item),
                                    icon: const Icon(Icons.edit_outlined,
                                        size: 18),
                                  ),
                                if (canDelete)
                                  _compactIconButton(
                                    tooltip: '삭제',
                                    onPressed: () => showDeleteDialog(item),
                                    icon: const Icon(Icons.delete_outline,
                                        size: 18),
                                  ),
                              ],
                            ),
                            widths[9],
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
        child: Align(alignment: Alignment.centerLeft, child: child),
      ),
    );
  }

  Widget _tableText(
    String value, {
    bool strong = false,
    Color color = const Color(0xFF374151),
  }) {
    return Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: color,
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredMembers = selectedCarrierFilter == '전체'
        ? members
        : members
            .where((item) => _matchesCarrierFilter(item['carrier']))
            .toList();
    final totalGiftCard = filteredMembers.fold<int>(
      0,
      (sum, item) => sum + parseInt(item['gift_card']),
    );
    final totalPrepaid = filteredMembers.fold<int>(
      0,
      (sum, item) => sum + parseInt(item['prepaid_amount']),
    );
    final totalPostpaid = filteredMembers.fold<int>(
      0,
      (sum, item) => sum + parseInt(item['postpaid_amount']),
    );
    final totalPages = filteredMembers.isEmpty
        ? 1
        : ((filteredMembers.length + pageSize - 1) ~/ pageSize);
    final safePage = currentPage >= totalPages ? totalPages - 1 : currentPage;
    final pageStart = safePage * pageSize;
    var pageEnd = pageStart + pageSize;
    if (pageEnd > filteredMembers.length) pageEnd = filteredMembers.length;
    final visibleMembers = filteredMembers.sublist(pageStart, pageEnd);

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
                  label: '조회 가입자',
                  value: '${filteredMembers.length}건',
                  color: const Color(0xFF6B7280),
                ),
                const SizedBox(width: 14),
                _summaryTile(
                  label: '상품권',
                  value: money(totalGiftCard),
                  color: const Color(0xFFF59E0B),
                ),
                const SizedBox(width: 14),
                _summaryTile(
                  label: '선입금',
                  value: money(totalPrepaid),
                  color: const Color(0xFF10B981),
                ),
                const SizedBox(width: 14),
                _summaryTile(
                  label: '후입금',
                  value: money(totalPostpaid),
                  color: const Color(0xFFC94C6E),
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
                                  SizedBox(
                                    width: 300,
                                    height: 38,
                                    child: TextField(
                                      controller: searchController,
                                      onChanged: (value) =>
                                          fetchMembers(keyword: value),
                                      style: const TextStyle(fontSize: 13),
                                      decoration: InputDecoration(
                                        hintText: '번호, 판매자, 가입자, 통신사, 개통처 검색',
                                        prefixIcon: const Icon(
                                          Icons.search,
                                          size: 17,
                                          color: Color(0xFF9CA3AF),
                                        ),
                                        filled: true,
                                        fillColor: const Color(0xFFF9FAFB),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 12),
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          borderSide: const BorderSide(
                                            color: Color(0xFFE8E9EF),
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          borderSide: const BorderSide(
                                            color: Color(0xFFE8E9EF),
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          borderSide: const BorderSide(
                                            color: Color(0xFFC94C6E),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  _segmentedFilter(
                                    options: const ['전체', 'SKT', 'KT', 'LGU+'],
                                    selected: selectedCarrierFilter,
                                    onSelected: (value) {
                                      setState(() {
                                        selectedCarrierFilter = value;
                                        currentPage = 0;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: showCreateDialog,
                            icon: const Icon(Icons.add, size: 17),
                            label: const Text('가입 등록'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFC94C6E),
                              foregroundColor: Colors.white,
                              elevation: 0,
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: () =>
                                fetchMembers(keyword: searchController.text),
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
                          : members.isEmpty
                              ? const Center(child: Text('등록된 유선회원이 없습니다'))
                              : Scrollbar(
                                  thumbVisibility: true,
                                  child: SingleChildScrollView(
                                    child: _wiredTable(visibleMembers),
                                  ),
                                ),
                    ),
                    _pagination(
                      totalItems: filteredMembers.length,
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
