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
  final PlanChangeTask? task;

  const PlanChangeAlertEntry({
    required this.customer,
    required this.carrier,
    required this.type,
    required this.dueDate,
    this.task,
  });

  String get customerId => (customer['id'] ?? '').toString();
  String get customerName => _text(customer['name']);
  String get phone => _text(customer['phone']);
  String get store => _text(customer['store']);
  String get staff => _text(customer['staff']);
  String get plan => _text(customer['plan']);
  String get addService => _text(customer['add_service']);
  String get contractType => _text(customer['contract_type']);
  bool get isCompleted => task?.status == PlanChangeTaskStatus.done;
  String get currentValue =>
      PlanChangeAlertService.valueForType(type, customer);
  String get joinDateLabel {
    final date = PlanChangeAlertService.parseDate(customer['join_date']);
    return date == null ? '-' : DateFormat('yyyy-MM-dd').format(date);
  }

  PlanChangeAlertEntry copyWith({PlanChangeTask? task}) {
    return PlanChangeAlertEntry(
      customer: customer,
      carrier: carrier,
      type: type,
      dueDate: dueDate,
      task: task ?? this.task,
    );
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

class PlanChangeTaskStatus {
  static const pending = 'pending';
  static const done = 'done';
  static const skipped = 'skipped';
}

class PlanChangeTask {
  final String id;
  final String customerId;
  final String customerName;
  final String phone;
  final String store;
  final String carrierGroup;
  final String taskType;
  final DateTime dueDate;
  final String status;
  final String beforeValue;
  final String afterValue;
  final String actionDetail;
  final String note;
  final DateTime? completedAt;

  const PlanChangeTask({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.phone,
    required this.store,
    required this.carrierGroup,
    required this.taskType,
    required this.dueDate,
    required this.status,
    required this.beforeValue,
    required this.afterValue,
    required this.actionDetail,
    required this.note,
    required this.completedAt,
  });

  factory PlanChangeTask.fromMap(Map<String, dynamic> data) {
    return PlanChangeTask(
      id: _text(data['id']),
      customerId: _text(data['customer_id']),
      customerName: _text(data['customer_name']),
      phone: _text(data['phone']),
      store: _text(data['store']),
      carrierGroup: _text(data['carrier_group']),
      taskType: _text(data['task_type']),
      dueDate: PlanChangeAlertService.parseDate(data['due_date']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      status: _text(data['status']).isEmpty
          ? PlanChangeTaskStatus.pending
          : _text(data['status']),
      beforeValue: _text(data['before_value']),
      afterValue: _text(data['after_value']),
      actionDetail: _text(data['action_detail']),
      note: _text(data['note']),
      completedAt: PlanChangeAlertService.parseDateTime(data['completed_at']),
    );
  }

  PlanChangeAlertType? get alertType =>
      PlanChangeAlertService.typeFromTaskCode(taskType);

  String get typeLabel => alertType?.label ?? taskType;

  String get statusLabel {
    return switch (status) {
      PlanChangeTaskStatus.done => '처리완료',
      PlanChangeTaskStatus.skipped => '보류',
      _ => '미처리',
    };
  }

  bool isOverdue(DateTime today) {
    return status == PlanChangeTaskStatus.pending &&
        dueDate.isBefore(PlanChangeAlertService.dateOnly(today));
  }
}

class PlanChangeAlertService {
  final SupabaseClient supabase;

  const PlanChangeAlertService(this.supabase);

  static final List<String> carrierOrder = ['SK', 'KT', 'LG', '알뜰폰'];
  static final List<PlanChangeAlertType> typeOrder = [
    PlanChangeAlertType.addServiceDelete,
    PlanChangeAlertType.selectivePlanChange,
    PlanChangeAlertType.publicSubsidy,
    PlanChangeAlertType.selectiveWithSupport,
  ];
  static final DateFormat _dateFormat = DateFormat('yyyy-MM-dd');

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
    final entriesWithTasks = await _syncAndAttachTasks(entries);
    return PlanChangeAlertResult(date: today, entries: entriesWithTasks);
  }

  Future<Map<String, List<PlanChangeTask>>> fetchCustomerTasks(
    Iterable<String> customerIds,
  ) async {
    final ids =
        customerIds.where((id) => id.trim().isNotEmpty).toSet().toList();
    if (ids.isEmpty) return const {};

    try {
      final rows = await supabase
          .from('plan_change_tasks')
          .select()
          .inFilter('customer_id', ids)
          .order('due_date', ascending: false)
          .order('created_at', ascending: false);

      final result = <String, List<PlanChangeTask>>{};
      for (final row in rows) {
        final task = PlanChangeTask.fromMap(Map<String, dynamic>.from(row));
        result.putIfAbsent(task.customerId, () => []).add(task);
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  Future<void> completeTask({
    required PlanChangeTask task,
    required String afterValue,
    String note = '',
  }) async {
    final beforeValue = task.beforeValue.isNotEmpty
        ? task.beforeValue
        : task.afterValue.isNotEmpty
            ? task.afterValue
            : afterValue;
    await _completeTaskRow(
      task: task,
      beforeValue: beforeValue,
      afterValue: afterValue,
      note: note,
    );
  }

  Future<int> completePendingTasksForCustomerChange({
    required String customerId,
    required String planBefore,
    required String planAfter,
    required String addServiceBefore,
    required String addServiceAfter,
  }) async {
    if (customerId.trim().isEmpty) return 0;
    final planChanged = _compactValue(planBefore) != _compactValue(planAfter);
    final addServiceChanged =
        _compactValue(addServiceBefore) != _compactValue(addServiceAfter);
    if (!planChanged && !addServiceChanged) return 0;

    final taskMap = await fetchCustomerTasks([customerId]);
    final pendingTasks = (taskMap[customerId] ?? const <PlanChangeTask>[])
        .where((task) => task.status == PlanChangeTaskStatus.pending);
    var completed = 0;

    for (final task in pendingTasks) {
      final type = typeFromTaskCode(task.taskType);
      if (type == PlanChangeAlertType.addServiceDelete && addServiceChanged) {
        await _completeTaskRow(
          task: task,
          beforeValue: addServiceBefore,
          afterValue: addServiceAfter,
          note: '고객DB 부가서비스 변경 저장',
        );
        completed++;
      } else if (type != null &&
          type != PlanChangeAlertType.addServiceDelete &&
          planChanged) {
        await _completeTaskRow(
          task: task,
          beforeValue: planBefore,
          afterValue: planAfter,
          note: '고객DB 요금제 변경 저장',
        );
        completed++;
      }
    }

    return completed;
  }

  Future<List<PlanChangeAlertEntry>> _syncAndAttachTasks(
    List<PlanChangeAlertEntry> entries,
  ) async {
    if (entries.isEmpty) return entries;
    try {
      await _insertMissingTasks(entries);
      final tasks =
          await fetchCustomerTasks(entries.map((entry) => entry.customerId));
      final byKey = <String, PlanChangeTask>{};
      for (final taskList in tasks.values) {
        for (final task in taskList) {
          byKey[_taskKey(task.customerId, task.taskType, task.dueDate)] = task;
        }
      }
      return entries
          .map(
            (entry) => entry.copyWith(
              task: byKey[_taskKey(
                entry.customerId,
                taskTypeCode(entry.type),
                entry.dueDate,
              )],
            ),
          )
          .toList();
    } catch (_) {
      return entries;
    }
  }

  Future<void> _insertMissingTasks(List<PlanChangeAlertEntry> entries) async {
    final userId = supabase.auth.currentUser?.id;
    final payloads = <Map<String, dynamic>>[];
    for (final entry in entries) {
      if (entry.customerId.isEmpty) continue;
      payloads.add({
        'customer_id': entry.customerId,
        'customer_name': entry.customerName,
        'phone': entry.phone,
        'store': entry.store,
        'normalized_store': normalizeStoreName(entry.store),
        'carrier_group': entry.carrier,
        'task_type': taskTypeCode(entry.type),
        'due_date': _dateFormat.format(entry.dueDate),
        'before_value': entry.currentValue,
        'action_detail': entry.type == PlanChangeAlertType.addServiceDelete
            ? '부가서비스 삭제 확인'
            : '요금제 변경 확인',
        'created_by': userId,
      });
    }
    if (payloads.isEmpty) return;

    await supabase.from('plan_change_tasks').upsert(
          payloads,
          onConflict: 'customer_id,task_type,due_date',
          ignoreDuplicates: true,
        );
  }

  Future<void> _completeTaskRow({
    required PlanChangeTask task,
    required String beforeValue,
    required String afterValue,
    required String note,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    final now = DateTime.now().toUtc().toIso8601String();
    final actionDetail =
        '${task.typeLabel}: ${_blankDash(beforeValue)} -> ${_blankDash(afterValue)}';

    await supabase.from('plan_change_tasks').update({
      'status': PlanChangeTaskStatus.done,
      'before_value': beforeValue.trim(),
      'after_value': afterValue.trim(),
      'action_detail': actionDetail,
      'note': note.trim(),
      'completed_at': now,
      'completed_by': userId,
    }).eq('id', task.id);

    await supabase.from('plan_change_task_logs').insert({
      'task_id': task.id,
      'action': 'completed',
      'before_value': beforeValue.trim(),
      'after_value': afterValue.trim(),
      'note': note.trim(),
      'actor_id': userId,
    });
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
        case '알뜰폰':
          addIfDue(
            PlanChangeAlertType.addServiceDelete,
            DateTime(normalizedJoinDate.year, normalizedJoinDate.month + 4, 1),
          );
        case 'LG':
          addIfDue(
            PlanChangeAlertType.addServiceDelete,
            normalizedJoinDate.add(const Duration(days: 94)),
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
      case '알뜰폰':
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
              ? normalizedJoinDate.add(const Duration(days: 94))
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
    if (text.contains('유피')) return '알뜰폰';
    if (text.contains('SK')) return 'SK';
    if (text.contains('KT')) return 'KT';
    if (text.contains('LG') || text.contains('U+')) return 'LG';
    return null;
  }

  static String taskTypeCode(PlanChangeAlertType type) {
    return switch (type) {
      PlanChangeAlertType.addServiceDelete => 'add_service_delete',
      PlanChangeAlertType.selectivePlanChange => 'selective_plan_change',
      PlanChangeAlertType.publicSubsidy => 'public_subsidy',
      PlanChangeAlertType.selectiveWithSupport => 'selective_with_support',
    };
  }

  static PlanChangeAlertType? typeFromTaskCode(String code) {
    return switch (code) {
      'add_service_delete' => PlanChangeAlertType.addServiceDelete,
      'selective_plan_change' => PlanChangeAlertType.selectivePlanChange,
      'public_subsidy' => PlanChangeAlertType.publicSubsidy,
      'selective_with_support' => PlanChangeAlertType.selectiveWithSupport,
      _ => null,
    };
  }

  static String valueForType(
    PlanChangeAlertType type,
    Map<String, dynamic> customer,
  ) {
    return type == PlanChangeAlertType.addServiceDelete
        ? _text(customer['add_service'])
        : _text(customer['plan']);
  }

  static DateTime? parseDate(dynamic value) {
    final text = _text(value);
    if (text.isEmpty || text == '-') return null;
    final parsed = DateTime.tryParse(text);
    if (parsed == null) return null;
    return _dateOnly(parsed);
  }

  static DateTime? parseDateTime(dynamic value) {
    final text = _text(value);
    if (text.isEmpty || text == '-') return null;
    return DateTime.tryParse(text);
  }

  static DateTime dateOnly(DateTime date) => _dateOnly(date);

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

String _taskKey(String customerId, String taskType, DateTime dueDate) {
  return '$customerId|$taskType|${PlanChangeAlertService._dateFormat.format(dueDate)}';
}

String _compactValue(String value) {
  return value.trim().replaceAll(RegExp(r'\s+'), '').toLowerCase();
}

String _blankDash(String value) {
  final text = value.trim();
  return text.isEmpty ? '-' : text;
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
