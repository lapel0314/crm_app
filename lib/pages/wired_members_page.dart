import 'dart:io';

import 'package:excel/excel.dart' as xls;
import 'package:file_selector/file_selector.dart';
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

class WiredMembersPage extends StatefulWidget {
  final String role;
  final String currentStore;
  final String initialSearchQuery;

  const WiredMembersPage({
    super.key,
    required this.role,
    required this.currentStore,
    this.initialSearchQuery = '',
  });

  @override
  State<WiredMembersPage> createState() => _WiredMembersPageState();
}

class _WiredMembersPageState extends State<WiredMembersPage> {
  final searchController = TextEditingController();
  final dateSearchController = TextEditingController();
  final NumberFormat moneyFormat = NumberFormat('#,###');

  bool isLoading = false;
  bool showSummaryDashboard = false;
  List<Map<String, dynamic>> members = [];
  final Set<String> selectedMemberIds = {};
  String selectedCarrierFilter = '전체';
  int currentPage = 0;
  static const int pageSize = 20;

  bool get canEdit => canUseWiredMembers(widget.role);
  bool get canDelete => canDeleteWiredMember(widget.role);
  bool get canViewAllStores => isPrivilegedRole(widget.role);
  bool get canExportExcel => isPrivilegedRole(widget.role);

  bool _isCompactIosDialogContext(BuildContext context) {
    return !kIsWeb && Platform.isIOS && MediaQuery.of(context).size.width < 900;
  }

  @override
  void initState() {
    super.initState();
    searchController.text = widget.initialSearchQuery;
    fetchMembers(keyword: searchController.text);
  }

  @override
  void didUpdateWidget(covariant WiredMembersPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSearchQuery != widget.initialSearchQuery) {
      searchController.text = widget.initialSearchQuery;
      fetchMembers(keyword: searchController.text);
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

    fetchMembers(keyword: searchController.text);
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
      title: '유선회원 청약일 기간 선택',
    );
    if (picked == null) return;

    dateSearchController.text = formatDateRange(picked);
    await fetchMembers(keyword: searchController.text);
  }

  void clearSearchDate() {
    if (dateSearchController.text.isEmpty) return;
    dateSearchController.clear();
    fetchMembers(keyword: searchController.text);
  }

  Future<void> exportMembersExcel(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) {
      showMessage('내보낼 유선고객 데이터가 없습니다.');
      return;
    }
    if (kIsWeb) {
      showMessage('웹에서는 아직 엑셀 저장을 지원하지 않습니다.');
      return;
    }
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
      showMessage('엑셀 저장은 PC에서만 지원됩니다.');
      return;
    }

    const typeGroup = XTypeGroup(label: 'Excel', extensions: ['xlsx']);
    final suggestedName = _buildMembersExcelFileName(rows);
    final saveLocation = await getSaveLocation(
      acceptedTypeGroups: const [typeGroup],
      suggestedName: suggestedName,
      confirmButtonText: '저장',
    );
    if (saveLocation == null) return;

    final excel = xls.Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet();
    final sheetName = '유선고객';
    if (defaultSheet != null && defaultSheet != sheetName) {
      excel.rename(defaultSheet, sheetName);
    }
    final sheet = excel[sheetName];

    excel.appendRow(sheetName, [
      xls.TextCellValue('청약일'),
      xls.TextCellValue('매장'),
      xls.TextCellValue('판매점'),
      xls.TextCellValue('개통처'),
      xls.TextCellValue('가입자'),
      xls.TextCellValue('휴대폰번호'),
      xls.TextCellValue('통신사'),
      xls.TextCellValue('인터넷유형'),
      xls.TextCellValue('상품권'),
      xls.TextCellValue('리베이트'),
      xls.TextCellValue('추가리베이트'),
      xls.TextCellValue('선입금'),
      xls.TextCellValue('후입금'),
      xls.TextCellValue('마진'),
      xls.TextCellValue('은행'),
      xls.TextCellValue('예금주'),
      xls.TextCellValue('계좌번호'),
      xls.TextCellValue('메모'),
    ]);

    for (final member in rows) {
      final rebate = parseInt(member['rebate']);
      final prepaid = parseInt(member['prepaid_amount']);
      final postpaid = parseInt(member['postpaid_amount']);
      final margin = calcMargin(
        rebate: rebate,
        prepaid: prepaid,
        postpaid: postpaid,
        extra: parseInt(member['extra_rebate']),
        tax: 0,
      );

      excel.appendRow(sheetName, [
        xls.TextCellValue(shortDate(member['subscription_date'])),
        xls.TextCellValue(member['store']?.toString() ?? ''),
        xls.TextCellValue(member['seller']?.toString() ?? ''),
        xls.TextCellValue(member['activation_center']?.toString() ?? ''),
        xls.TextCellValue(member['subscriber']?.toString() ?? ''),
        xls.TextCellValue(member['phone']?.toString() ?? ''),
        xls.TextCellValue(member['carrier']?.toString() ?? ''),
        xls.TextCellValue(member['internet_type']?.toString() ?? ''),
        xls.IntCellValue(parseInt(member['gift_card'])),
        xls.IntCellValue(rebate),
        xls.IntCellValue(parseInt(member['extra_rebate'])),
        xls.IntCellValue(prepaid),
        xls.IntCellValue(postpaid),
        xls.IntCellValue(margin),
        xls.TextCellValue(member['bank_name']?.toString() ?? ''),
        xls.TextCellValue(member['account_holder']?.toString() ?? ''),
        xls.TextCellValue(member['account_number']?.toString() ?? ''),
        xls.TextCellValue(member['memo']?.toString() ?? ''),
      ]);
    }

    _styleMembersExcelSheet(sheet, rows);

    final bytes = excel.save(fileName: suggestedName);
    if (bytes == null || bytes.isEmpty) {
      showMessage('엑셀 파일 생성에 실패했습니다.');
      return;
    }

    await File(saveLocation.path).writeAsBytes(bytes, flush: true);
    if (!mounted) return;
    showMessage('유선고객 엑셀 저장이 완료되었습니다.');
  }

  String _buildMembersExcelFileName(List<Map<String, dynamic>> rows) {
    final storeLabel = _buildExcelStoreLabel(
      rows.map((row) => row['store']),
      fallback: '전체매장',
    );
    final dateLabel = _buildExcelDateLabel(
      selectedText: dateSearchController.text,
      dates: rows.map((row) => shortDate(row['subscription_date'])),
      fallback: '전체기간',
    );
    return '유선고객_${_sanitizeExcelFilePart(storeLabel)}_${_sanitizeExcelFilePart(dateLabel)}.xlsx';
  }

  void _styleMembersExcelSheet(
    xls.Sheet sheet,
    List<Map<String, dynamic>> rows,
  ) {
    final headerStyle = xls.CellStyle(
      bold: true,
      fontColorHex: xls.ExcelColor.white,
      backgroundColorHex: xls.ExcelColor.blueGrey600,
      horizontalAlign: xls.HorizontalAlign.Center,
      verticalAlign: xls.VerticalAlign.Center,
      leftBorder: xls.Border(borderStyle: xls.BorderStyle.Thin),
      rightBorder: xls.Border(borderStyle: xls.BorderStyle.Thin),
      topBorder: xls.Border(borderStyle: xls.BorderStyle.Thin),
      bottomBorder: xls.Border(borderStyle: xls.BorderStyle.Thin),
    );
    final moneyStyle = xls.CellStyle(
      numberFormat: xls.NumFormat.standard_3,
      horizontalAlign: xls.HorizontalAlign.Right,
      verticalAlign: xls.VerticalAlign.Center,
    );
    final rebateStyle = xls.CellStyle(
      bold: true,
      numberFormat: xls.NumFormat.standard_3,
      fontColorHex: xls.ExcelColor.blue800,
      backgroundColorHex: xls.ExcelColor.blue50,
      horizontalAlign: xls.HorizontalAlign.Right,
      verticalAlign: xls.VerticalAlign.Center,
    );
    final marginPositiveStyle = xls.CellStyle(
      bold: true,
      numberFormat: xls.NumFormat.standard_3,
      fontColorHex: xls.ExcelColor.green800,
      backgroundColorHex: xls.ExcelColor.green50,
      horizontalAlign: xls.HorizontalAlign.Right,
      verticalAlign: xls.VerticalAlign.Center,
    );
    final marginNegativeStyle = xls.CellStyle(
      bold: true,
      numberFormat: xls.NumFormat.standard_3,
      fontColorHex: xls.ExcelColor.red800,
      backgroundColorHex: xls.ExcelColor.red50,
      horizontalAlign: xls.HorizontalAlign.Right,
      verticalAlign: xls.VerticalAlign.Center,
    );
    final marginZeroStyle = xls.CellStyle(
      bold: true,
      numberFormat: xls.NumFormat.standard_3,
      fontColorHex: xls.ExcelColor.orange800,
      backgroundColorHex: xls.ExcelColor.orange50,
      horizontalAlign: xls.HorizontalAlign.Right,
      verticalAlign: xls.VerticalAlign.Center,
    );

    const widths = <double>[
      12,
      14,
      14,
      14,
      12,
      16,
      10,
      14,
      12,
      14,
      14,
      14,
      14,
      12,
      12,
      18,
      28,
    ];
    for (var i = 0; i < widths.length; i++) {
      sheet.setColumnWidth(i, widths[i]);
      sheet
          .cell(xls.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
          .cellStyle = headerStyle;
    }

    const moneyColumns = <int>[8, 9, 10, 11, 12];
    for (var rowIndex = 1; rowIndex <= rows.length; rowIndex++) {
      for (final columnIndex in moneyColumns) {
        sheet
            .cell(
              xls.CellIndex.indexByColumnRow(
                columnIndex: columnIndex,
                rowIndex: rowIndex,
              ),
            )
            .cellStyle = moneyStyle;
      }

      sheet
          .cell(
            xls.CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: rowIndex),
          )
          .cellStyle = rebateStyle;

      final row = rows[rowIndex - 1];
      final margin = calcMargin(
        rebate: parseInt(row['rebate']),
        prepaid: parseInt(row['prepaid_amount']),
        postpaid: parseInt(row['postpaid_amount']),
        extra: parseInt(row['extra_rebate']),
        tax: 0,
      );

      sheet
          .cell(
            xls.CellIndex.indexByColumnRow(columnIndex: 12, rowIndex: rowIndex),
          )
          .cellStyle = margin > 0
          ? marginPositiveStyle
          : margin < 0
              ? marginNegativeStyle
              : marginZeroStyle;
    }
  }

  String _buildExcelStoreLabel(
    Iterable<dynamic> stores, {
    required String fallback,
  }) {
    final uniqueStores = stores
        .map((store) => store?.toString().trim() ?? '')
        .where((store) => store.isNotEmpty && store != '-')
        .toSet()
        .toList()
      ..sort();

    if (uniqueStores.isEmpty) return fallback;
    if (uniqueStores.length == 1) return uniqueStores.first;
    return '${uniqueStores.first} 외${uniqueStores.length - 1}개';
  }

  String _buildExcelDateLabel({
    required String selectedText,
    required Iterable<String> dates,
    required String fallback,
  }) {
    final normalizedSelected = selectedText.trim().replaceAll(' ~ ', '~');
    if (normalizedSelected.isNotEmpty) {
      return normalizedSelected;
    }

    final uniqueDates = dates
        .map((date) => date.trim())
        .where((date) => date.isNotEmpty && date != '-')
        .toSet()
        .toList()
      ..sort();

    if (uniqueDates.isEmpty) return fallback;
    if (uniqueDates.length == 1) return uniqueDates.first;
    return '${uniqueDates.first} 외${uniqueDates.length - 1}일';
  }

  String _sanitizeExcelFilePart(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty ? '미지정' : cleaned;
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
    return 0;
  }

  int calcMargin({
    required int rebate,
    required int prepaid,
    required int postpaid,
    required int extra,
    required int tax,
  }) {
    return rebate - prepaid - postpaid;
  }

  int calcIncentive({
    required int margin,
  }) {
    return 0;
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

  Map<String, dynamic> withCalculatedSettlement(Map<String, dynamic> member) {
    final rebate = parseInt(member['rebate']);
    final extra = parseInt(member['extra_rebate']);
    final prepaid = parseInt(member['prepaid_amount']);
    final postpaid = parseInt(member['postpaid_amount']);
    final tax = calcTax(rebate: rebate, extra: extra);
    final margin = calcMargin(
      rebate: rebate,
      prepaid: prepaid,
      postpaid: postpaid,
      extra: extra,
      tax: tax,
    );

    return {
      ...member,
      'tax': tax,
      'margin': margin,
      'incentive': calcIncentive(margin: margin),
    };
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
        members = data
            .map((e) => withCalculatedSettlement(Map<String, dynamic>.from(e)))
            .toList();
        if (!canViewAllStores) {
          members = members
              .where(
                (member) => isSameStore(member['store'], widget.currentStore),
              )
              .toList();
        }
        final dateFilter = dateSearchController.text.trim();
        if (dateFilter.isNotEmpty) {
          members = members
              .where((member) =>
                  matchesDateSearch(member['subscription_date'], dateFilter))
              .toList();
        }
        selectedMemberIds.removeWhere(
          (id) => !members.any((member) => textValue(member['id']) == id),
        );
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
        'tax': 0,
        'margin': margin,
        'incentive': 0,
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
        'tax': 0,
        'margin': margin,
        'incentive': 0,
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
    final totalAdvance = prepaid + postpaid;

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
          Expanded(child: _calcPreviewItem('리베이트', money(rebate))),
          Expanded(child: _calcPreviewItem('대납', money(totalAdvance))),
          Expanded(child: _calcPreviewItem('마진', money(margin))),
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
          final compactIos = _isCompactIosDialogContext(context);
          final dialogWidth =
              compactIos ? MediaQuery.of(context).size.width - 56 : 560.0;
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
              width: dialogWidth,
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _dialogSectionTitle('기본 정보'),
                    SizedBox(
                      width: compactIos ? dialogWidth : 244,
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
                      width: compactIos ? dialogWidth : 500,
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
                      width: compactIos ? dialogWidth : 500,
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
          final compactIos = _isCompactIosDialogContext(context);
          final dialogWidth =
              compactIos ? MediaQuery.of(context).size.width - 56 : 560.0;
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
              width: dialogWidth,
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _dialogSectionTitle('기본 정보'),
                    SizedBox(
                      width: compactIos ? dialogWidth : 244,
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
                      width: compactIos ? dialogWidth : 500,
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
                      width: compactIos ? dialogWidth : 500,
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
      builder: (context) {
        final compactIos = _isCompactIosDialogContext(context);
        final dialogWidth =
            compactIos ? MediaQuery.of(context).size.width - 56 : 760.0;
        return AlertDialog(
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
            width: dialogWidth,
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
                    _detailRow('마진', money(item['margin'])),
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
        );
      },
    );
  }

  String textValue(dynamic value) {
    if (value == null) return '-';
    final text = value.toString().trim();
    return text.isEmpty ? '-' : text;
  }

  List<Map<String, dynamic>> _selectedMembers([
    List<Map<String, dynamic>>? source,
  ]) {
    final rows = source ??
        (selectedCarrierFilter == '전체'
            ? members
            : members
                .where((member) => _matchesCarrierFilter(member['carrier']))
                .toList());
    return rows
        .where((member) => selectedMemberIds.contains(textValue(member['id'])))
        .toList();
  }

  bool _areAllMembersSelected(List<Map<String, dynamic>> rows) {
    return rows.isNotEmpty &&
        rows.every(
          (member) => selectedMemberIds.contains(textValue(member['id'])),
        );
  }

  void _toggleSelectAllMembers(List<Map<String, dynamic>> rows, bool select) {
    setState(() {
      for (final member in rows) {
        final memberId = textValue(member['id']);
        if (select) {
          selectedMemberIds.add(memberId);
        } else {
          selectedMemberIds.remove(memberId);
        }
      }
    });
  }

  Future<void> _sendSmsToSelectedMembers(String message) async {
    final selected = _selectedMembers();
    final result = await const ContactActionService().smsBulk(
      selected.map((member) => textValue(member['phone'])).toList(),
      message,
    );
    if (!mounted) return;
    showMessage(result.message ?? '${selected.length}명 문자 앱을 열었습니다.');
  }

  Future<void> showSmsSendDialog() async {
    final selected = _selectedMembers();
    if (selected.isEmpty) {
      showMessage('문자를 보낼 유선회원을 선택해주세요.');
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
                await _sendSmsToSelectedMembers(controller.text);
              },
              child: const Text('문자 앱 열기'),
            ),
          ],
        );
      },
    );
  }

  Future<void> sendKakaoToSelectedMembers() async {
    final selected = _selectedMembers();
    if (selected.isEmpty) {
      showMessage('카카오톡을 보낼 유선회원을 선택해주세요.');
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
                    color: Color(0xFF9CA3AF),
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
                    color: Color(0xFF111827),
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

  Widget _wiredTable(
    List<Map<String, dynamic>> visibleMembers, {
    required bool allSelected,
    required bool hasSelectionTarget,
    required int selectionTargetCount,
    required bool partiallySelected,
  }) {
    const baseWidths = <double>[
      118,
      92,
      170,
      120,
      130,
      140,
      190,
      118,
      118,
      118,
      246,
    ];
    const headers = [
      '선택',
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
          widths[2] += extraWidth * 0.18;
          widths[3] += extraWidth * 0.10;
          widths[4] += extraWidth * 0.12;
          widths[5] += extraWidth * 0.12;
          widths[6] += extraWidth * 0.18;
          widths[7] += extraWidth * 0.07;
          widths[8] += extraWidth * 0.07;
          widths[9] += extraWidth * 0.07;
          widths[10] += extraWidth * 0.09;
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
                        if (i == 0)
                          _selectionHeaderCell(
                            width: widths[i],
                            allSelected: allSelected,
                            hasSelectionTarget: hasSelectionTarget,
                            partiallySelected: partiallySelected,
                            selectionTargetCount: selectionTargetCount,
                            onChanged: (value) => _toggleSelectAllMembers(
                              selectedCarrierFilter == '전체'
                                  ? members
                                  : members
                                      .where((item) => _matchesCarrierFilter(
                                          item['carrier']))
                                      .toList(),
                              value ?? false,
                            ),
                          )
                        else
                          _headerCell(headers[i], widths[i]),
                    ],
                  ),
                ),
                ...visibleMembers.map((item) {
                  final memberId = textValue(item['id']);
                  final selected = selectedMemberIds.contains(memberId);
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
                            Checkbox(
                              value: selected,
                              onChanged: (value) {
                                setState(() {
                                  if (value == true) {
                                    selectedMemberIds.add(memberId);
                                  } else {
                                    selectedMemberIds.remove(memberId);
                                  }
                                });
                              },
                            ),
                            widths[0],
                          ),
                          _tableCell(
                              _tableBadge(
                                textValue(item['carrier']),
                                color: _carrierColor(item['carrier']),
                              ),
                              widths[1]),
                          _tableCell(
                            _tableText(textValue(item['activation_center'])),
                            widths[2],
                          ),
                          _tableCell(
                              _tableText(textValue(item['seller'])), widths[3]),
                          _tableCell(
                            _tableText(textValue(item['subscriber']),
                                strong: true),
                            widths[4],
                          ),
                          _tableCell(
                              _tableText(textValue(item['phone'])), widths[5]),
                          _tableCell(
                            _tableBadge(
                              textValue(item['internet_type']),
                              color: const Color(0xFF3B82F6),
                            ),
                            widths[6],
                          ),
                          _tableCell(
                            _tableText(money(item['gift_card']),
                                color: const Color(0xFFF59E0B), strong: true),
                            widths[7],
                          ),
                          _tableCell(
                            _tableText(money(item['prepaid_amount']),
                                color: const Color(0xFF10B981), strong: true),
                            widths[8],
                          ),
                          _tableCell(
                            _tableText(money(item['postpaid_amount']),
                                color: const Color(0xFFC94C6E), strong: true),
                            widths[9],
                          ),
                          _tableCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ContactActionButtons(
                                  customerName: textValue(item['subscriber']),
                                  phone: textValue(item['phone']),
                                  onMessage: showMessage,
                                  dense: true,
                                ),
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
                            widths[10],
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

  Widget _selectionHeaderCell({
    required double width,
    required bool allSelected,
    required bool hasSelectionTarget,
    required bool partiallySelected,
    required int selectionTargetCount,
    required ValueChanged<bool?> onChanged,
  }) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: [
            Checkbox(
              value: hasSelectionTarget
                  ? (allSelected ? true : (partiallySelected ? null : false))
                  : false,
              tristate: true,
              onChanged: hasSelectionTarget ? onChanged : null,
              visualDensity: VisualDensity.compact,
            ),
            Expanded(
              child: Text(
                '모두선택\n($selectionTargetCount명)',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
            ),
          ],
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
    final filteredMembers = selectedCarrierFilter == '전체'
        ? members
        : members
            .where((item) => _matchesCarrierFilter(item['carrier']))
            .toList();
    final selectedMembers = _selectedMembers(filteredMembers);
    final selectedMemberCount = selectedMembers.length;
    final allMembersSelected = _areAllMembersSelected(filteredMembers);
    final partiallySelectedMembers =
        !allMembersSelected && selectedMemberCount > 0;
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
    final mobile = MediaQuery.of(context).size.width < 900;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      body: Padding(
        padding: EdgeInsets.all(mobile ? 14 : 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                          label: '조회 가입자',
                          value: '${filteredMembers.length}건',
                          color: const Color(0xFF6B7280),
                          compact: true,
                        ),
                        _summaryTile(
                          label: '상품권',
                          value: money(totalGiftCard),
                          color: const Color(0xFFF59E0B),
                          compact: true,
                        ),
                        _summaryTile(
                          label: '선입금',
                          value: money(totalPrepaid),
                          color: const Color(0xFF10B981),
                          compact: true,
                        ),
                        _summaryTile(
                          label: '후입금',
                          value: money(totalPostpaid),
                          color: const Color(0xFFC94C6E),
                          compact: true,
                        ),
                      ],
                    )
                  : Row(
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
                          label:
                              Text(showSummaryDashboard ? '요약 숨기기' : '요약 보기'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF6B7280),
                            visualDensity: VisualDensity.compact,
                            minimumSize: const Size(0, 34),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 0),
                            side: const BorderSide(color: Color(0xFFE8E9EF)),
                          ),
                        ),
                      ],
                    ),
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
                                          onChanged: (value) =>
                                              fetchMembers(keyword: value),
                                          style: const TextStyle(fontSize: 13),
                                          decoration: InputDecoration(
                                            hintText:
                                                '번호, 판매점, 가입자, 통신사, 개통처 검색',
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
                                        options: const [
                                          '전체',
                                          'SKT',
                                          'KT',
                                          'LGU+'
                                        ],
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
                                const SizedBox(height: 10),
                                Column(
                                  children: [
                                    Row(
                                      children: [
                                        SizedBox(
                                          width: 36,
                                          height: 36,
                                          child: OutlinedButton(
                                            onPressed: selectedMemberCount == 0
                                                ? null
                                                : showSmsSendDialog,
                                            style: OutlinedButton.styleFrom(
                                              minimumSize: const Size(36, 36),
                                              padding: EdgeInsets.zero,
                                              visualDensity:
                                                  VisualDensity.compact,
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
                                            onPressed: selectedMemberCount == 0
                                                ? null
                                                : sendKakaoToSelectedMembers,
                                            style: OutlinedButton.styleFrom(
                                              minimumSize: const Size(36, 36),
                                              padding: EdgeInsets.zero,
                                              visualDensity:
                                                  VisualDensity.compact,
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
                                            icon:
                                                const Icon(Icons.add, size: 14),
                                            label: const Text('등록'),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  const Color(0xFFC94C6E),
                                              foregroundColor: Colors.white,
                                              elevation: 0,
                                              minimumSize: const Size(0, 36),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 0,
                                              ),
                                              textStyle: const TextStyle(
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: ElevatedButton.icon(
                                            onPressed: () => fetchMembers(
                                              keyword: searchController.text,
                                            ),
                                            icon: const Icon(
                                              Icons.refresh,
                                              size: 14,
                                            ),
                                            label: const Text('새로고침'),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.white,
                                              foregroundColor:
                                                  const Color(0xFF6B7280),
                                              elevation: 0,
                                              minimumSize: const Size(0, 36),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 0,
                                              ),
                                              textStyle: const TextStyle(
                                                fontSize: 12,
                                              ),
                                              side: const BorderSide(
                                                color: Color(0xFFE8E9EF),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (canExportExcel) ...[
                                      const SizedBox(height: 8),
                                      SizedBox(
                                        width: double.infinity,
                                        child: OutlinedButton.icon(
                                          onPressed: selectedMemberCount == 0
                                              ? null
                                              : () => exportMembersExcel(
                                                    selectedMembers,
                                                  ),
                                          icon: const Icon(
                                            Icons.table_view_rounded,
                                            size: 16,
                                          ),
                                          label: Text(
                                            '엑셀 출력 ($selectedMemberCount명)',
                                          ),
                                          style: OutlinedButton.styleFrom(
                                            minimumSize: const Size(0, 36),
                                            foregroundColor:
                                                const Color(0xFF2563EB),
                                            side: const BorderSide(
                                              color: Color(0xFFBFDBFE),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
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
                                            onChanged: (value) =>
                                                fetchMembers(keyword: value),
                                            style:
                                                const TextStyle(fontSize: 13),
                                            decoration: InputDecoration(
                                              hintText:
                                                  '번호, 판매자, 가입자, 통신사, 개통처 검색',
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
                                            'SKT',
                                            'KT',
                                            'LGU+'
                                          ],
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
                                OutlinedButton.icon(
                                  onPressed: selectedMemberCount == 0
                                      ? null
                                      : showSmsSendDialog,
                                  icon: const Icon(Icons.sms_rounded, size: 17),
                                  label: Text('문자 ($selectedMemberCount)'),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  onPressed: selectedMemberCount == 0
                                      ? null
                                      : sendKakaoToSelectedMembers,
                                  icon: const Icon(Icons.chat_bubble_rounded,
                                      size: 17),
                                  label: Text('카카오 ($selectedMemberCount)'),
                                ),
                                const SizedBox(width: 8),
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
                                if (canExportExcel) ...[
                                  OutlinedButton.icon(
                                    onPressed: selectedMemberCount == 0
                                        ? null
                                        : () => exportMembersExcel(
                                              selectedMembers,
                                            ),
                                    icon: const Icon(Icons.table_view_rounded,
                                        size: 17),
                                    label: Text('엑셀 ($selectedMemberCount)'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFF2563EB),
                                      side: const BorderSide(
                                        color: Color(0xFFBFDBFE),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                ElevatedButton.icon(
                                  onPressed: () => fetchMembers(
                                      keyword: searchController.text),
                                  icon: const Icon(Icons.refresh, size: 17),
                                  label: const Text('새로고침'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: const Color(0xFF6B7280),
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
                          : members.isEmpty
                              ? const Center(child: Text('등록된 유선회원이 없습니다'))
                              : Scrollbar(
                                  thumbVisibility: true,
                                  child: SingleChildScrollView(
                                    child: _wiredTable(
                                      visibleMembers,
                                      allSelected: allMembersSelected,
                                      hasSelectionTarget:
                                          filteredMembers.isNotEmpty,
                                      selectionTargetCount:
                                          filteredMembers.length,
                                      partiallySelected:
                                          partiallySelectedMembers,
                                    ),
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
