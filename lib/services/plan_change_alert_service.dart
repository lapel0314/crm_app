import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:crm_app/utils/store_utils.dart';

enum PlanChangeAlertType {
  addServiceDelete('부가서비스삭제'),
  selectivePlanChange('선택약정 요금제변경'),
  publicSubsidy('공시지원금'),
  selectiveWithSupport('선택약정+지원금');

  final String label;

  const PlanChangeAlertType(this.label);
}

class PlanChangeAlertEntry {
  final Map<String, dynamic> customer;
  final String carrier;
  final PlanChangeAlertType type;
  final DateTime dueDate;

  const PlanChangeAlertEntry({
    required this.customer,
    required this.carrier,
    required this.type,
    required this.dueDate,
  });

  String get customerId => (customer['id'] ?? '').toString();
  String get customerName => _text(customer['name']);
  String get phone => _text(customer['phone']);
  String get store => _text(customer['store']);
  String get staff => _text(customer['staff']);
  String get plan => _text(customer['plan']);
  String get addService => _text(customer['add_service']);
  String get contractType => _text(customer['contract_type']);
  String get joinDateLabel {
    final date = PlanChangeAlertService.parseDate(customer['join_date']);
    return date == null ? '-' : DateFormat('yyyy-MM-dd').format(date);
  }
}

class PlanChangeAlertResult {
  final DateTime date;
  final List<PlanChangeAlertEntry> entries;

  const PlanChangeAlertResult({
    required this.date,
    required this.entries,
  });

  int get totalEntries => entries.length;

  List<Map<String, dynamic>> get uniqueCustomers {
    final seen = <String>{};
    final rows = <Map<String, dynamic>>[];
    for (final entry in entries) {
      final id = entry.customerId;
      if (id.isNotEmpty && !seen.add(id)) continue;
      rows.add(entry.customer);
    }
    return rows;
  }

  Map<String, Map<PlanChangeAlertType, List<PlanChangeAlertEntry>>>
      get grouped {
    final result =
        <String, Map<PlanChangeAlertType, List<PlanChangeAlertEntry>>>{};
    for (final entry in entries) {
      final byType = result.putIfAbsent(entry.carrier, () => {});
      byType.putIfAbsent(entry.type, () => []).add(entry);
    }
    return result;
  }
}

class PlanChangeAlertService {
  final SupabaseClient supabase;

  const PlanChangeAlertService(this.supabase);

  static final List<String> carrierOrder = ['SK', 'KT', 'LG'];
  static final List<PlanChangeAlertType> typeOrder = [
    PlanChangeAlertType.addServiceDelete,
    PlanChangeAlertType.selectivePlanChange,
    PlanChangeAlertType.publicSubsidy,
    PlanChangeAlertType.selectiveWithSupport,
  ];

  Future<PlanChangeAlertResult> fetchTodayAlerts({
    required String role,
    required String currentStore,
    DateTime? now,
  }) async {
    final today = _dateOnly(now ?? DateTime.now());
    if (!canUseCustomerDb(role)) {
      return PlanChangeAlertResult(date: today, entries: const []);
    }

    final rows = await supabase
        .from('customers')
        .select()
        .eq('is_deleted', false)
        .order('join_date', ascending: true)
        .order('created_at', ascending: true);

    final entries = <PlanChangeAlertEntry>[];
    for (final row in rows) {
      final customer = Map<String, dynamic>.from(row as Map);
      if (!includesStoreForRole(
        role: role,
        currentStore: currentStore,
        rowStore: customer['store'],
      )) {
        continue;
      }
      entries.addAll(entriesForCustomer(customer: customer, today: today));
    }

    entries.sort(_compareEntries);
    return PlanChangeAlertResult(date: today, entries: entries);
  }

  static List<PlanChangeAlertEntry> entriesForCustomer({
    required Map<String, dynamic> customer,
    required DateTime today,
  }) {
    final joinDate = parseDate(customer['join_date']);
    if (joinDate == null) return const [];

    final carrier = normalizeCarrier(customer['carrier']);
    if (carrier == null) return const [];

    final normalizedToday = _dateOnly(today);
    final normalizedJoinDate = _dateOnly(joinDate);
    final entries = <PlanChangeAlertEntry>[];

    void addIfDue(PlanChangeAlertType type, DateTime dueDate) {
      final normalizedDueDate = _dateOnly(dueDate);
      if (!_sameDate(normalizedDueDate, normalizedToday)) return;
      entries.add(
        PlanChangeAlertEntry(
          customer: customer,
          carrier: carrier,
          type: type,
          dueDate: normalizedDueDate,
        ),
      );
    }

    if (hasActiveAddService(customer['add_service'])) {
      switch (carrier) {
        case 'SK':
          addIfDue(
            PlanChangeAlertType.addServiceDelete,
            DateTime(normalizedJoinDate.year, normalizedJoinDate.month + 1, 1),
          );
        case 'KT':
          addIfDue(
            PlanChangeAlertType.addServiceDelete,
            DateTime(normalizedJoinDate.year, normalizedJoinDate.month + 4, 1),
          );
        case 'LG':
          addIfDue(
            PlanChangeAlertType.addServiceDelete,
            normalizedJoinDate.add(const Duration(days: 93)),
          );
      }
    }

    final planType = planChangeType(customer);
    if (planType == null) return entries;

    switch (carrier) {
      case 'SK':
        addIfDue(
          planType == PlanChangeAlertType.selectivePlanChange
              ? PlanChangeAlertType.selectivePlanChange
              : planType,
          planType == PlanChangeAlertType.selectivePlanChange
              ? DateTime(
                  normalizedJoinDate.year,
                  normalizedJoinDate.month + 5,
                  1,
                )
              : normalizedJoinDate.add(const Duration(days: 183)),
        );
      case 'KT':
        addIfDue(
          planType,
          planType == PlanChangeAlertType.selectivePlanChange
              ? normalizedJoinDate.add(const Duration(days: 122))
              : normalizedJoinDate.add(const Duration(days: 183)),
        );
      case 'LG':
        addIfDue(
          planType,
          planType == PlanChangeAlertType.selectivePlanChange
              ? normalizedJoinDate.add(const Duration(days: 93))
              : normalizedJoinDate.add(const Duration(days: 183)),
        );
    }

    return entries;
  }

  static PlanChangeAlertType? planChangeType(Map<String, dynamic> customer) {
    final contractType = _text(customer['contract_type']).replaceAll(' ', '');
    if (contractType.contains('공시')) {
      return PlanChangeAlertType.publicSubsidy;
    }
    if (!contractType.contains('선약') && !contractType.contains('선택약정')) {
      return null;
    }
    final supportMoney = _toInt(customer['support_money']);
    if (supportMoney > 0) return PlanChangeAlertType.selectiveWithSupport;
    return PlanChangeAlertType.selectivePlanChange;
  }

  static bool hasActiveAddService(dynamic value) {
    final text = _text(value);
    if (text.isEmpty) return false;
    final compact = text.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    const inactive = {
      '없음',
      'x',
      '미적용',
      '0',
      '-',
      '없슴',
      '무',
      'n/a',
      'na',
      'none',
    };
    if (RegExp(r'^0+원?$').hasMatch(compact)) return false;
    return !inactive.contains(compact);
  }

  static String? normalizeCarrier(dynamic value) {
    final text = _text(value).toUpperCase().replaceAll(RegExp(r'[\s_-]'), '');
    if (text.contains('SK')) return 'SK';
    if (text.contains('KT')) return 'KT';
    if (text.contains('LG') || text.contains('U+')) return 'LG';
    return null;
  }

  static DateTime? parseDate(dynamic value) {
    final text = _text(value);
    if (text.isEmpty || text == '-') return null;
    final parsed = DateTime.tryParse(text);
    if (parsed == null) return null;
    return _dateOnly(parsed);
  }

  static DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  static bool _sameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static int _compareEntries(
    PlanChangeAlertEntry a,
    PlanChangeAlertEntry b,
  ) {
    final carrierCompare = carrierOrder
        .indexOf(a.carrier)
        .compareTo(carrierOrder.indexOf(b.carrier));
    if (carrierCompare != 0) return carrierCompare;
    final typeCompare =
        typeOrder.indexOf(a.type).compareTo(typeOrder.indexOf(b.type));
    if (typeCompare != 0) return typeCompare;
    final joinCompare = a.joinDateLabel.compareTo(b.joinDateLabel);
    if (joinCompare != 0) return joinCompare;
    return a.customerName.compareTo(b.customerName);
  }
}

String _text(dynamic value) {
  return value?.toString().trim() ?? '';
}

int _toInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString().replaceAll(RegExp(r'[^0-9-]'), '')) ?? 0;
}
