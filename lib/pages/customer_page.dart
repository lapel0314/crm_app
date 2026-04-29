import 'dart:io';

import 'package:excel/excel.dart' as xls;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:crm_app/services/kakao_talk_service.dart';
import 'package:crm_app/services/contact_action_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crm_app/constants/message_templates.dart';
import 'package:crm_app/utils/store_utils.dart';
import 'package:crm_app/widgets/contact_action_buttons.dart';
import 'package:crm_app/widgets/compact_date_range_picker.dart';

final supabase = Supabase.instance.client;

class CustomerPage extends StatefulWidget {
  final String role;
  final String currentStore;
  final bool openMode;
  final String initialNameQuery;
  final String initialPhoneQuery;

  const CustomerPage({
    super.key,
    required this.role,
    required this.currentStore,
    this.openMode = false,
    this.initialNameQuery = '',
    this.initialPhoneQuery = '',
  });

  @override
  State<CustomerPage> createState() => _CustomerPageState();
}

class _CustomerPageState extends State<CustomerPage> {
  final searchController = TextEditingController();
  final dateSearchController = TextEditingController();
  final phoneSearchController = TextEditingController();
  final NumberFormat moneyFormat = NumberFormat('#,###');
  final kakaoTalkService = KakaoTalkService();
  final contactActionService = const ContactActionService();

  List<Map<String, dynamic>> customers = [];
  final Set<String> selectedCustomerIds = {};
  bool isLoading = true;
  bool isSendingKakao = false;
  bool showSummaryDashboard = false;
  String selectedCarrierFilter = '전체';
  String selectedJoinTypeFilter = '전체';
  int currentPage = 0;
  static const int pageSize = 20;

  bool get isOpenView => widget.openMode || canUseOpenCustomerDb(widget.role);
  bool get canEdit => !isOpenView && canUseCustomerDb(widget.role);
  bool get canDelete => !isOpenView && canDeleteCustomer(widget.role);
  bool get canViewAllStores => isPrivilegedRole(widget.role);
  bool get canExportExcel => isPrivilegedRole(widget.role);

  bool _isCompactIosDialogContext(BuildContext context) {
    return !kIsWeb && Platform.isIOS && MediaQuery.of(context).size.width < 900;
  }

  @override
  void initState() {
    super.initState();
    searchController.text = widget.initialNameQuery;
    phoneSearchController.text = widget.initialPhoneQuery;
    fetchCustomers();
  }

  @override
  void didUpdateWidget(covariant CustomerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialNameQuery != widget.initialNameQuery ||
        oldWidget.initialPhoneQuery != widget.initialPhoneQuery) {
      searchController.text = widget.initialNameQuery;
      phoneSearchController.text = widget.initialPhoneQuery;
      fetchCustomers();
    }
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

  DateTime? _parseSearchDate(String value) {
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

  DateTime? _dateOnly(dynamic value) {
    final parsed = value is DateTime ? value : _parseSearchDate(_date(value));
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  DateTimeRange? _dateRangeFromText(String text) {
    final matches = RegExp(
      r'\d{6}|\d{8}|\d{2,4}[./-]\d{1,2}[./-]\d{1,2}',
    ).allMatches(text).map((match) => match.group(0)!).toList();
    final parts = matches.length >= 2
        ? matches.take(2).toList()
        : text.split('~').map((part) => part.trim()).toList();
    if (parts.length != 2) return null;

    final start = _dateOnly(parts[0]);
    final end = _dateOnly(parts[1]);
    if (start == null || end == null) return null;

    return start.isAfter(end)
        ? DateTimeRange(start: end, end: start)
        : DateTimeRange(start: start, end: end);
  }

  String _formatDateRange(DateTimeRange range) {
    final formatter = DateFormat('yyyy-MM-dd');
    final start = formatter.format(range.start);
    final end = formatter.format(range.end);
    return start == end ? start : '$start ~ $end';
  }

  bool _matchesDateSearch(dynamic value, String filter) {
    if (filter.isEmpty) return true;

    final range = _dateRangeFromText(filter);
    if (range == null) {
      final date = _dateOnly(value);
      final searchDate = _dateOnly(filter);
      if (date != null && searchDate != null) return date == searchDate;
      return _date(value).contains(filter);
    }

    final target = _dateOnly(value);
    if (target == null) return false;
    return !target.isBefore(range.start) && !target.isAfter(range.end);
  }

  void _handleDateSearchChanged(String value) {
    final trimmed = value.trim();
    final compactDigits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    final range = _dateRangeFromText(trimmed);
    final shouldNormalizeSingle = !trimmed.contains('~') &&
        (compactDigits.length == 6 || compactDigits.length == 8);

    if (range != null) {
      final formatted = _formatDateRange(range);
      dateSearchController.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    } else if (shouldNormalizeSingle) {
      final date = _dateOnly(trimmed);
      if (date != null) {
        final formatted = DateFormat('yyyy-MM-dd').format(date);
        dateSearchController.value = TextEditingValue(
          text: formatted,
          selection: TextSelection.collapsed(offset: formatted.length),
        );
      }
    }

    fetchCustomers();
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

  String _displayName(String name) => isOpenView ? _maskName(name) : name;
  String _displayPhone(String phone) => isOpenView ? _maskPhone(phone) : phone;
  String _displayBankInfo(String bankInfo) =>
      isOpenView ? _maskBankInfo(bankInfo) : bankInfo;

  Future<void> _pickSearchDate() async {
    final currentText = dateSearchController.text.trim();
    final initialRange = _dateRangeFromText(currentText);
    final initialDate = _dateOnly(currentText) ?? DateTime.now();
    final picked = await showCompactDateRangePicker(
      context: context,
      initialDateRange:
          initialRange ?? DateTimeRange(start: initialDate, end: initialDate),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      title: '가입일 기간 선택',
    );
    if (picked == null) return;

    dateSearchController.text = _formatDateRange(picked);
    await fetchCustomers();
  }

  void _clearSearchDate() {
    if (dateSearchController.text.isEmpty) return;
    dateSearchController.clear();
    fetchCustomers();
  }

  Future<void> _exportCustomersExcel(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) {
      _showCenterMessage('내보낼 고객 데이터가 없습니다.');
      return;
    }
    if (kIsWeb) {
      _showCenterMessage('웹에서는 아직 엑셀 저장을 지원하지 않습니다.');
      return;
    }
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
      _showCenterMessage('엑셀 저장은 PC에서만 지원됩니다.');
      return;
    }

    const typeGroup = XTypeGroup(label: 'Excel', extensions: ['xlsx']);
    final suggestedName = _buildCustomerExcelFileName(rows);
    final saveLocation = await getSaveLocation(
      acceptedTypeGroups: const [typeGroup],
      suggestedName: suggestedName,
      confirmButtonText: '저장',
    );
    if (saveLocation == null) return;

    final excel = xls.Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet();
    final sheetName = '고객DB';
    if (defaultSheet != null && defaultSheet != sheetName) {
      excel.rename(defaultSheet, sheetName);
    }
    final sheet = excel[sheetName];

    excel.appendRow(sheetName, [
      xls.TextCellValue('가입일'),
      xls.TextCellValue('매장'),
      xls.TextCellValue('담당자'),
      xls.TextCellValue('고객명'),
      xls.TextCellValue('휴대폰번호'),
      xls.TextCellValue('통신사'),
      xls.TextCellValue('가입유형'),
      xls.TextCellValue('모델명'),
      xls.TextCellValue('요금제'),
      xls.TextCellValue('리베이트'),
      xls.TextCellValue('부가리베이트'),
      xls.TextCellValue('히든리베이트'),
      xls.TextCellValue('총리베이트'),
      xls.TextCellValue('유통망지원금'),
      xls.TextCellValue('결제'),
      xls.TextCellValue('입금'),
      xls.TextCellValue('마진'),
      xls.TextCellValue('은행정보'),
      xls.TextCellValue('메모'),
    ]);

    for (final customer in rows) {
      final rebate = _toInt(customer['rebate']);
      final addRebate = _toInt(customer['add_rebate']);
      final hiddenRebate = _toInt(customer['hidden_rebate']);
      final supportMoney = _toInt(customer['support_money']);
      final payment = _toInt(customer['payment']);
      final deposit = _toInt(customer['deposit']);
      final totalRebate = _calcTotalRebate(
        rebate: rebate,
        addRebate: addRebate,
        hiddenRebate: hiddenRebate,
        deduction: _toInt(customer['deduction']),
        supportMoney: supportMoney,
        payment: payment,
        deposit: deposit,
        tradePrice: _toInt(customer['trade_price']),
      );
      final margin = _calcMargin(
        totalRebate: totalRebate,
        supportMoney: supportMoney,
        payment: payment,
        deposit: deposit,
      );

      excel.appendRow(sheetName, [
        xls.TextCellValue(_date(customer['join_date'])),
        xls.TextCellValue(customer['store']?.toString() ?? ''),
        xls.TextCellValue(customer['staff']?.toString() ?? ''),
        xls.TextCellValue(customer['name']?.toString() ?? ''),
        xls.TextCellValue(customer['phone']?.toString() ?? ''),
        xls.TextCellValue(customer['carrier']?.toString() ?? ''),
        xls.TextCellValue(customer['join_type']?.toString() ?? ''),
        xls.TextCellValue(customer['model']?.toString() ?? ''),
        xls.TextCellValue(customer['plan']?.toString() ?? ''),
        xls.IntCellValue(rebate),
        xls.IntCellValue(addRebate),
        xls.IntCellValue(hiddenRebate),
        xls.IntCellValue(totalRebate),
        xls.IntCellValue(supportMoney),
        xls.IntCellValue(payment),
        xls.IntCellValue(deposit),
        xls.IntCellValue(margin),
        xls.TextCellValue(customer['bank_info']?.toString() ?? ''),
        xls.TextCellValue(customer['memo']?.toString() ?? ''),
      ]);
    }

    _styleCustomerExcelSheet(sheet, rows);

    final bytes = excel.save(fileName: suggestedName);
    if (bytes == null || bytes.isEmpty) {
      _showCenterMessage('엑셀 파일 생성에 실패했습니다.');
      return;
    }

    await File(saveLocation.path).writeAsBytes(bytes, flush: true);
    if (!mounted) return;
    _showCenterMessage('고객DB 엑셀 저장이 완료되었습니다.');
  }

  String _buildCustomerExcelFileName(List<Map<String, dynamic>> rows) {
    final storeLabel = _buildExcelStoreLabel(
      rows.map((row) => row['store']),
      fallback: '전체매장',
    );
    final dateLabel = _buildExcelDateLabel(
      selectedText: dateSearchController.text,
      dates: rows.map((row) => _date(row['join_date'])),
      fallback: '전체기간',
    );
    return '고객DB_${_sanitizeExcelFilePart(storeLabel)}_${_sanitizeExcelFilePart(dateLabel)}.xlsx';
  }

  void _styleCustomerExcelSheet(
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
    final totalRebateStyle = xls.CellStyle(
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
      12,
      12,
      16,
      10,
      12,
      16,
      14,
      14,
      14,
      14,
      14,
      14,
      14,
      14,
      14,
      24,
      28,
    ];
    for (var i = 0; i < widths.length; i++) {
      sheet.setColumnWidth(i, widths[i]);
      sheet
          .cell(xls.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
          .cellStyle = headerStyle;
    }

    const moneyColumns = <int>[9, 10, 11, 12, 13, 14, 15, 16];
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
            xls.CellIndex.indexByColumnRow(columnIndex: 15, rowIndex: rowIndex),
          )
          .cellStyle = totalRebateStyle;

      final row = rows[rowIndex - 1];
      final rebate = _toInt(row['rebate']);
      final addRebate = _toInt(row['add_rebate']);
      final hiddenRebate = _toInt(row['hidden_rebate']);
      final supportMoney = _toInt(row['support_money']);
      final payment = _toInt(row['payment']);
      final deposit = _toInt(row['deposit']);
      final totalRebate = _calcTotalRebate(
        rebate: rebate,
        addRebate: addRebate,
        hiddenRebate: hiddenRebate,
        deduction: _toInt(row['deduction']),
        supportMoney: supportMoney,
        payment: payment,
        deposit: deposit,
        tradePrice: _toInt(row['trade_price']),
      );
      final margin = _calcMargin(
        totalRebate: totalRebate,
        supportMoney: supportMoney,
        payment: payment,
        deposit: deposit,
      );

      sheet
          .cell(
            xls.CellIndex.indexByColumnRow(columnIndex: 16, rowIndex: rowIndex),
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
    return rebate + addRebate + hiddenRebate;
  }

  int _calcMargin({
    required int totalRebate,
    required int supportMoney,
    required int payment,
    required int deposit,
  }) {
    return totalRebate - supportMoney - payment - deposit;
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
      final List<dynamic> data = isOpenView
          ? await supabase.rpc('customer_open_rows')
          : await supabase
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
        final nameText = _text(item['name']).toLowerCase();
        final phoneText = _text(item['phone']);
        final phoneDigits = phoneText.replaceAll(RegExp(r'[^0-9]'), '');

        final matchesDate = _matchesDateSearch(item['join_date'], dateFilter);
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
        selectedCustomerIds.removeWhere(
          (id) => !customers.any((customer) => customer['id'].toString() == id),
        );
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

  String _firstText(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  List<Map<String, dynamic>> _selectedCustomers([
    List<Map<String, dynamic>>? source,
  ]) {
    final rows = source ?? customers;
    return rows
        .where((customer) =>
            selectedCustomerIds.contains(customer['id'].toString()))
        .toList();
  }

  bool _areAllCustomersSelected(List<Map<String, dynamic>> rows) {
    return rows.isNotEmpty &&
        rows.every(
          (customer) => selectedCustomerIds.contains(customer['id'].toString()),
        );
  }

  void _toggleSelectAllCustomers(List<Map<String, dynamic>> rows, bool select) {
    setState(() {
      for (final customer in rows) {
        final customerId = customer['id'].toString();
        if (select) {
          selectedCustomerIds.add(customerId);
        } else {
          selectedCustomerIds.remove(customerId);
        }
      }
    });
  }

  void _showKakaoSendingDialog(int total) {
    final compactIos = _isCompactIosDialogContext(context);
    final screenSize = MediaQuery.of(context).size;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Container(
            width: compactIos ? screenSize.width - 56 : 420,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                const SizedBox(height: 18),
                Text(
                  '카카오 발송 중 ($total명)',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '발송 중에는 마우스와 키보드를 조작하지 말아주세요.\n카카오톡 PC 창이 자동으로 전환됩니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showKakaoResultDialog(List<KakaoSendResult> results) {
    final failures = results.where((result) => !result.success).toList();
    final successCount = results.length - failures.length;

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final compactIos = _isCompactIosDialogContext(dialogContext);
        final screenSize = MediaQuery.of(dialogContext).size;
        return AlertDialog(
          title: const Text('카카오 발송 결과'),
          content: SizedBox(
            width: compactIos ? screenSize.width - 56 : 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '성공 $successCount건 / 실패 ${failures.length}건',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111827),
                  ),
                ),
                if (failures.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text(
                    '실패한 대상',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 260),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE8E9EF)),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: failures.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: Color(0xFFE8E9EF)),
                      itemBuilder: (context, index) {
                        final failure = failures[index];
                        final name = failure.target.customerName;
                        final target = failure.target.searchName;
                        return ListTile(
                          dense: true,
                          title: Text(
                            '$name ($target)',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            failure.errorMessage ?? '-',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('확인'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _insertKakaoLog(KakaoSendResult result) async {
    final user = supabase.auth.currentUser;
    try {
      await supabase.from('kakao_send_logs').insert({
        'target_name': result.target.searchName,
        'message': result.message,
        'success': result.success,
        'error_message': result.errorMessage,
        'sent_at': DateTime.now().toIso8601String(),
        'sent_by': user?.id,
      });
    } catch (e) {
      _logUiError('카카오 발송 로그 저장 실패: $e');
    }
  }

  Future<void> _sendKakaoMessage(String message) async {
    final selected = _selectedCustomers();
    if (selected.isEmpty) {
      _showCenterMessage('발송할 고객을 선택해 주세요');
      return;
    }
    if (selected.length > 50) {
      _showCenterMessage('카카오 발송은 한 번에 최대 50명까지 가능합니다');
      return;
    }

    if (kIsWeb || !Platform.isWindows) {
      final result = await const ContactActionService().kakao(message);
      if (!mounted) return;
      _showCenterMessage(
        result.message ??
            (result.success
                ? '${selected.length}명 카카오톡 공유 화면을 열었습니다.'
                : '카카오톡을 열 수 없습니다.'),
      );
      return;
    }

    final targets = selected.map((customer) {
      final searchName = _firstText(
        customer,
        ['kakao_search_name', 'kakao_room_name', 'name'],
      );
      return KakaoSendTarget(
        id: customer['id'].toString(),
        customerName: _text(customer['name']),
        searchName: searchName,
        chatType: KakaoChatType.fromText(customer['kakao_chat_type']),
      );
    }).toList();

    setState(() => isSendingKakao = true);
    _showKakaoSendingDialog(targets.length);

    try {
      final results = await kakaoTalkService.sendBulkMessages(
        targets: targets,
        message: message,
        delayBetweenMessages: const Duration(seconds: 2),
      );
      for (final result in results) {
        await _insertKakaoLog(result);
      }

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      setState(() => isSendingKakao = false);
      _showKakaoResultDialog(results);
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      setState(() => isSendingKakao = false);
      _showCenterMessage('카카오 발송 중 오류가 발생했습니다: $e');
    }
  }

  Future<void> _sendSmsToSelected(String message) async {
    final selected = _selectedCustomers();
    if (selected.isEmpty) {
      _showCenterMessage('문자를 보낼 고객을 선택해 주세요');
      return;
    }
    final result = await contactActionService.smsBulk(
      selected.map((customer) => customer['phone']?.toString() ?? '').toList(),
      message,
    );
    if (!result.success) {
      _showCenterMessage(result.message ?? '문자 앱을 열 수 없습니다.');
    }
  }

  Future<void> showSmsSendDialog() async {
    final selected = _selectedCustomers();
    if (selected.isEmpty) {
      _showCenterMessage('문자를 보낼 고객을 선택해 주세요');
      return;
    }
    final controller = TextEditingController(
      text: buildContactMessage(customerName: _text(selected.first['name'])),
    );
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('문자 발송 (${selected.length}명)'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: '문자 내용',
            alignLabelWithHint: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () async {
              final message = controller.text.trim();
              if (message.isEmpty) {
                _showCenterMessage('문자 내용을 입력해 주세요');
                return;
              }
              Navigator.pop(context);
              await _sendSmsToSelected(message);
            },
            child: const Text('문자 앱 열기'),
          ),
        ],
      ),
    );
  }

  Future<List<String>> _loadKakaoTemplates() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('kakao_message_templates') ?? [];
  }

  Future<void> _saveKakaoTemplates(List<String> templates) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('kakao_message_templates', templates);
  }

  String _defaultKakaoGreeting(List<Map<String, dynamic>> selected) {
    final staff = selected.isEmpty ? '' : _text(selected.first['staff']);
    final manager = staff == '-' ? '담당자' : staff;
    return '안녕하세요, 고객님 $manager 입니다.';
  }

  Future<void> _showTemplateEditor({
    required BuildContext context,
    required List<String> templates,
    required void Function(List<String>) onChanged,
    int? editIndex,
  }) async {
    final controller = TextEditingController(
      text: editIndex == null ? '' : templates[editIndex],
    );
    final title = editIndex == null ? '템플릿 추가' : '템플릿 수정';

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: Text(
          title,
          style: const TextStyle(
            color: Color(0xFF111827),
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: controller,
            maxLines: 5,
            decoration: InputDecoration(
              hintText: '자주 쓰는 안내 문구를 입력하세요',
              filled: true,
              fillColor: const Color(0xFFF9FAFB),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: Color(0xFF111827), width: 1.2),
              ),
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
              backgroundColor: const Color(0xFF111827),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () async {
              final text = controller.text.trim();
              if (text.isEmpty) return;
              final next = [...templates];
              if (editIndex == null) {
                if (next.length >= 5) {
                  _showCenterMessage('템플릿은 최대 5개까지 저장됩니다');
                  return;
                }
                next.add(text);
              } else {
                next[editIndex] = text;
              }
              await _saveKakaoTemplates(next);
              onChanged(next);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }

  Future<void> showKakaoSendDialog() async {
    final selected = _selectedCustomers();
    final messageController = TextEditingController(
      text: buildContactMessage(customerName: ''),
    );
    var templates = await _loadKakaoTemplates();
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final compactIos = _isCompactIosDialogContext(context);
          final screenSize = MediaQuery.of(context).size;

          void applyTemplates(List<String> next) {
            setDialogState(() => templates = next);
          }

          void appendTemplate(String template) {
            final current = messageController.text.trimRight();
            final next = current.isEmpty ? template : '$current\n\n$template';
            messageController.value = TextEditingValue(
              text: next,
              selection: TextSelection.collapsed(offset: next.length),
            );
          }

          return Dialog(
            insetPadding: EdgeInsets.symmetric(
              horizontal: compactIos ? 16 : 24,
              vertical: 24,
            ),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            child: Container(
              width: compactIos ? screenSize.width - 32 : 720,
              constraints: BoxConstraints(
                maxHeight: compactIos ? screenSize.height * 0.82 : 760,
              ),
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE500),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.chat_bubble_outline,
                            color: Color(0xFF111827), size: 19),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '카카오 발송 (${selected.length}명)',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF111827),
                              ),
                            ),
                            const SizedBox(height: 3),
                            const Text(
                              '카카오톡 PC에서 검색되는 이름 또는 채팅방명 기준으로 발송합니다',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF8B95A1),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: messageController,
                    maxLines: 8,
                    decoration: InputDecoration(
                      labelText: '발송 메시지',
                      alignLabelWithHint: true,
                      filled: true,
                      fillColor: const Color(0xFFF9FAFB),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFE8E9EF)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Text(
                        '템플릿',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${templates.length}/5',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF8B95A1),
                        ),
                      ),
                      const Spacer(),
                      OutlinedButton.icon(
                        onPressed: templates.length >= 5
                            ? null
                            : () => _showTemplateEditor(
                                  context: context,
                                  templates: templates,
                                  onChanged: applyTemplates,
                                ),
                        icon: const Icon(Icons.add_rounded, size: 17),
                        label: const Text('템플릿 추가'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 180),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE8E9EF)),
                    ),
                    child: templates.isEmpty
                        ? const Text(
                            '저장된 템플릿이 없습니다',
                            style: TextStyle(
                              color: Color(0xFF8B95A1),
                              fontWeight: FontWeight.w600,
                            ),
                          )
                        : SingleChildScrollView(
                            child: Column(
                              children: [
                                for (var i = 0; i < templates.length; i++)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: const Color(0xFFE8E9EF),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: InkWell(
                                            onTap: () =>
                                                appendTemplate(templates[i]),
                                            child: Text(
                                              templates[i],
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF111827),
                                              ),
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: '수정',
                                          onPressed: () => _showTemplateEditor(
                                            context: context,
                                            templates: templates,
                                            editIndex: i,
                                            onChanged: applyTemplates,
                                          ),
                                          icon: const Icon(Icons.edit_outlined,
                                              size: 18),
                                        ),
                                        IconButton(
                                          tooltip: '삭제',
                                          onPressed: () async {
                                            final next = [...templates]
                                              ..removeAt(i);
                                            await _saveKakaoTemplates(next);
                                            applyTemplates(next);
                                          },
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            size: 18,
                                            color: Color(0xFFDC2626),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('취소'),
                      ),
                      const Spacer(),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF111827),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 14,
                          ),
                        ),
                        onPressed: () async {
                          final message = messageController.text.trim();
                          if (message.isEmpty) {
                            _showCenterMessage('메시지를 입력해 주세요');
                            return;
                          }
                          Navigator.pop(context);
                          await _sendKakaoMessage(message);
                        },
                        icon: const Icon(Icons.send_rounded, size: 17),
                        label: const Text('발송'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
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
          filled: true,
          fillColor: const Color(0xFFF9FAFB),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF111827), width: 1.2),
          ),
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
          filled: true,
          fillColor: const Color(0xFFF9FAFB),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF111827), width: 1.2),
          ),
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

    int currentMargin() => _calcMargin(
          totalRebate: currentTotalRebate(),
          supportMoney: _toInt(supportMoneyController.text),
          payment: _toInt(paymentController.text),
          deposit: _toInt(depositController.text),
        );

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          final compactIos = _isCompactIosDialogContext(context);
          final screenSize = MediaQuery.of(context).size;

          void onMoneyChanged(TextEditingController controller, String value) {
            _applyMoneyFormat(controller, value);
            setDialogState(() {});
          }

          return AlertDialog(
            backgroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
            contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
            actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            title: const Row(
              children: [
                Icon(Icons.edit_note_rounded,
                    color: Color(0xFF111827), size: 22),
                SizedBox(width: 10),
                Text(
                  '고객 수정',
                  style: TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: compactIos ? screenSize.width - 56 : 680,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF111827),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () async {
                  final totalRebate = currentTotalRebate();
                  const tax = 0;
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
                        if (!isOpenView)
                          ContactActionButtons(
                            customerName: customer['name']?.toString() ?? '',
                            phone: customer['phone']?.toString() ?? '',
                            onMessage: _showCenterMessage,
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

  Widget _filterField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    double width = 220,
    VoidCallback? onIconPressed,
    VoidCallback? onClear,
    ValueChanged<String>? onChanged,
  }) {
    final hasText = controller.text.trim().isNotEmpty;
    return SizedBox(
      width: width,
      height: 38,
      child: TextField(
        controller: controller,
        onChanged: onChanged ?? (_) => fetchCustomers(),
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: onIconPressed == null
              ? Icon(icon, size: 17, color: const Color(0xFF9CA3AF))
              : IconButton(
                  tooltip: '달력 열기',
                  onPressed: onIconPressed,
                  icon: Icon(icon, size: 17),
                  color: hasText
                      ? const Color(0xFFC94C6E)
                      : const Color(0xFF9CA3AF),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 34,
                    minHeight: 34,
                  ),
                ),
          suffixIcon: onClear != null && hasText
              ? IconButton(
                  tooltip: '날짜 검색 지우기',
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  color: const Color(0xFF9CA3AF),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                )
              : null,
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

  Widget _customerTable(
    List<Map<String, dynamic>> visibleCustomers, {
    required bool allSelected,
    required bool hasSelectionTarget,
    required int selectionTargetCount,
    required bool partiallySelected,
  }) {
    final showSelection = !isOpenView;
    final baseWidths = <double>[
      if (showSelection) 118,
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
      184,
    ];
    final headers = [
      if (showSelection) '선택',
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
        widths[showSelection ? 9 : 8] += extraWidth;

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
                        if (showSelection && i == 0)
                          _selectionHeaderCell(
                            width: widths[i],
                            allSelected: allSelected,
                            hasSelectionTarget: hasSelectionTarget,
                            partiallySelected: partiallySelected,
                            selectionTargetCount: selectionTargetCount,
                            onChanged: (value) => _toggleSelectAllCustomers(
                              customers,
                              value ?? false,
                            ),
                          )
                        else
                          _headerCell(headers[i], widths[i]),
                    ],
                  ),
                ),
                ...visibleCustomers.map((customer) {
                  final offset = showSelection ? 1 : 0;
                  final customerId = customer['id'].toString();
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
                          if (showSelection)
                            _tableCell(
                              Checkbox(
                                value: selectedCustomerIds.contains(customerId),
                                onChanged: (value) {
                                  setState(() {
                                    if (value == true) {
                                      selectedCustomerIds.add(customerId);
                                    } else {
                                      selectedCustomerIds.remove(customerId);
                                    }
                                  });
                                },
                              ),
                              widths[0],
                            ),
                          _tableCell(_tableText(_date(customer['join_date'])),
                              widths[offset + 0]),
                          _tableCell(
                            _tableBadge(
                              _text(customer['staff']),
                              color: _staffColor(customer['staff']),
                            ),
                            widths[offset + 1],
                          ),
                          _tableCell(
                            _tableText(
                              _displayName(customer['name']?.toString() ?? ''),
                              strong: true,
                            ),
                            widths[offset + 2],
                          ),
                          _tableCell(_tableText(phone), widths[offset + 3]),
                          _tableCell(
                            _tableBadge(
                              _text(customer['join_type']),
                              color: _joinTypeColor(customer['join_type']),
                            ),
                            widths[offset + 4],
                          ),
                          _tableCell(
                            _tableBadge(
                              _text(customer['carrier']),
                              color: _carrierColor(customer['carrier']),
                            ),
                            widths[offset + 5],
                          ),
                          _tableCell(
                            _tableText(_text(customer['previous_carrier'])),
                            widths[offset + 6],
                          ),
                          _tableCell(
                            _tableText(_text(customer['model']), strong: true),
                            widths[offset + 7],
                          ),
                          _tableCell(_tableText(_text(customer['plan'])),
                              widths[offset + 8]),
                          _tableCell(
                            _tableText(_text(customer['add_service'])),
                            widths[offset + 9],
                          ),
                          _tableCell(
                            _tableBadge(
                              _text(customer['contract_type']),
                              color:
                                  _contractTypeColor(customer['contract_type']),
                            ),
                            widths[offset + 10],
                          ),
                          _tableCell(
                            _tableText('${_text(customer['installment'])}개월'),
                            widths[offset + 11],
                          ),
                          _tableCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!isOpenView)
                                  _compactIconButton(
                                    tooltip: '\uC804\uD654',
                                    onPressed: () async {
                                      final phoneNumber =
                                          customer['phone']?.toString() ?? '';
                                      if (_displayPhone(phoneNumber).isEmpty) {
                                        _showCenterMessage(
                                          '\uC0AC\uC6A9 \uAC00\uB2A5\uD55C \uC804\uD654\uBC88\uD638\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4.',
                                        );
                                        return;
                                      }
                                      final result =
                                          await const ContactActionService()
                                              .call(phoneNumber);
                                      if (!mounted) return;
                                      if (!result.success &&
                                          result.message != null) {
                                        _showCenterMessage(result.message!);
                                      }
                                    },
                                    icon: const Icon(
                                      Icons.call_outlined,
                                      size: 18,
                                    ),
                                  ),
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
                            widths[offset + 12],
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
    phoneSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalCustomers = customers.length;
    final selectedCustomers = _selectedCustomers();
    final selectedCustomerCount = selectedCustomers.length;
    final allCustomersSelected = _areAllCustomersSelected(customers);
    final partiallySelectedCustomers =
        !allCustomersSelected && selectedCustomerCount > 0;
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
    final mobile = MediaQuery.of(context).size.width < 900;

    if (mobile) {
      return Scaffold(
        backgroundColor: const Color(0xFFF4F5F8),
        body: Padding(
          padding: const EdgeInsets.all(14),
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
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 16,
                    ),
                    label: Text(
                      showSummaryDashboard
                          ? '\uC694\uC57D \uC228\uAE30\uAE30'
                          : '\uC694\uC57D \uBCF4\uAE30',
                    ),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 0,
                      ),
                      foregroundColor: const Color(0xFF4B5563),
                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                  ),
                ],
              ),
              SizedBox(height: showSummaryDashboard ? 12 : 6),
              if (showSummaryDashboard) ...[
                SizedBox(
                  height: 168,
                  child: GridView.count(
                    crossAxisCount: 2,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 2.0,
                    children: [
                      _summaryTile(
                        label: '\uC804\uCCB4 \uACE0\uAC1D',
                        value: '$totalCustomers\uBA85',
                        color: const Color(0xFF6B7280),
                        compact: true,
                      ),
                      _summaryTile(
                        label: '\uC2E0\uADDC \uAC1C\uD1B5',
                        value: '$newJoinCount\uBA85',
                        color: const Color(0xFF10B981),
                        compact: true,
                      ),
                      _summaryTile(
                        label: '\uBC88\uD638\uC774\uB3D9',
                        value: '$transferCount\uBA85',
                        color: const Color(0xFF3B82F6),
                        compact: true,
                      ),
                      _summaryTile(
                        label: '\uAE30\uAE30\uBCC0\uACBD',
                        value: '$deviceChangeCount\uBA85',
                        color: const Color(0xFFF59E0B),
                        compact: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
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
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _filterField(
                                    controller: dateSearchController,
                                    hint: '\uAC00\uC785\uC77C',
                                    icon: Icons.calendar_today_outlined,
                                    width: 132,
                                    onIconPressed: _pickSearchDate,
                                    onClear: _clearSearchDate,
                                    onChanged: _handleDateSearchChanged,
                                  ),
                                  const SizedBox(width: 8),
                                  _filterField(
                                    controller: searchController,
                                    hint: '\uACE0\uAC1D\uBA85',
                                    icon: Icons.person_search_outlined,
                                    width: 120,
                                  ),
                                  const SizedBox(width: 8),
                                  _filterField(
                                    controller: phoneSearchController,
                                    hint: '\uC804\uD654\uBC88\uD638',
                                    icon: Icons.phone_iphone_outlined,
                                    width: 132,
                                  ),
                                  const SizedBox(width: 8),
                                  _segmentedFilter(
                                    options: const [
                                      '\uC804\uCCB4',
                                      'SKT',
                                      'KT',
                                      'LGU+',
                                    ],
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
                                    options: const [
                                      '\uC804\uCCB4',
                                      '\uC2E0\uADDC',
                                      '\uBC88\uD638\uC774\uB3D9',
                                      '\uAE30\uAE30\uBCC0\uACBD',
                                    ],
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
                            const SizedBox(height: 10),
                            Column(
                              children: [
                                Row(
                                  children: [
                                    if (!isOpenView) ...[
                                      SizedBox(
                                        width: 36,
                                        height: 36,
                                        child: OutlinedButton(
                                          onPressed:
                                              selectedCustomerCount == 0 ||
                                                      isSendingKakao
                                                  ? null
                                                  : showKakaoSendDialog,
                                          style: OutlinedButton.styleFrom(
                                            minimumSize: const Size(36, 36),
                                            padding: EdgeInsets.zero,
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                          child: Icon(
                                            isSendingKakao
                                                ? Icons.hourglass_top_rounded
                                                : Icons.chat_bubble_outline,
                                            size: 16,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      SizedBox(
                                        width: 36,
                                        height: 36,
                                        child: OutlinedButton(
                                          onPressed: selectedCustomerCount == 0
                                              ? null
                                              : showSmsSendDialog,
                                          style: OutlinedButton.styleFrom(
                                            minimumSize: const Size(36, 36),
                                            padding: EdgeInsets.zero,
                                            visualDensity:
                                                VisualDensity.compact,
                                          ),
                                          child: const Icon(
                                            Icons.sms_outlined,
                                            size: 16,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                    ],
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: () => fetchCustomers(),
                                        icon:
                                            const Icon(Icons.refresh, size: 14),
                                        label: const Text(
                                          '\uC0C8\uB85C\uACE0\uCE68',
                                        ),
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
                                if (canExportExcel) ...[
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      onPressed: selectedCustomerCount == 0
                                          ? null
                                          : () => _exportCustomersExcel(
                                                selectedCustomers,
                                              ),
                                      icon: const Icon(Icons.table_view_rounded,
                                          size: 16),
                                      label: Text(
                                        '엑셀 출력 ($selectedCustomerCount명)',
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
                        ),
                      ),
                      const Divider(height: 1, color: Color(0xFFF3F4F6)),
                      Expanded(
                        child: isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : customers.isEmpty
                                ? const Center(
                                    child: Text(
                                      '\uACE0\uAC1D \uC815\uBCF4\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4',
                                    ),
                                  )
                                : Scrollbar(
                                    thumbVisibility: true,
                                    child: SingleChildScrollView(
                                      child: _customerTable(
                                        visibleCustomers,
                                        allSelected: allCustomersSelected,
                                        hasSelectionTarget:
                                            customers.isNotEmpty,
                                        selectionTargetCount: customers.length,
                                        partiallySelected:
                                            partiallySelectedCustomers,
                                      ),
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

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      body: Padding(
        padding: EdgeInsets.all(mobile ? 14 : 28),
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
                                    onIconPressed: _pickSearchDate,
                                    onClear: _clearSearchDate,
                                    onChanged: _handleDateSearchChanged,
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
                          if (!isOpenView) ...[
                            ElevatedButton.icon(
                              onPressed:
                                  selectedCustomerCount == 0 || isSendingKakao
                                      ? null
                                      : showKakaoSendDialog,
                              icon: const Icon(Icons.chat_bubble_outline,
                                  size: 17),
                              label: Text(isSendingKakao
                                  ? '발송 중'
                                  : '카카오 발송 ($selectedCustomerCount)'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFEE500),
                                foregroundColor: const Color(0xFF111827),
                                elevation: 0,
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: selectedCustomerCount == 0
                                  ? null
                                  : showSmsSendDialog,
                              icon: const Icon(Icons.sms_outlined, size: 17),
                              label: Text('문자 발송 ($selectedCustomerCount)'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: const Color(0xFF374151),
                                elevation: 0,
                                side: const BorderSide(
                                  color: Color(0xFFE8E9EF),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          if (canExportExcel) ...[
                            OutlinedButton.icon(
                              onPressed: selectedCustomerCount == 0
                                  ? null
                                  : () => _exportCustomersExcel(
                                        selectedCustomers,
                                      ),
                              icon: const Icon(Icons.table_view_rounded,
                                  size: 17),
                              label: Text('엑셀 ($selectedCustomerCount)'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF2563EB),
                                side:
                                    const BorderSide(color: Color(0xFFBFDBFE)),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
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
                                    child: _customerTable(
                                      visibleCustomers,
                                      allSelected: allCustomersSelected,
                                      hasSelectionTarget: customers.isNotEmpty,
                                      selectionTargetCount: customers.length,
                                      partiallySelected:
                                          partiallySelectedCustomers,
                                    ),
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
