import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crm_app/utils/store_utils.dart';

final supabase = Supabase.instance.client;

class GlobalSearchPage extends StatefulWidget {
  final String nameQuery;
  final String phoneQuery;
  final String role;
  final String currentStore;
  final ValueChanged<String>? onNavigateToPage;

  const GlobalSearchPage({
    super.key,
    required this.nameQuery,
    required this.phoneQuery,
    required this.role,
    required this.currentStore,
    this.onNavigateToPage,
  });

  @override
  State<GlobalSearchPage> createState() => _GlobalSearchPageState();
}

class _GlobalSearchPageState extends State<GlobalSearchPage> {
  bool isLoading = false;
  List<Map<String, dynamic>> customers = [];
  List<Map<String, dynamic>> wiredMembers = [];
  List<Map<String, dynamic>> leads = [];
  String? errorMessage;
  final NumberFormat moneyFormat = NumberFormat('#,###');
  bool get canViewAllStores => isPrivilegedRole(widget.role);

  bool _isCompactIosDialogContext(BuildContext context) {
    return !kIsWeb && Platform.isIOS && MediaQuery.of(context).size.width < 900;
  }

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void didUpdateWidget(covariant GlobalSearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nameQuery != widget.nameQuery ||
        oldWidget.phoneQuery != widget.phoneQuery) {
      _search();
    }
  }

  String _text(dynamic value) {
    if (value == null) return '-';
    final text = value.toString().trim();
    return text.isEmpty ? '-' : text;
  }

  String _date(dynamic value) {
    if (value == null) return '-';
    final text = value.toString();
    return text.length >= 10 ? text.substring(0, 10) : text;
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

  dynamic _value(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key];
      if (value != null && value.toString().trim().isNotEmpty) return value;
    }
    return null;
  }

  String _tradeInText(dynamic value) {
    if (value == null) return '-';
    if (value == true) return 'O';
    if (value == false) return 'X';
    return _text(value);
  }

  String _normalizeCarrier(String value) {
    return value.toUpperCase().replaceAll(RegExp(r'[\s_-]'), '');
  }

  Color _carrierColor(dynamic value) {
    final carrier = _normalizeCarrier(_text(value));
    if (carrier.contains('SK')) return const Color(0xFF2563EB);
    if (carrier.contains('KT')) return const Color(0xFFEF4444);
    if (carrier.contains('LG')) return const Color(0xFFC94C6E);
    return const Color(0xFF6B7280);
  }

  String _digits(String value) => value.replaceAll(RegExp(r'[^0-9]'), '');

  String _formatPhone(String digits) {
    if (digits.length != 11) return digits;
    return '${digits.substring(0, 3)}-${digits.substring(3, 7)}-${digits.substring(7)}';
  }

  String _containsFilter({
    required List<String> nameColumns,
    required List<String> phoneColumns,
  }) {
    final name = widget.nameQuery.trim();
    final phone = widget.phoneQuery.trim();
    final phoneValues = <String>{phone};
    final digits = _digits(phone);
    if (digits.isNotEmpty) {
      phoneValues.add(digits);
      phoneValues.add(_formatPhone(digits));
    }

    final filters = <String>[];
    for (final column in nameColumns) {
      if (name.isNotEmpty) {
        filters.add('$column.ilike.%$name%');
      }
    }
    for (final column in phoneColumns) {
      for (final value in phoneValues.where((e) => e.isNotEmpty)) {
        filters.add('$column.ilike.%$value%');
      }
    }
    return filters.join(',');
  }

  bool _matchesRow({
    required Map<String, dynamic> row,
    required List<String> nameColumns,
    required List<String> phoneColumns,
  }) {
    final name = widget.nameQuery.trim().toLowerCase();
    final phoneDigits = _digits(widget.phoneQuery);
    final matchesName = name.isEmpty ||
        nameColumns
            .any((column) => _text(row[column]).toLowerCase().contains(name));
    final matchesPhone = phoneDigits.isEmpty ||
        phoneColumns
            .any((column) => _digits(_text(row[column])).contains(phoneDigits));
    return matchesName && matchesPhone;
  }

  Future<void> _search() async {
    final name = widget.nameQuery.trim();
    final phone = widget.phoneQuery.trim();
    if (name.isEmpty && phone.isEmpty) {
      setState(() {
        isLoading = false;
        customers = [];
        wiredMembers = [];
        leads = [];
        errorMessage = null;
      });
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final customerFilter = _containsFilter(
        nameColumns: ['name'],
        phoneColumns: ['phone'],
      );
      final wiredFilter = _containsFilter(
        nameColumns: ['subscriber', 'customer_name'],
        phoneColumns: ['phone'],
      );
      final leadsFilter = _containsFilter(
        nameColumns: ['subscriber'],
        phoneColumns: ['phone'],
      );

      final result = await Future.wait<List<dynamic>>([
        supabase
            .from('customers')
            .select()
            .or(customerFilter)
            .order('join_date', ascending: false)
            .limit(20),
        supabase
            .from('wired_members')
            .select()
            .or(wiredFilter)
            .order('subscription_date', ascending: false)
            .limit(20),
        supabase
            .from('leads')
            .select()
            .or(leadsFilter)
            .order('lead_date', ascending: false)
            .limit(20),
      ]);

      if (!mounted) return;
      setState(() {
        customers = result[0]
            .map((e) => Map<String, dynamic>.from(e))
            .where(
              (row) =>
                  (canViewAllStores ||
                      isSameStore(row['store'], widget.currentStore)) &&
                  _matchesRow(
                    row: row,
                    nameColumns: ['name'],
                    phoneColumns: ['phone'],
                  ),
            )
            .toList();
        wiredMembers = result[1]
            .map((e) => Map<String, dynamic>.from(e))
            .where(
              (row) =>
                  (canViewAllStores ||
                      isSameStore(row['store'], widget.currentStore)) &&
                  _matchesRow(
                    row: row,
                    nameColumns: ['subscriber', 'customer_name'],
                    phoneColumns: ['phone'],
                  ),
            )
            .toList();
        leads = result[2]
            .map((e) => Map<String, dynamic>.from(e))
            .where(
              (row) =>
                  (canViewAllStores ||
                      isSameStore(row['store'], widget.currentStore)) &&
                  _matchesRow(
                    row: row,
                    nameColumns: ['subscriber'],
                    phoneColumns: ['phone'],
                  ),
            )
            .toList();
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = '검색 실패: $e';
        customers = [];
        wiredMembers = [];
        leads = [];
        isLoading = false;
      });
    }
  }

  Widget _summaryCard({
    required String label,
    required int count,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        height: 84,
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$count건',
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _section({
    required String title,
    required IconData icon,
    required List<Map<String, dynamic>> rows,
    required List<String> headers,
    required List<double> widths,
    required List<Widget> Function(Map<String, dynamic> row) cells,
    required ValueChanged<Map<String, dynamic>> onTap,
    required String pageTitle,
  }) {
    final tableWidth = widths.fold<double>(0, (sum, width) => sum + width) + 36;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE8E9EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Row(
              children: [
                Icon(icon, size: 18, color: const Color(0xFF6B7280)),
                const SizedBox(width: 8),
                Text(
                  '$title ${rows.length}건',
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 12),
                if (widget.onNavigateToPage != null)
                  SizedBox(
                    height: 32,
                    child: OutlinedButton.icon(
                      onPressed: () => widget.onNavigateToPage!(pageTitle),
                      icon: const Icon(Icons.open_in_new_rounded, size: 15),
                      label: Text('$pageTitle로 이동'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFC94C6E),
                        side: const BorderSide(color: Color(0xFFFFCAD8)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF3F4F6)),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                '검색 결과가 없습니다',
                style: TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: tableWidth,
                child: Column(
                  children: [
                    Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      color: const Color(0xFFFAFAFC),
                      child: Row(
                        children: [
                          for (var i = 0; i < headers.length; i++)
                            _headerCell(headers[i], widths[i]),
                        ],
                      ),
                    ),
                    ...rows.map(
                      (row) {
                        final rowCells = cells(row);
                        return InkWell(
                          onTap: () => onTap(row),
                          child: Container(
                            height: 58,
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            decoration: const BoxDecoration(
                              border: Border(
                                bottom: BorderSide(color: Color(0xFFF3F4F6)),
                              ),
                            ),
                            child: Row(
                              children: [
                                for (var i = 0; i < rowCells.length; i++)
                                  _tableCell(rowCells[i], widths[i]),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _headerCell(String text, double width) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFF9CA3AF),
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _tableCell(Widget child, double width) {
    return SizedBox(
      width: width,
      child: Align(
        alignment: Alignment.centerLeft,
        child: child,
      ),
    );
  }

  Widget _tableText(dynamic value, {bool strong = false}) {
    return Text(
      _text(value),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: const Color(0xFF111827),
        fontSize: 13,
        fontWeight: strong ? FontWeight.w900 : FontWeight.w600,
      ),
    );
  }

  Widget _tableBadge(dynamic value, {Color color = const Color(0xFF6B7280)}) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 110),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        _text(value),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  void _showDetailDialog({
    required String title,
    required List<MapEntry<String, dynamic>> rows,
  }) {
    showDialog<void>(
      context: context,
      builder: (context) {
        final compactIos = _isCompactIosDialogContext(context);
        final dialogWidth =
            compactIos ? MediaQuery.of(context).size.width - 56 : 720.0;
        return AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: Text(
          title,
          style: const TextStyle(
            color: Color(0xFF111827),
            fontWeight: FontWeight.w900,
          ),
        ),
        content: SizedBox(
          width: dialogWidth,
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 18,
              runSpacing: 0,
              children: [
                for (final row in rows)
                  _detailRow(
                    row.key,
                    row.value,
                    width: compactIos ? dialogWidth : 330,
                    labelWidth: compactIos ? 92 : 110,
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('닫기'),
          ),
        ],
      );
      },
    );
  }

  Widget _detailRow(
    String label,
    dynamic value, {
    double width = 330,
    double labelWidth = 110,
  }) {
    return SizedBox(
      width: width,
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
              width: labelWidth,
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

  Widget _mobileSummaryCard({
    required String label,
    required int count,
    required Color color,
  }) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
            height: 28,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$count\uAC74',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mobileSection({
    required String title,
    required IconData icon,
    required int count,
    required String pageTitle,
    required List<Map<String, dynamic>> rows,
    required List<String> headers,
    required List<double> widths,
    required List<Widget> Function(Map<String, dynamic> row) cells,
    required ValueChanged<Map<String, dynamic>> onTap,
  }) {
    final tableWidth = widths.fold<double>(0, (sum, width) => sum + width) + 20;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE8E9EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 18, color: const Color(0xFF6B7280)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$title $count\uAC74',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF111827),
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                if (widget.onNavigateToPage != null) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 34,
                    child: OutlinedButton.icon(
                      onPressed: () => widget.onNavigateToPage!(pageTitle),
                      icon: const Icon(Icons.open_in_new_rounded, size: 15),
                      label: Text('$pageTitle\uB85C \uC774\uB3D9'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFC94C6E),
                        side: const BorderSide(color: Color(0xFFFFCAD8)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF3F4F6)),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                '\uAC80\uC0C9 \uACB0\uACFC\uAC00 \uC5C6\uC2B5\uB2C8\uB2E4',
                style: TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: tableWidth,
                child: Column(
                  children: [
                    Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      color: const Color(0xFFFAFAFC),
                      child: Row(
                        children: [
                          for (var i = 0; i < headers.length; i++)
                            _headerCell(headers[i], widths[i]),
                        ],
                      ),
                    ),
                    ...rows.map((row) {
                      final rowCells = cells(row);
                      return InkWell(
                        onTap: () => onTap(row),
                        child: Container(
                          height: 56,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: const BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: Color(0xFFF3F4F6)),
                            ),
                          ),
                          child: Row(
                            children: [
                              for (var i = 0; i < rowCells.length; i++)
                                _tableCell(rowCells[i], widths[i]),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showCustomerDetail(Map<String, dynamic> row) {
    _showDetailDialog(
      title: '고객DB 상세',
      rows: [
        MapEntry('가입일', _date(row['join_date'])),
        MapEntry('M+3', row['m3']),
        MapEntry('M+6', row['m6']),
        MapEntry('담당자', row['staff']),
        MapEntry('고객명', row['name']),
        MapEntry('휴대폰번호', row['phone']),
        MapEntry('개통매장', row['store']),
        MapEntry('가입유형', row['join_type']),
        MapEntry('통신사/거래처', row['carrier']),
        MapEntry('기존통신사', row['previous_carrier']),
        MapEntry('모델명', row['model']),
        MapEntry('요금제', row['plan']),
        MapEntry('부가서비스', _value(row, ['add_service', 'additional_service'])),
        MapEntry('공시/선약', _value(row, ['contract_type', 'support_type'])),
        MapEntry('할부개월', _value(row, ['installment', 'installment_months'])),
        MapEntry('리베이트', _money(row['rebate'])),
        MapEntry('부가리베이트', _money(row['add_rebate'])),
        MapEntry('히든리베이트', _money(row['hidden_rebate'])),
        MapEntry('차감항목', _money(row['deduction'])),
        MapEntry('유통망지원금', _money(row['support_money'])),
        MapEntry('결제', _money(row['payment'])),
        MapEntry('입금', _money(row['deposit'])),
        MapEntry('매입금액', _money(row['trade_price'])),
        MapEntry('총리베이트', _money(row['total_rebate'])),
        MapEntry('세금', _money(row['tax'])),
        MapEntry('마진', _money(row['margin'])),
        MapEntry('메모', row['memo']),
        MapEntry('모바일', row['mobile']),
        MapEntry('2nd', row['second']),
        MapEntry('히든내용', row['hidden_note']),
        MapEntry('차감내용', row['deduction_note']),
        MapEntry('결제내용', row['payment_note']),
        MapEntry('은행/계좌/예금주', row['bank_info']),
        MapEntry('중고폰반납', _tradeInText(row['trade_in'])),
        MapEntry('반납모델', row['trade_model']),
      ],
    );
  }

  void _showWiredDetail(Map<String, dynamic> row) {
    _showDetailDialog(
      title: '유선회원 상세',
      rows: [
        MapEntry('청약일', _date(row['subscription_date'])),
        MapEntry('통신사', row['carrier']),
        MapEntry('개통처', row['activation_center']),
        MapEntry('판매자', row['seller']),
        MapEntry('가입자', row['subscriber']),
        MapEntry('번호', row['phone']),
        MapEntry('인터넷유형', row['internet_type']),
        MapEntry('상품권', row['gift_card']),
        MapEntry('선입금', row['prepayment']),
        MapEntry('후입금', row['postpayment']),
        MapEntry('메모', row['memo']),
      ],
    );
  }

  void _showLeadDetail(Map<String, dynamic> row) {
    _showDetailDialog(
      title: '가망고객 상세',
      rows: [
        MapEntry('등록일', _date(row['lead_date'])),
        MapEntry('담당자', row['manager']),
        MapEntry('가입자', row['subscriber']),
        MapEntry('휴대폰번호', row['phone']),
        MapEntry('기존통신사', row['previous_carrier']),
        MapEntry('변경통신사', row['target_carrier']),
        MapEntry('메모', row['memo']),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.nameQuery.trim();
    final phone = widget.phoneQuery.trim();
    final total = customers.length + wiredMembers.length + leads.length;
    final mobile = MediaQuery.of(context).size.width < 900;
    final queryLabel = [
      if (name.isNotEmpty) '고객명: $name',
      if (phone.isNotEmpty) '핸드폰번호: $phone',
    ].join(' / ');

    final normalizedQueryLabel = [
      if (name.isNotEmpty) '\uACE0\uAC1D\uBA85: $name',
      if (phone.isNotEmpty) '\uD578\uB4DC\uD3F0: $phone',
    ].join(' / ');

    if (mobile) {
      return Scaffold(
        backgroundColor: const Color(0xFFF4F5F8),
        body: Padding(
          padding: const EdgeInsets.all(14),
          child: name.isEmpty && phone.isEmpty
              ? const Center(
                  child: Text(
                    '\uC0C1\uB2E8 \uD1B5\uD569\uAC80\uC0C9\uC5D0\uC11C \uACE0\uAC1D\uBA85 \uB610\uB294 \uD578\uB4DC\uD3F0\uBC88\uD638\uB97C \uC785\uB825\uD574\uC8FC\uC138\uC694.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF6B7280),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 2.05,
                      children: [
                        _mobileSummaryCard(
                          label: '\uC804\uCCB4 \uACB0\uACFC',
                          count: total,
                          color: const Color(0xFF6B7280),
                        ),
                        _mobileSummaryCard(
                          label: '\uACE0\uAC1DDB',
                          count: customers.length,
                          color: const Color(0xFF10B981),
                        ),
                        _mobileSummaryCard(
                          label: '\uC720\uC120\uD68C\uC6D0',
                          count: wiredMembers.length,
                          color: const Color(0xFF3B82F6),
                        ),
                        _mobileSummaryCard(
                          label: '\uAC00\uB9DD\uACE0\uAC1D',
                          count: leads.length,
                          color: const Color(0xFFF59E0B),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '$normalizedQueryLabel \uD1B5\uD569 \uAC80\uC0C9 \uACB0\uACFC',
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : errorMessage != null
                              ? Center(child: Text(errorMessage!))
                              : SingleChildScrollView(
                                  child: Column(
                                    children: [
                                      _mobileSection(
                                        title: '\uACE0\uAC1DDB',
                                        icon: Icons.people_alt_rounded,
                                        count: customers.length,
                                        pageTitle: '\uACE0\uAC1DDB',
                                        rows: customers,
                                        headers: const [
                                          '\uAC00\uC785\uC77C',
                                          '\uACE0\uAC1D\uBA85',
                                          '\uD734\uB300\uD3F0\uBC88\uD638',
                                        ],
                                        widths: const [88, 92, 118],
                                        cells: (row) => [
                                          _tableText(_date(row['join_date'])),
                                          _tableText(row['name'], strong: true),
                                          _tableText(row['phone']),
                                        ],
                                        onTap: _showCustomerDetail,
                                      ),
                                      _mobileSection(
                                        title: '\uC720\uC120\uD68C\uC6D0',
                                        icon: Icons.cable_rounded,
                                        count: wiredMembers.length,
                                        pageTitle: '\uC720\uC120\uD68C\uC6D0',
                                        rows: wiredMembers,
                                        headers: const [
                                          '\uCCAD\uC57D\uC77C',
                                          '\uAC00\uC785\uC790',
                                          '\uBC88\uD638',
                                        ],
                                        widths: const [88, 92, 118],
                                        cells: (row) => [
                                          _tableText(_date(row['subscription_date'])),
                                          _tableText(row['subscriber'], strong: true),
                                          _tableText(row['phone']),
                                        ],
                                        onTap: _showWiredDetail,
                                      ),
                                      _mobileSection(
                                        title: '\uAC00\uB9DD\uACE0\uAC1D',
                                        icon: Icons.person_search_rounded,
                                        count: leads.length,
                                        pageTitle: '\uAC00\uB9DD\uACE0\uAC1D',
                                        rows: leads,
                                        headers: const [
                                          '\uB4F1\uB85D\uC77C',
                                          '\uAC00\uC785\uC790',
                                          '\uD578\uB4DC\uD3F0',
                                        ],
                                        widths: const [88, 92, 118],
                                        cells: (row) => [
                                          _tableText(_date(row['lead_date'])),
                                          _tableText(row['subscriber'], strong: true),
                                          _tableText(row['phone']),
                                        ],
                                        onTap: _showLeadDetail,
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
        padding: const EdgeInsets.all(28),
        child: name.isEmpty && phone.isEmpty
            ? const Center(
                child: Text(
                  '상단 검색창에서 고객명 또는 핸드폰번호를 입력해 주세요',
                  style: TextStyle(
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _summaryCard(
                        label: '전체 결과',
                        count: total,
                        color: const Color(0xFF6B7280),
                      ),
                      const SizedBox(width: 14),
                      _summaryCard(
                        label: '고객DB',
                        count: customers.length,
                        color: const Color(0xFF10B981),
                      ),
                      const SizedBox(width: 14),
                      _summaryCard(
                        label: '유선회원',
                        count: wiredMembers.length,
                        color: const Color(0xFF3B82F6),
                      ),
                      const SizedBox(width: 14),
                      _summaryCard(
                        label: '가망고객',
                        count: leads.length,
                        color: const Color(0xFFF59E0B),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '$queryLabel 통합 검색 결과',
                    style: const TextStyle(
                      color: Color(0xFF111827),
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : errorMessage != null
                            ? Center(child: Text(errorMessage!))
                            : SingleChildScrollView(
                                child: Column(
                                  children: [
                                    _section(
                                      title: '고객DB',
                                      icon: Icons.people_alt_rounded,
                                      pageTitle: '고객DB',
                                      rows: customers,
                                      headers: const [
                                        '가입일',
                                        '고객명',
                                        '휴대폰번호',
                                        '가입유형',
                                        '통신사/거래처',
                                        '모델명',
                                        '요금제',
                                        '담당자',
                                      ],
                                      widths: const [
                                        110,
                                        120,
                                        150,
                                        100,
                                        140,
                                        150,
                                        170,
                                        110,
                                      ],
                                      cells: (row) => [
                                        _tableText(_date(row['join_date'])),
                                        _tableText(row['name'], strong: true),
                                        _tableText(row['phone']),
                                        _tableBadge(row['join_type']),
                                        _tableBadge(
                                          row['carrier'],
                                          color: _carrierColor(row['carrier']),
                                        ),
                                        _tableText(row['model']),
                                        _tableText(row['plan']),
                                        _tableText(row['staff']),
                                      ],
                                      onTap: _showCustomerDetail,
                                    ),
                                    _section(
                                      title: '유선회원',
                                      icon: Icons.cable_rounded,
                                      pageTitle: '유선회원',
                                      rows: wiredMembers,
                                      headers: const [
                                        '청약일',
                                        '가입자',
                                        '번호',
                                        '통신사',
                                        '개통처',
                                        '판매자',
                                        '인터넷유형',
                                        '메모',
                                      ],
                                      widths: const [
                                        110,
                                        120,
                                        150,
                                        100,
                                        150,
                                        110,
                                        130,
                                        240,
                                      ],
                                      cells: (row) => [
                                        _tableText(
                                            _date(row['subscription_date'])),
                                        _tableText(row['subscriber'],
                                            strong: true),
                                        _tableText(row['phone']),
                                        _tableBadge(
                                          row['carrier'],
                                          color: _carrierColor(row['carrier']),
                                        ),
                                        _tableText(row['activation_center']),
                                        _tableText(row['seller']),
                                        _tableText(row['internet_type']),
                                        _tableText(row['memo']),
                                      ],
                                      onTap: _showWiredDetail,
                                    ),
                                    _section(
                                      title: '가망고객',
                                      icon: Icons.person_search_rounded,
                                      pageTitle: '가망고객',
                                      rows: leads,
                                      headers: const [
                                        '등록일',
                                        '가입자',
                                        '휴대폰번호',
                                        '담당자',
                                        '기존통신사',
                                        '변경통신사',
                                        '메모',
                                      ],
                                      widths: const [
                                        110,
                                        120,
                                        150,
                                        110,
                                        120,
                                        120,
                                        280,
                                      ],
                                      cells: (row) => [
                                        _tableText(_date(row['lead_date'])),
                                        _tableText(row['subscriber'],
                                            strong: true),
                                        _tableText(row['phone']),
                                        _tableText(row['manager']),
                                        _tableBadge(
                                          row['previous_carrier'],
                                          color: _carrierColor(
                                              row['previous_carrier']),
                                        ),
                                        _tableBadge(row['target_carrier'],
                                            color: _carrierColor(
                                                row['target_carrier'])),
                                        _tableText(row['memo']),
                                      ],
                                      onTap: _showLeadDetail,
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
