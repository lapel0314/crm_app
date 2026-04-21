import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crm_app/constants/message_templates.dart';
import 'package:crm_app/services/contact_action_service.dart';
import 'package:crm_app/utils/store_utils.dart';
import 'package:crm_app/widgets/contact_action_buttons.dart';
import 'package:crm_app/widgets/compact_date_range_picker.dart';

final supabase = Supabase.instance.client;

class LeadsPage extends StatefulWidget {
  final String role;
  final String currentStore;
  final String initialSearchQuery;

  const LeadsPage({
    super.key,
    required this.role,
    required this.currentStore,
    this.initialSearchQuery = '',
  });

  @override
  State<LeadsPage> createState() => _LeadsPageState();
}

class _LeadsPageState extends State<LeadsPage> {
  final searchController = TextEditingController();
  final dateSearchController = TextEditingController();

  bool isLoading = true;
  bool showSummaryDashboard = false;
  List<Map<String, dynamic>> leads = [];
  final Set<String> selectedLeadIds = {};
  String selectedTypeFilter = '전체';
  int currentPage = 0;
  static const int pageSize = 20;

  bool get canView => canUseLeads(widget.role);
  bool get canEdit => canUseLeads(widget.role);
  bool get canDelete => canDeleteLead(widget.role);
  bool get canViewAllStores => isPrivilegedRole(widget.role);

  bool _isCompactIosDialogContext(BuildContext context) {
    return !kIsWeb && Platform.isIOS && MediaQuery.of(context).size.width < 900;
  }

  @override
  void initState() {
    super.initState();
    searchController.text = widget.initialSearchQuery;
    if (canView) {
      fetchLeads(keyword: searchController.text, silent: true);
    } else {
      isLoading = false;
    }
  }

  @override
  void didUpdateWidget(covariant LeadsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSearchQuery != widget.initialSearchQuery) {
      searchController.text = widget.initialSearchQuery;
      if (canView) {
        fetchLeads(keyword: searchController.text, silent: true);
      }
    }
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

  DateTime? parseSearchDate(String value) {
    final text = value.trim();
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 6) {
      final year = 2000 + (int.tryParse(digits.substring(0, 2)) ?? -1);
      final month = int.tryParse(digits.substring(2, 4));
      final day = int.tryParse(digits.substring(4, 6));
      if (month != null && day != null) {
        return DateTime.tryParse(
          '${year.toString().padLeft(4, '0')}-'
          '${month.toString().padLeft(2, '0')}-'
          '${day.toString().padLeft(2, '0')}',
        );
      }
    }
    if (digits.length == 8) {
      return DateTime.tryParse(
        '${digits.substring(0, 4)}-${digits.substring(4, 6)}-${digits.substring(6, 8)}',
      );
    }
    return DateTime.tryParse(text.replaceAll('.', '-').replaceAll('/', '-'));
  }

  DateTime? dateOnly(dynamic value) {
    final parsed =
        value is DateTime ? value : parseSearchDate(shortDate(value));
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  DateTimeRange? dateRangeFromText(String text) {
    final matches = RegExp(
      r'\d{6}|\d{8}|\d{2,4}[./-]\d{1,2}[./-]\d{1,2}',
    ).allMatches(text).map((match) => match.group(0)!).toList();
    final parts = matches.length >= 2
        ? matches.take(2).toList()
        : text.split('~').map((part) => part.trim()).toList();
    if (parts.length != 2) return null;

    final start = dateOnly(parts[0]);
    final end = dateOnly(parts[1]);
    if (start == null || end == null) return null;

    return start.isAfter(end)
        ? DateTimeRange(start: end, end: start)
        : DateTimeRange(start: start, end: end);
  }

  String formatDateRange(DateTimeRange range) {
    final formatter = DateFormat('yyyy-MM-dd');
    final start = formatter.format(range.start);
    final end = formatter.format(range.end);
    return start == end ? start : '$start ~ $end';
  }

  bool matchesDateSearch(dynamic value, String filter) {
    if (filter.isEmpty) return true;

    final range = dateRangeFromText(filter);
    if (range == null) {
      final date = dateOnly(value);
      final searchDate = dateOnly(filter);
      if (date != null && searchDate != null) return date == searchDate;
      return shortDate(value).contains(filter);
    }

    final target = dateOnly(value);
    if (target == null) return false;
    return !target.isBefore(range.start) && !target.isAfter(range.end);
  }

  void handleDateSearchChanged(String value) {
    final trimmed = value.trim();
    final compactDigits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    final range = dateRangeFromText(trimmed);
    final shouldNormalizeSingle = !trimmed.contains('~') &&
        (compactDigits.length == 6 || compactDigits.length == 8);

    if (range != null) {
      final formatted = formatDateRange(range);
      dateSearchController.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    } else if (shouldNormalizeSingle) {
      final date = dateOnly(trimmed);
      if (date != null) {
        final formatted = DateFormat('yyyy-MM-dd').format(date);
        dateSearchController.value = TextEditingValue(
          text: formatted,
          selection: TextSelection.collapsed(offset: formatted.length),
        );
      }
    }

    fetchLeads(keyword: searchController.text, silent: true);
  }

  Future<void> pickSearchDate() async {
    final currentText = dateSearchController.text.trim();
    final initialRange = dateRangeFromText(currentText);
    final initialDate = dateOnly(currentText) ?? DateTime.now();
    final picked = await showCompactDateRangePicker(
      context: context,
      initialDateRange:
          initialRange ?? DateTimeRange(start: initialDate, end: initialDate),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      title: '가망고객 기간 선택',
    );
    if (picked == null) return;

    dateSearchController.text = formatDateRange(picked);
    await fetchLeads(keyword: searchController.text, silent: true);
  }

  void clearSearchDate() {
    if (dateSearchController.text.isEmpty) return;
    dateSearchController.clear();
    fetchLeads(keyword: searchController.text, silent: true);
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

  InputDecoration _dialogInputDecoration(String label) {
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
        borderSide: const BorderSide(color: Color(0xFF6B7280), width: 1.4),
      ),
    );
  }

  Widget _leadInput({
    required String label,
    required TextEditingController controller,
    double width = 240,
    int maxLines = 1,
    ValueChanged<String>? onChanged,
  }) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        onChanged: onChanged,
        style: const TextStyle(
          color: Color(0xFF111827),
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        decoration: _dialogInputDecoration(label),
      ),
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
        if (!canViewAllStores) {
          leads = leads
              .where((lead) => isSameStore(lead['store'], widget.currentStore))
              .toList();
        }
        final dateFilter = dateSearchController.text.trim();
        if (dateFilter.isNotEmpty) {
          leads = leads
              .where((lead) => matchesDateSearch(lead['lead_date'], dateFilter))
              .toList();
        }
        selectedLeadIds.removeWhere(
          (id) => !leads.any((lead) => textValue(lead['id']) == id),
        );
        currentPage = 0;
      });
    } catch (e) {
      if (!silent) {
        logUiError('가망고객 조회 실패: $e');
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
        'store': normalizeStoreName(widget.currentStore),
      });

      if (mounted) Navigator.pop(context);
      showMessage('가망고객 등록 완료');
      fetchLeads(keyword: searchController.text, silent: true);
    } catch (e) {
      logUiError('가망고객 등록 실패: $e');
    }
  }

  Future<void> updateLead({
    required String id,
    required String store,
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
        'store': normalizeStoreName(
          store.trim().isEmpty ? widget.currentStore : store,
        ),
      }).eq('id', id);

      if (mounted) Navigator.pop(context);
      showMessage('가망고객 수정 완료');
      fetchLeads(keyword: searchController.text, silent: true);
    } catch (e) {
      logUiError('가망고객 수정 실패: $e');
    }
  }

  Future<void> deleteLead(String id) async {
    try {
      await supabase.from('leads').delete().eq('id', id);
      if (mounted) Navigator.pop(context);
      showMessage('가망고객 삭제 완료');
      fetchLeads(keyword: searchController.text, silent: true);
    } catch (e) {
      logUiError('가망고객 삭제 실패: $e');
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
          final compactIos = _isCompactIosDialogContext(context);
          final dialogWidth =
              compactIos ? MediaQuery.of(context).size.width - 56 : 760.0;

          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            title: const Text(
              '가망고객 등록',
              style: TextStyle(
                color: Color(0xFF111827),
                fontWeight: FontWeight.w900,
              ),
            ),
            content: SizedBox(
              width: dialogWidth,
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: compactIos ? dialogWidth : 240,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFC94C6E),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
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
                    _leadInput(
                      label: '담당자',
                      controller: managerController,
                    ),
                    _leadInput(
                      label: '가입자',
                      controller: subscriberController,
                    ),
                    _leadInput(
                      label: '휴대폰번호',
                      controller: phoneController,
                      onChanged: (value) {
                        final formatted = formatPhone(value);
                        phoneController.value = TextEditingValue(
                          text: formatted,
                          selection:
                              TextSelection.collapsed(offset: formatted.length),
                        );
                      },
                    ),
                    _leadInput(
                      label: '기존통신사',
                      controller: previousCarrierController,
                    ),
                    _leadInput(
                      label: '변경통신사',
                      controller: targetCarrierController,
                    ),
                    _leadInput(
                      label: '메모',
                      controller: memoController,
                      width: compactIos ? dialogWidth : 492,
                      maxLines: 3,
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC94C6E),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
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
          final compactIos = _isCompactIosDialogContext(context);
          final dialogWidth =
              compactIos ? MediaQuery.of(context).size.width - 56 : 760.0;

          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            title: const Text(
              '가망고객 수정',
              style: TextStyle(
                color: Color(0xFF111827),
                fontWeight: FontWeight.w900,
              ),
            ),
            content: SizedBox(
              width: dialogWidth,
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: compactIos ? dialogWidth : 240,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFC94C6E),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
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
                    _leadInput(
                      label: '담당자',
                      controller: managerController,
                    ),
                    _leadInput(
                      label: '가입자',
                      controller: subscriberController,
                    ),
                    _leadInput(
                      label: '휴대폰번호',
                      controller: phoneController,
                      onChanged: (value) {
                        final formatted = formatPhone(value);
                        phoneController.value = TextEditingValue(
                          text: formatted,
                          selection:
                              TextSelection.collapsed(offset: formatted.length),
                        );
                      },
                    ),
                    _leadInput(
                      label: '기존통신사',
                      controller: previousCarrierController,
                    ),
                    _leadInput(
                      label: '변경통신사',
                      controller: targetCarrierController,
                    ),
                    _leadInput(
                      label: '메모',
                      controller: memoController,
                      width: compactIos ? dialogWidth : 492,
                      maxLines: 3,
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC94C6E),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => updateLead(
                  id: item['id'].toString(),
                  store: item['store']?.toString() ?? '',
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

  String textValue(dynamic value) {
    if (value == null) return '-';
    final text = value.toString().trim();
    return text.isEmpty ? '-' : text;
  }

  List<Map<String, dynamic>> _selectedLeads() {
    return leads
        .where((lead) => selectedLeadIds.contains(textValue(lead['id'])))
        .toList();
  }

  Future<void> _sendSmsToSelectedLeads(String message) async {
    final selected = _selectedLeads();
    final result = await const ContactActionService().smsBulk(
      selected.map((lead) => textValue(lead['phone'])).toList(),
      message,
    );
    if (!mounted) return;
    showMessage(result.message ?? '${selected.length}명 문자 앱을 열었습니다.');
  }

  Future<void> showSmsSendDialog() async {
    final selected = _selectedLeads();
    if (selected.isEmpty) {
      showMessage('문자를 보낼 가망고객을 선택해주세요.');
      return;
    }
    final controller = TextEditingController(
      text: buildContactMessage(
        customerName: textValue(selected.first['subscriber']),
      ),
    );
    await showDialog<void>(
      context: context,
      builder: (context) {
        final compactIos = _isCompactIosDialogContext(context);
        return AlertDialog(
        title: Text('문자 발송 (${selected.length}명)'),
        content: SizedBox(
          width: compactIos ? MediaQuery.of(context).size.width - 56 : 420,
          child: TextField(
            controller: controller,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: '문자 내용',
              border: OutlineInputBorder(),
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
              Navigator.pop(context);
              await _sendSmsToSelectedLeads(controller.text);
            },
            child: const Text('문자 앱 열기'),
          ),
        ],
      );
      },
    );
  }

  Future<void> sendKakaoToSelectedLeads() async {
    final selected = _selectedLeads();
    if (selected.isEmpty) {
      showMessage('카카오톡을 보낼 가망고객을 선택해주세요.');
      return;
    }
    final message = buildContactMessage(
      customerName: textValue(selected.first['subscriber']),
    );
    final result = await const ContactActionService().kakao(message);
    if (!mounted) return;
    showMessage(result.message ?? '${selected.length}명 카카오톡 공유 화면을 열었습니다.');
  }

  String _normalizeCarrier(String value) {
    return value.toUpperCase().replaceAll(RegExp(r'[\s_-]'), '');
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
    bool compact = false,
  }) {
    return Container(
      height: compact ? 74 : 88,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 18,
        vertical: compact ? 10 : 14,
      ),
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
            height: compact ? 28 : 34,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          SizedBox(width: compact ? 10 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xFF6B7280),
                    fontSize: compact ? 11 : 12,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
                SizedBox(height: compact ? 4 : 5),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xFF111827),
                    fontSize: compact ? 18 : 21,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateSearchButton() {
    final selectedDate = dateSearchController.text.trim();
    final hasDate = selectedDate.isNotEmpty;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 38,
          height: 38,
          child: IconButton(
            tooltip: hasDate ? '날짜 검색: $selectedDate' : '달력 열기',
            onPressed: pickSearchDate,
            icon: const Icon(Icons.calendar_month_outlined, size: 18),
            style: IconButton.styleFrom(
              backgroundColor:
                  hasDate ? const Color(0xFFFFEEF4) : const Color(0xFFF9FAFB),
              foregroundColor:
                  hasDate ? const Color(0xFFC94C6E) : const Color(0xFF6B7280),
              side: const BorderSide(color: Color(0xFFE8E9EF)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: hasDate ? 210 : 104,
          height: 38,
          child: TextField(
            controller: dateSearchController,
            onChanged: handleDateSearchChanged,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
            decoration: InputDecoration(
              hintText: '260401',
              suffixIcon: hasDate
                  ? IconButton(
                      tooltip: '날짜 검색 지우기',
                      onPressed: clearSearchDate,
                      icon: const Icon(Icons.close_rounded, size: 15),
                      color: const Color(0xFF9CA3AF),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 30,
                        minHeight: 30,
                      ),
                    )
                  : null,
              filled: true,
              fillColor: const Color(0xFFF9FAFB),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10),
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
                borderSide: const BorderSide(
                  color: Color(0xFFC94C6E),
                ),
              ),
            ),
          ),
        ),
      ],
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

  Widget _leadsTable(List<Map<String, dynamic>> visibleLeads) {
    const baseWidths = <double>[48, 110, 120, 130, 150, 130, 130, 300, 226];
    const headers = [
      '',
      '날짜',
      '담당자',
      '가입자',
      '번호',
      '기존통신사',
      '변경통신사',
      '특이사항',
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
          widths[2] += extraWidth * 0.12;
          widths[3] += extraWidth * 0.12;
          widths[4] += extraWidth * 0.12;
          widths[5] += extraWidth * 0.10;
          widths[6] += extraWidth * 0.10;
          widths[7] += extraWidth * 0.34;
          widths[8] += extraWidth * 0.10;
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
                ...visibleLeads.map((item) {
                  final leadId = textValue(item['id']);
                  final selected = selectedLeadIds.contains(leadId);
                  return InkWell(
                    onTap: () => showEditDialog(item),
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
                            Checkbox(
                              value: selected,
                              onChanged: (value) {
                                setState(() {
                                  if (value == true) {
                                    selectedLeadIds.add(leadId);
                                  } else {
                                    selectedLeadIds.remove(leadId);
                                  }
                                });
                              },
                            ),
                            widths[0],
                          ),
                          _tableCell(_tableText(shortDate(item['lead_date'])),
                              widths[1]),
                          _tableCell(_tableText(textValue(item['manager'])),
                              widths[2]),
                          _tableCell(
                            _tableText(textValue(item['subscriber']),
                                strong: true),
                            widths[3],
                          ),
                          _tableCell(
                              _tableText(textValue(item['phone'])), widths[4]),
                          _tableCell(
                            _tableBadge(
                              textValue(item['previous_carrier']),
                              color: _carrierColor(item['previous_carrier']),
                            ),
                            widths[5],
                          ),
                          _tableCell(
                            _tableBadge(
                              textValue(item['target_carrier']),
                              color: _carrierColor(item['target_carrier']),
                            ),
                            widths[6],
                          ),
                          _tableCell(
                              _tableText(textValue(item['memo'])), widths[7]),
                          _tableCell(
                            canEdit
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ContactActionButtons(
                                        customerName:
                                            textValue(item['subscriber']),
                                        phone: textValue(item['phone']),
                                        onMessage: showMessage,
                                        dense: true,
                                      ),
                                      _compactIconButton(
                                        tooltip: '수정',
                                        onPressed: () => showEditDialog(item),
                                        icon: const Icon(Icons.edit_outlined,
                                            size: 18),
                                      ),
                                      if (canDelete)
                                        _compactIconButton(
                                          tooltip: '삭제',
                                          onPressed: () =>
                                              showDeleteDialog(item),
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            size: 18,
                                          ),
                                        ),
                                    ],
                                  )
                                : const SizedBox.shrink(),
                            widths[8],
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
      constraints: const BoxConstraints.tightFor(width: 30, height: 30),
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

    final filteredLeads = selectedTypeFilter == '전체'
        ? leads
        : leads
            .where((item) =>
                textValue(item['target_carrier']).contains(selectedTypeFilter))
            .toList();
    final moveCount = leads
        .where((item) => textValue(item['target_carrier']).contains('이동'))
        .length;
    final changeCount = leads
        .where((item) =>
            textValue(item['target_carrier']).contains('기변') ||
            textValue(item['target_carrier']).contains('기기변경'))
        .length;
    final memoCount =
        leads.where((item) => textValue(item['memo']) != '-').length;
    final totalPages = filteredLeads.isEmpty
        ? 1
        : ((filteredLeads.length + pageSize - 1) ~/ pageSize);
    final safePage = currentPage >= totalPages ? totalPages - 1 : currentPage;
    final pageStart = safePage * pageSize;
    var pageEnd = pageStart + pageSize;
    if (pageEnd > filteredLeads.length) pageEnd = filteredLeads.length;
    final visibleLeads = filteredLeads.sublist(pageStart, pageEnd);
    final mobile = MediaQuery.of(context).size.width < 900;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      body: Padding(
        padding: EdgeInsets.all(mobile ? 14 : 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      showSummaryDashboard = !showSummaryDashboard;
                    });
                  },
                  icon: Icon(
                    showSummaryDashboard
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 16,
                  ),
                  label: Text(showSummaryDashboard ? '요약 숨기기' : '요약 보기'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF6B7280),
                    visualDensity: VisualDensity.compact,
                    minimumSize: const Size(0, 34),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    side: const BorderSide(color: Color(0xFFE8E9EF)),
                  ),
                ),
              ],
            ),
            if (showSummaryDashboard) ...[
              const SizedBox(height: 10),
              mobile
                  ? GridView.count(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.95,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _summaryTile(
                          label: '전체 가망고객',
                          value: '${leads.length}건',
                          color: const Color(0xFF6B7280),
                          compact: true,
                        ),
                        _summaryTile(
                          label: '이동',
                          value: '$moveCount건',
                          color: const Color(0xFF3B82F6),
                          compact: true,
                        ),
                        _summaryTile(
                          label: '기변',
                          value: '$changeCount건',
                          color: const Color(0xFF10B981),
                          compact: true,
                        ),
                        _summaryTile(
                          label: '특이사항',
                          value: '$memoCount건',
                          color: const Color(0xFFF59E0B),
                          compact: true,
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: _summaryTile(
                            label: '전체 가망고객',
                            value: '${leads.length}건',
                            color: const Color(0xFF6B7280),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _summaryTile(
                            label: '이동',
                            value: '$moveCount건',
                            color: const Color(0xFF3B82F6),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _summaryTile(
                            label: '기변',
                            value: '$changeCount건',
                            color: const Color(0xFF10B981),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _summaryTile(
                            label: '특이사항',
                            value: '$memoCount건',
                            color: const Color(0xFFF59E0B),
                          ),
                        ),
                      ],
                    ),
              const SizedBox(height: 20),
            ] else
              const SizedBox(height: 6),
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
                      child: mobile
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      _dateSearchButton(),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 220,
                                        height: 38,
                                        child: TextField(
                                          controller: searchController,
                                          onChanged: (value) => fetchLeads(
                                              keyword: value, silent: true),
                                          style: const TextStyle(fontSize: 13),
                                          decoration: InputDecoration(
                                            hintText:
                                                '이름, 연락처, 담당자, 통신사, 특이사항 검색',
                                            prefixIcon: const Icon(
                                              Icons.search,
                                              size: 17,
                                              color: Color(0xFF9CA3AF),
                                            ),
                                            filled: true,
                                            fillColor:
                                                const Color(0xFFF9FAFB),
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
                                        options: const [
                                          '전체',
                                          '이동',
                                          '기변',
                                          '분류'
                                        ],
                                        selected: selectedTypeFilter,
                                        onSelected: (value) {
                                          setState(() {
                                            selectedTypeFilter = value;
                                            currentPage = 0;
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    SizedBox(
                                      width: 36,
                                      height: 36,
                                      child: OutlinedButton(
                                        onPressed: selectedLeadIds.isEmpty
                                            ? null
                                            : showSmsSendDialog,
                                        style: OutlinedButton.styleFrom(
                                          minimumSize: const Size(36, 36),
                                          padding: EdgeInsets.zero,
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        child: const Icon(
                                          Icons.sms_rounded,
                                          size: 16,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    SizedBox(
                                      width: 36,
                                      height: 36,
                                      child: OutlinedButton(
                                        onPressed: selectedLeadIds.isEmpty
                                            ? null
                                            : sendKakaoToSelectedLeads,
                                        style: OutlinedButton.styleFrom(
                                          minimumSize: const Size(36, 36),
                                          padding: EdgeInsets.zero,
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        child: const Icon(
                                          Icons.chat_bubble_rounded,
                                          size: 16,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: showCreateDialog,
                                        icon: const Icon(Icons.add, size: 14),
                                        label: const Text('등록'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              const Color(0xFFC94C6E),
                                          foregroundColor: Colors.white,
                                          elevation: 0,
                                          minimumSize: const Size(0, 36),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 0,
                                          ),
                                          textStyle:
                                              const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: () => fetchLeads(
                                          keyword: searchController.text,
                                          silent: true,
                                        ),
                                        icon: const Icon(Icons.refresh, size: 14),
                                        label: const Text('새로고침'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.white,
                                          foregroundColor:
                                              const Color(0xFF6B7280),
                                          elevation: 0,
                                          minimumSize: const Size(0, 36),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 0,
                                          ),
                                          textStyle:
                                              const TextStyle(fontSize: 12),
                                          side: const BorderSide(
                                            color: Color(0xFFE8E9EF),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            )
                          : Row(
                              children: [
                                Expanded(
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      children: [
                                        _dateSearchButton(),
                                        const SizedBox(width: 8),
                                        SizedBox(
                                          width: 300,
                                          height: 38,
                                          child: TextField(
                                            controller: searchController,
                                            onChanged: (value) => fetchLeads(
                                                keyword: value, silent: true),
                                            style:
                                                const TextStyle(fontSize: 13),
                                            decoration: InputDecoration(
                                              hintText:
                                                  '이름, 연락처, 담당자, 통신사, 특이사항 검색',
                                              prefixIcon: const Icon(
                                                Icons.search,
                                                size: 17,
                                                color: Color(0xFF9CA3AF),
                                              ),
                                              filled: true,
                                              fillColor:
                                                  const Color(0xFFF9FAFB),
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
                                              enabledBorder:
                                                  OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                borderSide: const BorderSide(
                                                  color: Color(0xFFE8E9EF),
                                                ),
                                              ),
                                              focusedBorder:
                                                  OutlineInputBorder(
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
                                          options: const [
                                            '전체',
                                            '이동',
                                            '기변',
                                            '분류'
                                          ],
                                          selected: selectedTypeFilter,
                                          onSelected: (value) {
                                            setState(() {
                                              selectedTypeFilter = value;
                                              currentPage = 0;
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                OutlinedButton.icon(
                                  onPressed: selectedLeadIds.isEmpty
                                      ? null
                                      : showSmsSendDialog,
                                  icon: const Icon(Icons.sms_rounded, size: 17),
                                  label:
                                      Text('문자 (' + selectedLeadIds.length.toString() + ')'),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  onPressed: selectedLeadIds.isEmpty
                                      ? null
                                      : sendKakaoToSelectedLeads,
                                  icon: const Icon(Icons.chat_bubble_rounded,
                                      size: 17),
                                  label:
                                      Text('카카오 (' + selectedLeadIds.length.toString() + ')'),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton.icon(
                                  onPressed: showCreateDialog,
                                  icon: const Icon(Icons.add, size: 17),
                                  label: const Text('리드 등록'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFC94C6E),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton.icon(
                                  onPressed: () => fetchLeads(
                                    keyword: searchController.text,
                                    silent: true,
                                  ),
                                  icon: const Icon(Icons.refresh, size: 17),
                                  label: const Text('새로고침'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor:
                                        const Color(0xFF6B7280),
                                    elevation: 0,
                                    side: const BorderSide(
                                        color: Color(0xFFE8E9EF)),
                                  ),
                                ),
                              ],
                            ),
                      ),
                    const Divider(height: 1, color: Color(0xFFF3F4F6)),
                    Expanded(
                      child: isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : filteredLeads.isEmpty
                              ? const Center(child: Text('등록된 가망고객이 없습니다'))
                              : Scrollbar(
                                  thumbVisibility: true,
                                  child: SingleChildScrollView(
                                    child: _leadsTable(visibleLeads),
                                  ),
                                ),
                    ),
                    _pagination(
                      totalItems: filteredLeads.length,
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
