import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool isLoading = true;

  int totalCustomers = 0;
  int totalInventory = 0;
  int totalWiredMembers = 0;
  int totalRebate = 0;

  int dailyRebate = 0;
  int dailyTax = 0;
  int dailyMargin = 0;

  int monthlyRebate = 0;
  int monthlyTax = 0;
  int monthlyMargin = 0;

  final NumberFormat moneyFormat = NumberFormat('#,###');

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

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _isSameMonth(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month;
  }

  Future<void> loadDashboard() async {
    setState(() {
      isLoading = true;
    });

    try {
      final customers = await supabase.from('customers').select();
      final inventory = await supabase.from('device_inventory').select();
      final wired = await supabase.from('wired_members').select();

      final customerList = List<Map<String, dynamic>>.from(customers);
      final inventoryList = List<Map<String, dynamic>>.from(inventory);
      final wiredList = List<Map<String, dynamic>>.from(wired);

      int rebateSum = 0;
      int todayRebateSum = 0;
      int todayTaxSum = 0;
      int todayMarginSum = 0;
      int monthRebateSum = 0;
      int monthTaxSum = 0;
      int monthMarginSum = 0;

      final now = DateTime.now();

      for (final c in customerList) {
        final rebate = _toInt(c['total_rebate']);
        final tax = _toInt(c['tax']);
        final margin = _toInt(c['margin']);

        rebateSum += rebate;

        final baseDate =
            _parseDate(c['join_date']) ?? _parseDate(c['created_at']);
        if (baseDate != null) {
          if (_isSameDay(baseDate, now)) {
            todayRebateSum += rebate;
            todayTaxSum += tax;
            todayMarginSum += margin;
          }
          if (_isSameMonth(baseDate, now)) {
            monthRebateSum += rebate;
            monthTaxSum += tax;
            monthMarginSum += margin;
          }
        }
      }

      setState(() {
        totalCustomers = customerList.length;
        totalInventory = inventoryList.length;
        totalWiredMembers = wiredList.length;
        totalRebate = rebateSum;

        dailyRebate = todayRebateSum;
        dailyTax = todayTaxSum;
        dailyMargin = todayMarginSum;

        monthlyRebate = monthRebateSum;
        monthlyTax = monthTaxSum;
        monthlyMargin = monthMarginSum;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('대시보드 데이터 조회 실패: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Widget _card(String title, String value) {
    return Container(
      width: 220,
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
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: Color(0xFF111827),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF6B7280),
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFF111827),
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _moneyPanel(String title, int rebate, int tax, int margin) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
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
            const SizedBox(height: 18),
            _row('총리베이트', _money(rebate)),
            const SizedBox(height: 10),
            _row('세금', _money(tax)),
            const SizedBox(height: 10),
            _row('마진', _money(margin)),
          ],
        ),
      ),
    );
  }

  Widget _barItem(String label, int value, int maxValue) {
    final ratio = maxValue == 0 ? 0.0 : value / maxValue;
    return Column(
      children: [
        Text(
          moneyFormat.format(value),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF6B7280),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: 46,
          height: 180,
          alignment: Alignment.bottomCenter,
          child: Container(
            width: 46,
            height: (180 * ratio).clamp(8, 180).toDouble(),
            decoration: BoxDecoration(
              color: const Color(0xFFFF6FAE),
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: Color(0xFF111827),
          ),
        ),
      ],
    );
  }

  Widget _graphPanel() {
    final values = [
      dailyRebate,
      dailyTax,
      dailyMargin,
      monthlyRebate,
      monthlyTax,
      monthlyMargin,
    ];
    final maxValue = values.reduce((a, b) => a > b ? a : b);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE7E9EE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '정산 그래프',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 20),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _barItem('일 리베이트', dailyRebate, maxValue),
                const SizedBox(width: 18),
                _barItem('일 세금', dailyTax, maxValue),
                const SizedBox(width: 18),
                _barItem('일 마진', dailyMargin, maxValue),
                const SizedBox(width: 26),
                _barItem('월 리베이트', monthlyRebate, maxValue),
                const SizedBox(width: 18),
                _barItem('월 세금', monthlyTax, maxValue),
                const SizedBox(width: 18),
                _barItem('월 마진', monthlyMargin, maxValue),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('대시보드'),
        actions: [
          IconButton(
            onPressed: loadDashboard,
            icon: const Icon(Icons.refresh),
            tooltip: '새로고침',
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      _card('고객DB 고객 수', '$totalCustomers'),
                      _card('재고 수량', '$totalInventory'),
                      _card('유선회원 수', '$totalWiredMembers'),
                      _card('누적 총리베이트', _money(totalRebate)),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      _moneyPanel('일일 정산', dailyRebate, dailyTax, dailyMargin),
                      const SizedBox(width: 18),
                      _moneyPanel(
                          '월별 정산', monthlyRebate, monthlyTax, monthlyMargin),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _graphPanel(),
                ],
              ),
            ),
    );
  }
}
