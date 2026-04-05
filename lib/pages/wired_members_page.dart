import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class WiredMembersPage extends StatefulWidget {
  final String role;

  const WiredMembersPage({super.key, required this.role});

  @override
  State<WiredMembersPage> createState() => _WiredMembersPageState();
}

class _WiredMembersPageState extends State<WiredMembersPage> {
  final searchController = TextEditingController();
  final NumberFormat moneyFormat = NumberFormat('#,###');

  bool isLoading = false;
  List<Map<String, dynamic>> members = [];

  bool get canEdit => ['대표', '개발자', '사장', '점장', '사원'].contains(widget.role);
  bool get canDelete => ['대표', '개발자', '사장', '점장'].contains(widget.role);

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
    return ((rebate - extra) * 0.133).round();
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
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
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
      });
    } catch (e) {
      showMessage('유선회원 조회 실패: $e');
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
      });

      if (mounted) Navigator.pop(context);
      showMessage('유선회원 등록 완료');
      fetchMembers(keyword: searchController.text);
    } catch (e) {
      showMessage('유선회원 등록 실패: $e');
    }
  }

  Future<void> updateMember({
    required String id,
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
      }).eq('id', id);

      if (mounted) Navigator.pop(context);
      showMessage('유선회원 수정 완료');
      fetchMembers(keyword: searchController.text);
    } catch (e) {
      showMessage('유선회원 수정 실패: $e');
    }
  }

  Future<void> deleteMember(String id) async {
    try {
      await supabase.from('wired_members').delete().eq('id', id);
      if (mounted) Navigator.pop(context);
      showMessage('유선회원 삭제 완료');
      fetchMembers(keyword: searchController.text);
    } catch (e) {
      showMessage('유선회원 삭제 실패: $e');
    }
  }

  Widget _summaryCard({
    required int rebate,
    required int extra,
    required int prepaid,
    required int postpaid,
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
          Text('세금: ${money(tax)}',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('마진: ${money(margin)}',
              style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('인센: ${money(incentive)}',
              style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
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
            title: const Text('유선회원 등록'),
            content: SizedBox(
              width: 620,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
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
                        child: Text(
                          subscriptionDate == null
                              ? '청약일 선택'
                              : DateFormat('yyyy-MM-dd')
                                  .format(subscriptionDate!),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: carrierController,
                      decoration: const InputDecoration(labelText: '통신사'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: activationCenterController,
                      decoration: const InputDecoration(labelText: '개통처'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: sellerController,
                      decoration: const InputDecoration(labelText: '판매자'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: subscriberController,
                      decoration: const InputDecoration(labelText: '가입자'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneController,
                      decoration: const InputDecoration(labelText: '번호'),
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
                      controller: internetTypeController,
                      decoration: const InputDecoration(labelText: '인터넷유형'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: giftCardController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '상품권'),
                      onChanged: (v) {
                        applyMoneyFormat(giftCardController, v);
                        setDialogState(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: prepaidAmountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '선입금'),
                      onChanged: (v) {
                        applyMoneyFormat(prepaidAmountController, v);
                        setDialogState(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: postpaidAmountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '후입금'),
                      onChanged: (v) {
                        applyMoneyFormat(postpaidAmountController, v);
                        setDialogState(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: rebateController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '리베이트'),
                      onChanged: (v) {
                        applyMoneyFormat(rebateController, v);
                        setDialogState(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: extraRebateController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '추가'),
                      onChanged: (v) {
                        applyMoneyFormat(extraRebateController, v);
                        setDialogState(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                    _summaryCard(
                      rebate: rebate,
                      extra: extra,
                      prepaid: prepaid,
                      postpaid: postpaid,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: bankNameController,
                      decoration: const InputDecoration(labelText: '은행명'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: accountHolderController,
                      decoration: const InputDecoration(labelText: '이름'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: accountNumberController,
                      decoration: const InputDecoration(labelText: '계좌번호'),
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
            title: const Text('유선회원 수정'),
            content: SizedBox(
              width: 620,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
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
                        child: Text(
                          subscriptionDate == null
                              ? '청약일 선택'
                              : DateFormat('yyyy-MM-dd')
                                  .format(subscriptionDate!),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: carrierController,
                      decoration: const InputDecoration(labelText: '통신사'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: activationCenterController,
                      decoration: const InputDecoration(labelText: '개통처'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: sellerController,
                      decoration: const InputDecoration(labelText: '판매자'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: subscriberController,
                      decoration: const InputDecoration(labelText: '가입자'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneController,
                      decoration: const InputDecoration(labelText: '번호'),
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
                      controller: internetTypeController,
                      decoration: const InputDecoration(labelText: '인터넷유형'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: giftCardController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '상품권'),
                      onChanged: (v) {
                        applyMoneyFormat(giftCardController, v);
                        setDialogState(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: prepaidAmountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '선입금'),
                      onChanged: (v) {
                        applyMoneyFormat(prepaidAmountController, v);
                        setDialogState(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: postpaidAmountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '후입금'),
                      onChanged: (v) {
                        applyMoneyFormat(postpaidAmountController, v);
                        setDialogState(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: rebateController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '리베이트'),
                      onChanged: (v) {
                        applyMoneyFormat(rebateController, v);
                        setDialogState(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: extraRebateController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '추가'),
                      onChanged: (v) {
                        applyMoneyFormat(extraRebateController, v);
                        setDialogState(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                    _summaryCard(
                      rebate: rebate,
                      extra: extra,
                      prepaid: prepaid,
                      postpaid: postpaid,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: bankNameController,
                      decoration: const InputDecoration(labelText: '은행명'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: accountHolderController,
                      decoration: const InputDecoration(labelText: '이름'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: accountNumberController,
                      decoration: const InputDecoration(labelText: '계좌번호'),
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
                onPressed: () => updateMember(
                  id: item['id'].toString(),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text('$label : ${value ?? '-'}'),
    );
  }

  void showDetailDialog(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(item['subscriber']?.toString() ?? '유선회원 상세'),
        content: SizedBox(
          width: 680,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('개통정보',
                    style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                _detailRow('청약일', shortDate(item['subscription_date'])),
                _detailRow('통신사', item['carrier']),
                _detailRow('개통처', item['activation_center']),
                _detailRow('판매자', item['seller']),
                _detailRow('가입자', item['subscriber']),
                _detailRow('번호', item['phone']),
                const SizedBox(height: 14),
                const Text('인터넷유형',
                    style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                _detailRow('인터넷유형', item['internet_type']),
                _detailRow('상품권', money(item['gift_card'])),
                _detailRow('선입금', money(item['prepaid_amount'])),
                _detailRow('후입금', money(item['postpaid_amount'])),
                const SizedBox(height: 14),
                const Text('리베이트',
                    style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                _detailRow('리베이트', money(item['rebate'])),
                _detailRow('추가', money(item['extra_rebate'])),
                _detailRow('세금', money(item['tax'])),
                _detailRow('마진', money(item['margin'])),
                const SizedBox(height: 14),
                const Text('판매수수료',
                    style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                _detailRow('인센', money(item['incentive'])),
                const SizedBox(height: 14),
                const Text('페이백계좌정보',
                    style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                _detailRow('은행명', item['bank_name']),
                _detailRow('이름', item['account_holder']),
                _detailRow('계좌번호', item['account_number']),
                _detailRow('메모', item['memo']),
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

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('유선회원DB'),
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
                      hintText: '번호, 판매자, 가입자, 통신사, 개통처 검색',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) => fetchMembers(keyword: value),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: showCreateDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('유선회원 등록'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () => fetchMembers(keyword: searchController.text),
                  icon: const Icon(Icons.refresh),
                  label: const Text('새로고침'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : members.isEmpty
                      ? const Center(child: Text('등록된 유선회원이 없습니다'))
                      : ListView.builder(
                          itemCount: members.length,
                          itemBuilder: (context, index) {
                            final item = members[index];
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              child: ListTile(
                                onTap: () => showDetailDialog(item),
                                title: Text(
                                  '${shortDate(item['subscription_date'])} | ${item['subscriber'] ?? '-'}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800),
                                ),
                                subtitle: Text(
                                  '${item['carrier'] ?? '-'} | ${item['phone'] ?? '-'} | ${money(item['incentive'])}',
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: '상세',
                                      onPressed: () => showDetailDialog(item),
                                      icon:
                                          const Icon(Icons.visibility_outlined),
                                    ),
                                    if (canEdit)
                                      IconButton(
                                        tooltip: '수정',
                                        onPressed: () => showEditDialog(item),
                                        icon: const Icon(Icons.edit_outlined),
                                      ),
                                    if (canDelete)
                                      IconButton(
                                        tooltip: '삭제',
                                        onPressed: () => showDeleteDialog(item),
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
      ),
    );
  }
}
