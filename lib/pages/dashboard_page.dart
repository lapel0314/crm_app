import 'dart:io';

import 'package:crm_app/utils/store_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class DashboardPage extends StatefulWidget {
  final String role;
  final String currentStore;

  const DashboardPage({
    super.key,
    required this.role,
    required this.currentStore,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final NumberFormat moneyFormat = NumberFormat('#,###');

  bool isLoading = true;
  List<Map<String, dynamic>> customers = [];
  List<Map<String, dynamic>> wiredMembers = [];
  List<Map<String, dynamic>> leads = [];
  List<Map<String, dynamic>> inventory = [];

  int todayRebate = 0;
  int todayMargin = 0;
  int monthRebate = 0;
  int monthMargin = 0;

  bool _isCompactIosDialogContext(BuildContext context) {
    return !kIsWeb && Platform.isIOS && MediaQuery.of(context).size.width < 900;
  }

  @override
  void initState() {
    super.initState();
    loadDashboard();
  }

  int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    return int.tryParse(value.toString().replaceAll(',', '').trim()) ?? 0;
  }

  String _money(dynamic value) => '${moneyFormat.format(_toInt(value))}원';

  String _text(dynamic value) {
    if (value == null) return '-';
    final text = value.toString().trim();
    return text.isEmpty ? '-' : text;
  }

  String _normalizeCarrier(String value) {
    return value.toUpperCase().replaceAll(RegExp(r'[\s_-]'), '');
  }

  String _carrierLabel(dynamic value) {
    final carrier = _normalizeCarrier(_text(value));
    if (carrier.contains('SK')) return 'SK';
    if (carrier.contains('KT')) return 'KT';
    if (carrier.contains('LG')) return 'LG';
    return _text(value);
  }

  Color _carrierColor(dynamic value) {
    final carrier = _normalizeCarrier(_text(value));
    if (carrier.contains('SK')) return const Color(0xFF2563EB);
    if (carrier.contains('KT')) return const Color(0xFFEF4444);
    if (carrier.contains('LG')) return const Color(0xFFC94C6E);
    return const Color(0xFF6B7280);
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  String _shortDate(dynamic value) {
    final date = _parseDate(value);
    if (date == null) return '-';
    return DateFormat('yyyy-MM-dd').format(date);
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isSameMonth(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;

  DateTime? _customerDate(Map<String, dynamic> customer) {
    return _parseDate(customer['join_date']) ??
        _parseDate(customer['created_at']);
  }

  DateTime? _wiredDate(Map<String, dynamic> member) {
    return _parseDate(member['subscription_date']) ??
        _parseDate(member['created_at']);
  }

  int _customerTotalRebate(Map<String, dynamic> customer) {
    return _toInt(customer['rebate']) +
        _toInt(customer['hidden_rebate']) +
        _toInt(customer['add_rebate']);
  }

  int _customerMargin(Map<String, dynamic> customer) {
    return _customerTotalRebate(customer) -
        _toInt(customer['support_money']) -
        _toInt(customer['payment']) -
        _toInt(customer['deposit']);
  }

  int _wiredTotalRebate(Map<String, dynamic> member) {
    return _toInt(member['rebate']);
  }

  int _wiredMargin(Map<String, dynamic> member) {
    return _wiredTotalRebate(member) -
        _toInt(member['prepaid_amount']) -
        _toInt(member['postpaid_amount']);
  }

  List<Map<String, dynamic>> get todayCustomerSales {
    final now = DateTime.now();
    return customers.where((customer) {
      final date = _customerDate(customer);
      return date != null && _isSameDay(date, now);
    }).toList();
  }

  List<Map<String, dynamic>> get monthCustomerSales {
    final now = DateTime.now();
    return customers.where((customer) {
      final date = _customerDate(customer);
      return date != null && _isSameMonth(date, now);
    }).toList();
  }

  List<Map<String, dynamic>> get todayWiredSales {
    final now = DateTime.now();
    return wiredMembers.where((member) {
      final date = _wiredDate(member);
      return date != null && _isSameDay(date, now);
    }).toList();
  }

  List<Map<String, dynamic>> get monthWiredSales {
    final now = DateTime.now();
    return wiredMembers.where((member) {
      final date = _wiredDate(member);
      return date != null && _isSameMonth(date, now);
    }).toList();
  }

  bool get canViewAllStores => isPrivilegedRole(widget.role);

  List<Map<String, dynamic>> _filterStoreRows(List<Map<String, dynamic>> rows) {
    if (canViewAllStores) return rows;
    return rows
        .where((row) => isSameStore(row['store'], widget.currentStore))
        .toList();
  }

  List<Map<String, dynamic>> _buildSalesEntries({
    required List<Map<String, dynamic>> customerRows,
    required List<Map<String, dynamic>> wiredRows,
  }) {
    final entries = <Map<String, dynamic>>[];

    for (final customer in customerRows) {
      entries.add({
        'source': '고객DB',
        'date': _customerDate(customer),
        'dateText': _shortDate(customer['join_date']),
        'name': _text(customer['name']),
        'phone': _text(customer['phone']),
        'type': _text(customer['join_type']),
        'carrier': _text(customer['carrier']),
        'model': _text(customer['model']),
        'owner': _text(customer['staff']),
        'rebate': _customerTotalRebate(customer),
        'margin': _customerMargin(customer),
      });
    }

    for (final member in wiredRows) {
      entries.add({
        'source': '유선회원',
        'date': _wiredDate(member),
        'dateText': _shortDate(member['subscription_date']),
        'name': _text(member['subscriber']),
        'phone': _text(member['phone']),
        'type': _text(member['internet_type']),
        'carrier': _text(member['carrier']),
        'model': _text(member['activation_center']),
        'owner': _text(member['seller']),
        'rebate': _wiredTotalRebate(member),
        'margin': _wiredMargin(member),
      });
    }

    entries.sort((a, b) {
      final aDate = a['date'] as DateTime?;
      final bDate = b['date'] as DateTime?;
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return bDate.compareTo(aDate);
    });

    return entries;
  }

  Future<void> loadDashboard() async {
    setState(() {
      isLoading = true;
    });

    try {
      final result = await Future.wait<List<dynamic>>([
        supabase.from('customers').select(),
        supabase.from('device_inventory').select(),
        supabase.from('wired_members').select(),
        supabase.from('leads').select(),
      ]);

      final customerList = _filterStoreRows(
        result[0].map((e) => Map<String, dynamic>.from(e)).toList(),
      );
      final inventoryList = _filterStoreRows(
        result[1].map((e) => Map<String, dynamic>.from(e)).toList(),
      );
      final wiredList = _filterStoreRows(
        result[2].map((e) => Map<String, dynamic>.from(e)).toList(),
      );
      final leadList = _filterStoreRows(
        result[3].map((e) => Map<String, dynamic>.from(e)).toList(),
      );

      final now = DateTime.now();
      var dailyRebateSum = 0;
      var dailyMarginSum = 0;
      var monthlyRebateSum = 0;
      var monthlyMarginSum = 0;

      for (final customer in customerList) {
        final rebate = _customerTotalRebate(customer);
        final margin = _customerMargin(customer);
        final date = _customerDate(customer);

        if (date != null && _isSameDay(date, now)) {
          dailyRebateSum += rebate;
          dailyMarginSum += margin;
        }
        if (date != null && _isSameMonth(date, now)) {
          monthlyRebateSum += rebate;
          monthlyMarginSum += margin;
        }
      }

      for (final member in wiredList) {
        final rebate = _wiredTotalRebate(member);
        final margin = _wiredMargin(member);
        final date = _wiredDate(member);

        if (date != null && _isSameDay(date, now)) {
          dailyRebateSum += rebate;
          dailyMarginSum += margin;
        }
        if (date != null && _isSameMonth(date, now)) {
          monthlyRebateSum += rebate;
          monthlyMarginSum += margin;
        }
      }

      if (!mounted) return;
      setState(() {
        customers = customerList;
        inventory = inventoryList;
        wiredMembers = wiredList;
        leads = leadList;
        todayRebate = dailyRebateSum;
        todayMargin = dailyMarginSum;
        monthRebate = monthlyRebateSum;
        monthMargin = monthlyMarginSum;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
      });
      debugPrint('dashboard load failed: $e');
    }
  }

  Widget _metricCard({
    required String title,
    required String value,
    required String caption,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
    bool expanded = true,
  }) {
    final mobile = MediaQuery.of(context).size.width < 900;
    final card = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: mobile ? 156 : 146,
        padding: const EdgeInsets.all(20),
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
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 18, color: color),
                ),
                const Spacer(),
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              value,
              style: const TextStyle(
                color: Color(0xFF111827),
                fontSize: 26,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              caption,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: mobile ? 11 : 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );

    if (expanded) {
      return Expanded(child: card);
    }

    return card;
  }

  Widget _panel({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
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
              color: Color(0xFF111827),
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xFF9CA3AF),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }

  Map<int, int> _monthlyCounts() {
    final counts = {for (var month = 1; month <= 12; month++) month: 0};
    final now = DateTime.now();
    for (final customer in customers) {
      final date = _customerDate(customer);
      if (date != null && date.year == now.year) {
        counts[date.month] = (counts[date.month] ?? 0) + 1;
      }
    }
    return counts;
  }

  Widget _monthlyTrend() {
    final counts = _monthlyCounts();
    final maxCount = counts.values.fold<int>(0, (a, b) => a > b ? a : b);
    const monthColors = [
      Color(0xFF2563EB),
      Color(0xFF10B981),
      Color(0xFFF59E0B),
      Color(0xFFC94C6E),
      Color(0xFFEF4444),
      Color(0xFF8B5CF6),
    ];

    return SizedBox(
      height: 230,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: counts.entries.map((entry) {
          final ratio = maxCount == 0 ? 0.0 : entry.value / maxCount;
          final barColor = monthColors[(entry.key - 1) % monthColors.length];
          return Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  '${entry.value}건',
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 22,
                  height: (150 * ratio).clamp(8, 150).toDouble(),
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '${entry.key}월',
                  style: const TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  List<MapEntry<String, int>> _carrierEntries(String source) {
    final carriers = <String, int>{};
    final includeCustomers = source == '전체' || source == '고객DB';
    final includeWired = source == '전체' || source == '유선회원';

    if (includeCustomers) {
      for (final customer in customers) {
        final carrier = _carrierLabel(customer['carrier']);
        if (carrier == '-') continue;
        carriers[carrier] = (carriers[carrier] ?? 0) + 1;
      }
    }

    if (includeWired) {
      for (final member in wiredMembers) {
        final carrier = _carrierLabel(member['carrier']);
        if (carrier == '-') continue;
        carriers[carrier] = (carriers[carrier] ?? 0) + 1;
      }
    }

    final sorted = carriers.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted;
  }

  Widget _sourceChips({
    required String selected,
    required ValueChanged<String> onSelected,
  }) {
    const sources = ['전체', '고객DB', '유선회원'];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: sources.map((source) {
        final active = selected == source;
        return InkWell(
          onTap: () => onSelected(source),
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: active
                  ? const Color(0xFFC94C6E).withValues(alpha: 0.10)
                  : const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color:
                    active ? const Color(0xFFC94C6E) : const Color(0xFFE5E7EB),
              ),
            ),
            child: Text(
              source,
              style: TextStyle(
                color:
                    active ? const Color(0xFFC94C6E) : const Color(0xFF6B7280),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _carrierSharePanel() {
    return StatefulBuilder(
      builder: (context, setPanelState) {
        var selectedSource = '전체';
        return StatefulBuilder(
          builder: (context, setInnerState) {
            final rows = _carrierEntries(selectedSource);
            final maxCount = rows.isEmpty ? 0 : rows.first.value;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sourceChips(
                  selected: selectedSource,
                  onSelected: (value) =>
                      setInnerState(() => selectedSource = value),
                ),
                const SizedBox(height: 18),
                if (rows.isEmpty)
                  const SizedBox(
                    height: 182,
                    child: Center(child: Text('통신사 데이터가 없습니다')),
                  )
                else
                  SizedBox(
                    height: 182,
                    child: Column(
                      children: rows.take(5).map((entry) {
                        final ratio =
                            maxCount == 0 ? 0.0 : entry.value / maxCount;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 18),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 82,
                                child: Text(
                                  entry.key,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF374151),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(99),
                                  child: LinearProgressIndicator(
                                    minHeight: 14,
                                    value: ratio,
                                    backgroundColor: const Color(0xFFF3F4F6),
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      _carrierColor(entry.key),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 48,
                                child: Text(
                                  '${entry.value}건',
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    color: Color(0xFF111827),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  String _monthKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}';

  String _monthLabel(String monthKey) {
    final parts = monthKey.split('-');
    if (parts.length != 2) return monthKey;
    return '${parts[0]}년 ${parts[1]}월';
  }

  List<String> _availableSettlementMonths() {
    final months = <String>{};

    for (final customer in customers) {
      final date = _customerDate(customer);
      if (date != null) months.add(_monthKey(date));
    }

    for (final member in wiredMembers) {
      final date = _wiredDate(member);
      if (date != null) months.add(_monthKey(date));
    }

    final sorted = months.toList();
    sorted.sort((a, b) => b.compareTo(a));
    return sorted;
  }

  List<Map<String, dynamic>> _customerRowsForMonth(String monthKey) {
    return customers.where((customer) {
      final date = _customerDate(customer);
      return date != null && _monthKey(date) == monthKey;
    }).toList();
  }

  List<Map<String, dynamic>> _wiredRowsForMonth(String monthKey) {
    return wiredMembers.where((member) {
      final date = _wiredDate(member);
      return date != null && _monthKey(date) == monthKey;
    }).toList();
  }

  Map<String, String> _bankInfoParts(dynamic value) {
    final text = _text(value);
    if (text == '-') {
      return const {'bank': '-', 'account': '-', 'holder': '-'};
    }

    final parts = text
        .split(RegExp(r'\s*/\s*|\s+'))
        .where((part) => part.trim().isNotEmpty)
        .toList();

    return {
      'bank': parts.isNotEmpty ? parts[0] : '-',
      'account': parts.length > 1 ? parts[1] : '-',
      'holder': parts.length > 2 ? parts[2] : '-',
    };
  }

  Widget _settlementActionRow({
    required String label,
    required int value,
    required Color color,
    VoidCallback? onTap,
  }) {
    final content = Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: onTap != null
                    ? const Color(0xFF111827)
                    : const Color(0xFF6B7280),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _money(value),
            style: const TextStyle(
              color: Color(0xFF111827),
              fontWeight: FontWeight.w900,
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 6),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFF9CA3AF),
              size: 18,
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return content;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: content,
      ),
    );
  }

  Widget _advanceDetailField(String label, dynamic value,
      {bool strong = false}) {
    final mobile = MediaQuery.of(context).size.width < 900;
    return SizedBox(
      width: mobile ? 118 : 132,
      child: Column(
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
          const SizedBox(height: 4),
          Text(
            _text(value),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: strong ? const Color(0xFF111827) : const Color(0xFF374151),
              fontSize: 13,
              fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _advanceDetailRow(
    Map<String, dynamic> customer,
    String amountLabel,
    String amountKey,
  ) {
    final bankInfo = _bankInfoParts(customer['bank_info']);
    final mobile = MediaQuery.of(context).size.width < 900;

    return Container(
      padding: EdgeInsets.symmetric(vertical: mobile ? 10 : 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: Wrap(
        spacing: mobile ? 10 : 16,
        runSpacing: mobile ? 10 : 8,
        children: [
          _advanceDetailField('고객명', customer['name'], strong: true),
          _advanceDetailField('휴대폰번호', customer['phone']),
          _advanceDetailField(amountLabel, _money(customer[amountKey]),
              strong: true),
          _advanceDetailField('은행', bankInfo['bank']),
          _advanceDetailField('계좌', bankInfo['account']),
          _advanceDetailField('예금주', bankInfo['holder']),
          _advanceDetailField('메모', customer['memo']),
        ],
      ),
    );
  }

  void _showAdvanceDetailDialog({
    required String title,
    required String monthKey,
    required String amountLabel,
    required String amountKey,
  }) {
    final rows = _customerRowsForMonth(monthKey)
        .where((customer) => _toInt(customer[amountKey]) > 0)
        .toList()
      ..sort((a, b) {
        final aDate = _customerDate(a);
        final bDate = _customerDate(b);
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return bDate.compareTo(aDate);
      });
    final totalAmount =
        rows.fold<int>(0, (sum, row) => sum + _toInt(row[amountKey]));
    final mobile = MediaQuery.of(context).size.width < 900;

    showDialog(
      context: context,
      builder: (dialogContext) {
        final compactIos = _isCompactIosDialogContext(dialogContext);
        final screenSize = MediaQuery.of(dialogContext).size;

        final summary = mobile
            ? GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.7,
                children: [
                  _mobileDialogSummary('건수', '${rows.length}건'),
                  _mobileDialogSummary(amountLabel, _money(totalAmount)),
                  _mobileDialogSummary('기준월', _monthLabel(monthKey)),
                  _mobileDialogSummary('구분', title),
                ],
              )
            : Row(
                children: [
                  _dialogSummary('건수', '${rows.length}건'),
                  const SizedBox(width: 10),
                  _dialogSummary(amountLabel, _money(totalAmount)),
                  const SizedBox(width: 10),
                  _dialogSummary('기준월', _monthLabel(monthKey)),
                ],
              );

        final list = rows.isEmpty
            ? const Center(child: Text('해당 월 데이터가 없습니다'))
            : SingleChildScrollView(
                child: Column(
                  children: rows
                      .map((row) =>
                          _advanceDetailRow(row, amountLabel, amountKey))
                      .toList(),
                ),
              );

        if (mobile) {
          return AlertDialog(
            insetPadding: EdgeInsets.symmetric(
              horizontal: compactIos ? 10 : 12,
              vertical: compactIos ? 14 : 18,
            ),
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            titlePadding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
            contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            title: Text(
              '$title 상세',
              style: const TextStyle(
                color: Color(0xFF111827),
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: compactIos ? screenSize.height * 0.72 : 580,
              child: Column(
                children: [
                  summary,
                  const SizedBox(height: 14),
                  Expanded(child: list)
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('닫기'),
              ),
            ],
          );
        }

        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          title: Text(
            '$title 상세',
            style: const TextStyle(
              color: Color(0xFF111827),
              fontWeight: FontWeight.w900,
            ),
          ),
          content: SizedBox(
            width: 980,
            height: 600,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                summary,
                const SizedBox(height: 14),
                Expanded(child: list)
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('닫기'),
            ),
          ],
        );
      },
    );
  }

  Widget _settlementPanel() {
    final availableMonths = _availableSettlementMonths();
    final currentMonth = _monthKey(DateTime.now());
    final initialMonth = availableMonths.contains(currentMonth)
        ? currentMonth
        : (availableMonths.isNotEmpty ? availableMonths.first : currentMonth);

    return StatefulBuilder(
      builder: (context, setPanelState) {
        var selectedMonth = initialMonth;

        return StatefulBuilder(
          builder: (context, setInnerState) {
            final monthCustomerRows = _customerRowsForMonth(selectedMonth);
            final monthWiredRows = _wiredRowsForMonth(selectedMonth);
            final monthTotalRebate = monthCustomerRows.fold<int>(
                    0, (sum, row) => sum + _customerTotalRebate(row)) +
                monthWiredRows.fold<int>(
                    0, (sum, row) => sum + _wiredTotalRebate(row));
            final monthTotalMargin = monthCustomerRows.fold<int>(
                    0, (sum, row) => sum + _customerMargin(row)) +
                monthWiredRows.fold<int>(
                    0, (sum, row) => sum + _wiredMargin(row));
            final monthSupportMoney = monthCustomerRows.fold<int>(
              0,
              (sum, row) => sum + _toInt(row['support_money']),
            );
            final monthPayment = monthCustomerRows.fold<int>(
              0,
              (sum, row) => sum + _toInt(row['payment']),
            );
            final monthDeposit = monthCustomerRows.fold<int>(
              0,
              (sum, row) => sum + _toInt(row['deposit']),
            );

            return _panel(
              title: '정산 현황',
              subtitle: '고객DB + 유선회원 합산 기준',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _settlementActionRow(
                    label: '오늘 총 리베이트',
                    value: todayRebate,
                    color: const Color(0xFF3B82F6),
                  ),
                  _settlementActionRow(
                    label: '오늘 총 마진',
                    value: todayMargin,
                    color: const Color(0xFF10B981),
                  ),
                  const Divider(height: 24),
                  if (availableMonths.isNotEmpty) ...[
                    const Text(
                      '월 선택',
                      style: TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: availableMonths.map((month) {
                        final active = selectedMonth == month;
                        return InkWell(
                          onTap: () =>
                              setInnerState(() => selectedMonth = month),
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: active
                                  ? const Color(0xFF111827)
                                      .withValues(alpha: 0.08)
                                  : const Color(0xFFF9FAFB),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: active
                                    ? const Color(0xFF111827)
                                    : const Color(0xFFE5E7EB),
                              ),
                            ),
                            child: Text(
                              _monthLabel(month),
                              style: TextStyle(
                                color: active
                                    ? const Color(0xFF111827)
                                    : const Color(0xFF6B7280),
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),
                  ],
                  _settlementActionRow(
                    label: '${_monthLabel(selectedMonth)} 총 리베이트',
                    value: monthTotalRebate,
                    color: const Color(0xFF3B82F6),
                  ),
                  _settlementActionRow(
                    label: '${_monthLabel(selectedMonth)} 총 마진',
                    value: monthTotalMargin,
                    color: const Color(0xFF10B981),
                  ),
                  const Divider(height: 24),
                  _settlementActionRow(
                    label: '대납 · 유통망지원금',
                    value: monthSupportMoney,
                    color: const Color(0xFFC94C6E),
                    onTap: () => _showAdvanceDetailDialog(
                      title: '유통망지원금',
                      monthKey: selectedMonth,
                      amountLabel: '유통망지원금',
                      amountKey: 'support_money',
                    ),
                  ),
                  _settlementActionRow(
                    label: '대납 · 결제',
                    value: monthPayment,
                    color: const Color(0xFFF59E0B),
                    onTap: () => _showAdvanceDetailDialog(
                      title: '결제',
                      monthKey: selectedMonth,
                      amountLabel: '결제',
                      amountKey: 'payment',
                    ),
                  ),
                  _settlementActionRow(
                    label: '대납 · 입금',
                    value: monthDeposit,
                    color: const Color(0xFF2563EB),
                    onTap: () => _showAdvanceDetailDialog(
                      title: '입금',
                      monthKey: selectedMonth,
                      amountLabel: '입금',
                      amountKey: 'deposit',
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  List<MapEntry<String, int>> _monthlyModelRanking() {
    final modelCounts = <String, int>{};
    for (final customer in monthCustomerSales) {
      final model = _text(customer['model']);
      if (model == '-') continue;
      modelCounts[model] = (modelCounts[model] ?? 0) + 1;
    }
    return modelCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
  }

  List<Map<String, dynamic>> _monthlyModelRows(String model) {
    final rows = monthCustomerSales
        .where((customer) => _text(customer['model']) == model)
        .toList();
    rows.sort((a, b) {
      final aDate = _customerDate(a);
      final bDate = _customerDate(b);
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return bDate.compareTo(aDate);
    });
    return rows;
  }

  void _showModelSalesDialog(String model) {
    final rows = _monthlyModelRows(model);
    final totalRebate =
        rows.fold<int>(0, (sum, row) => sum + _customerTotalRebate(row));
    final totalMargin =
        rows.fold<int>(0, (sum, row) => sum + _customerMargin(row));
    final mobile = MediaQuery.of(context).size.width < 900;

    showDialog(
      context: context,
      builder: (dialogContext) {
        final compactIos = _isCompactIosDialogContext(dialogContext);
        final screenSize = MediaQuery.of(dialogContext).size;

        Widget summary() {
          if (mobile) {
            return GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.7,
              children: [
                _mobileDialogSummary('판매건', '${rows.length}건'),
                _mobileDialogSummary('리베이트', _money(totalRebate)),
                _mobileDialogSummary('마진', _money(totalMargin)),
                _mobileDialogSummary('판매모델', model),
              ],
            );
          }

          return Row(
            children: [
              _dialogSummary('판매건', '${rows.length}건'),
              const SizedBox(width: 10),
              _dialogSummary('리베이트', _money(totalRebate)),
              const SizedBox(width: 10),
              _dialogSummary('마진', _money(totalMargin)),
            ],
          );
        }

        Widget list() {
          if (rows.isEmpty) {
            return const Center(child: Text('해당 모델 판매 데이터가 없습니다'));
          }

          return SingleChildScrollView(
            child: Column(
              children: rows.map((row) {
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      _popupField('개통일', _shortDate(row['join_date'])),
                      _popupField('고객명', row['name'], strong: true),
                      _popupField('휴대폰', row['phone']),
                      _popupField('통신사', row['carrier']),
                      _popupField('담당자', row['staff']),
                      _popupField('리베이트', _money(_customerTotalRebate(row)),
                          strong: true),
                      _popupField('마진', _money(_customerMargin(row)),
                          strong: true),
                    ],
                  ),
                );
              }).toList(),
            ),
          );
        }

        if (mobile) {
          return AlertDialog(
            insetPadding: EdgeInsets.symmetric(
              horizontal: compactIos ? 10 : 12,
              vertical: compactIos ? 14 : 18,
            ),
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            titlePadding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
            contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            title: Text(
              '$model 판매 카드',
              style: const TextStyle(
                color: Color(0xFF111827),
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: compactIos ? screenSize.height * 0.72 : 580,
              child: Column(
                children: [
                  summary(),
                  const SizedBox(height: 14),
                  Expanded(child: list())
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('닫기'),
              ),
            ],
          );
        }

        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          title: Text(
            '$model 판매 카드',
            style: const TextStyle(
              color: Color(0xFF111827),
              fontWeight: FontWeight.w900,
            ),
          ),
          content: SizedBox(
            width: 980,
            height: 600,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                summary(),
                const SizedBox(height: 14),
                Expanded(child: list())
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('닫기'),
            ),
          ],
        );
      },
    );
  }

  Widget _modelRankingPanel() {
    final rows = _monthlyModelRanking();
    final maxCount = rows.isEmpty ? 0 : rows.first.value;

    return _panel(
      title: '이번달 모델명 순위',
      subtitle: '고객 DB 개통일 기준 판매 모델 TOP 5',
      child: rows.isEmpty
          ? const SizedBox(
              height: 120,
              child: Center(child: Text('이번달 판매 모델 데이터가 없습니다')),
            )
          : Column(
              children: rows.take(5).toList().asMap().entries.map((item) {
                final index = item.key;
                final entry = item.value;
                final ratio = maxCount == 0 ? 0.0 : entry.value / maxCount;
                final colors = [
                  const Color(0xFFC94C6E),
                  const Color(0xFF2563EB),
                  const Color(0xFFEF4444),
                  const Color(0xFF10B981),
                  const Color(0xFFF59E0B),
                ];
                final color = colors[index % colors.length];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => _showModelSalesDialog(entry.key),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 6,
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 24,
                                  height: 24,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${index + 1}',
                                    style: TextStyle(
                                      color: color,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    entry.key,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFF111827),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  '${entry.value}건',
                                  style: TextStyle(
                                    color: color,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.open_in_new_rounded,
                                  size: 15,
                                  color: Color(0xFF9CA3AF),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(99),
                              child: LinearProgressIndicator(
                                minHeight: 10,
                                value: ratio,
                                backgroundColor: const Color(0xFFF3F4F6),
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(color),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _popupField(String label, dynamic value, {bool strong = false}) {
    final mobile = MediaQuery.of(context).size.width < 900;
    return SizedBox(
      width: mobile ? 122 : 150,
      child: Column(
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
          const SizedBox(height: 4),
          Text(
            _text(value),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: strong ? const Color(0xFF10B981) : const Color(0xFF111827),
              fontSize: 13,
              fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _salesPopupRow(Map<String, dynamic> row) {
    final mobile = MediaQuery.of(context).size.width < 900;
    return Container(
      padding: EdgeInsets.symmetric(vertical: mobile ? 10 : 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: Wrap(
        spacing: mobile ? 10 : 16,
        runSpacing: mobile ? 10 : 8,
        children: [
          _popupField('구분', row['source']),
          _popupField('일자', row['dateText']),
          _popupField('이름', row['name'], strong: true),
          _popupField('번호', row['phone']),
          _popupField('유형', row['type']),
          _popupField('통신사', row['carrier']),
          _popupField(row['source'] == '유선회원' ? '개통처' : '모델명', row['model']),
          _popupField(row['source'] == '유선회원' ? '판매자' : '담당자', row['owner']),
          _popupField('리베이트', _money(row['rebate']), strong: true),
          _popupField('마진', _money(row['margin']), strong: true),
        ],
      ),
    );
  }

  Widget _dialogSummary(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE8E9EF)),
        ),
        child: Column(
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
        ),
      ),
    );
  }

  Widget _mobileDialogSummary(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE8E9EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF111827),
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  void _showSalesDialog({
    required String title,
    required List<Map<String, dynamic>> customerRows,
    required List<Map<String, dynamic>> wiredRows,
  }) {
    final allRows = _buildSalesEntries(
      customerRows: customerRows,
      wiredRows: wiredRows,
    );
    final mobile = MediaQuery.of(context).size.width < 900;

    showDialog(
      context: context,
      builder: (dialogContext) {
        var selectedSource = '전체';

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filteredRows = selectedSource == '전체'
                ? allRows
                : allRows
                    .where((row) => row['source'] == selectedSource)
                    .toList();
            final rebate = filteredRows.fold<int>(
              0,
              (sum, row) => sum + _toInt(row['rebate']),
            );
            final margin = filteredRows.fold<int>(
              0,
              (sum, row) => sum + _toInt(row['margin']),
            );
            final compactIos = _isCompactIosDialogContext(dialogContext);
            final screenSize = MediaQuery.of(dialogContext).size;

            if (mobile) {
              return AlertDialog(
                insetPadding: EdgeInsets.symmetric(
                  horizontal: compactIos ? 10 : 12,
                  vertical: compactIos ? 14 : 18,
                ),
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                titlePadding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                title: Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                content: SizedBox(
                  width: double.maxFinite,
                  height: compactIos ? screenSize.height * 0.72 : 580,
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _sourceChips(
                          selected: selectedSource,
                          onSelected: (value) =>
                              setDialogState(() => selectedSource = value),
                        ),
                      ),
                      const SizedBox(height: 14),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 1.7,
                        children: [
                          _mobileDialogSummary(
                              '개통건', '${filteredRows.length}건'),
                          _mobileDialogSummary('리베이트', _money(rebate)),
                          _mobileDialogSummary('마진', _money(margin)),
                          _mobileDialogSummary('선택', selectedSource),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Expanded(
                        child: filteredRows.isEmpty
                            ? const Center(child: Text('해당 기간 개통건이 없습니다'))
                            : SingleChildScrollView(
                                child: Column(
                                  children:
                                      filteredRows.map(_salesPopupRow).toList(),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('닫기'),
                  ),
                ],
              );
            }

            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              title: Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF111827),
                  fontWeight: FontWeight.w900,
                ),
              ),
              content: SizedBox(
                width: 980,
                height: 600,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sourceChips(
                      selected: selectedSource,
                      onSelected: (value) =>
                          setDialogState(() => selectedSource = value),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _dialogSummary('개통건', '${filteredRows.length}건'),
                        const SizedBox(width: 10),
                        _dialogSummary('리베이트', _money(rebate)),
                        const SizedBox(width: 10),
                        _dialogSummary('마진', _money(margin)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: filteredRows.isEmpty
                          ? const Center(child: Text('해당 기간 개통건이 없습니다'))
                          : SingleChildScrollView(
                              child: Column(
                                children:
                                    filteredRows.map(_salesPopupRow).toList(),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('닫기'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final todayCount = todayCustomerSales.length + todayWiredSales.length;
    final monthCount = monthCustomerSales.length + monthWiredSales.length;
    final modelRankCount = _monthlyModelRanking().length;
    final mobile = MediaQuery.of(context).size.width < 900;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: loadDashboard,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.all(mobile ? 14 : 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (mobile) ...[
                      _metricCard(
                        title: '오늘 개통',
                        value: '$todayCount건',
                        caption: '고객DB + 유선회원 합산 보기',
                        icon: Icons.phone_iphone_rounded,
                        color: const Color(0xFF3B82F6),
                        onTap: () => _showSalesDialog(
                          title: '오늘 개통',
                          customerRows: todayCustomerSales,
                          wiredRows: todayWiredSales,
                        ),
                        expanded: false,
                      ),
                      const SizedBox(height: 12),
                      _metricCard(
                        title: '이번달 개통',
                        value: '$monthCount건',
                        caption: '고객DB + 유선회원 합산 보기',
                        icon: Icons.trending_up_rounded,
                        color: const Color(0xFF10B981),
                        onTap: () => _showSalesDialog(
                          title: '이번달 개통',
                          customerRows: monthCustomerSales,
                          wiredRows: monthWiredSales,
                        ),
                        expanded: false,
                      ),
                      const SizedBox(height: 12),
                      _metricCard(
                        title: '판매 모델',
                        value: '$modelRankCount종',
                        caption: '이번달 판매 모델 수',
                        icon: Icons.leaderboard_rounded,
                        color: const Color(0xFFF59E0B),
                        expanded: false,
                      ),
                      const SizedBox(height: 24),
                      _panel(
                        title: '월별 개통 추이',
                        subtitle: '${DateTime.now().year}년 월별 고객 DB 개통 현황',
                        child: _monthlyTrend(),
                      ),
                      const SizedBox(height: 24),
                      _panel(
                        title: '통신사 비중',
                        subtitle: '고객DB + 유선회원 필터 보기',
                        child: _carrierSharePanel(),
                      ),
                      const SizedBox(height: 24),
                      _modelRankingPanel(),
                      const SizedBox(height: 24),
                      _settlementPanel(),
                    ] else ...[
                      Row(
                        children: [
                          _metricCard(
                            title: '오늘 개통',
                            value: '$todayCount건',
                            caption: '고객DB + 유선회원 합산 보기',
                            icon: Icons.phone_iphone_rounded,
                            color: const Color(0xFF3B82F6),
                            onTap: () => _showSalesDialog(
                              title: '오늘 개통',
                              customerRows: todayCustomerSales,
                              wiredRows: todayWiredSales,
                            ),
                          ),
                          const SizedBox(width: 16),
                          _metricCard(
                            title: '이번달 개통',
                            value: '$monthCount건',
                            caption: '고객DB + 유선회원 합산 보기',
                            icon: Icons.trending_up_rounded,
                            color: const Color(0xFF10B981),
                            onTap: () => _showSalesDialog(
                              title: '이번달 개통',
                              customerRows: monthCustomerSales,
                              wiredRows: monthWiredSales,
                            ),
                          ),
                          const SizedBox(width: 16),
                          _metricCard(
                            title: '판매 모델',
                            value: '$modelRankCount종',
                            caption: '이번달 판매 모델 수',
                            icon: Icons.leaderboard_rounded,
                            color: const Color(0xFFF59E0B),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 2,
                            child: _panel(
                              title: '월별 개통 추이',
                              subtitle:
                                  '${DateTime.now().year}년 월별 고객 DB 개통 현황',
                              child: _monthlyTrend(),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _panel(
                              title: '통신사 비중',
                              subtitle: '고객DB + 유선회원 필터 보기',
                              child: _carrierSharePanel(),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _modelRankingPanel()),
                          const SizedBox(width: 16),
                          Expanded(child: _settlementPanel()),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      '재고 ${inventory.length}대 · 유선회원 ${wiredMembers.length}건',
                      style: const TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
