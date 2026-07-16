import 'package:crm_app/services/plan_change_alert_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlanChangeAlertService', () {
    test('calculates add-service delete due dates by carrier', () {
      expect(
        _typesFor(
          carrier: 'SK',
          joinDate: '2026-03-15',
          addService: '컬러링',
          contractType: '',
          today: DateTime(2026, 4),
        ),
        [PlanChangeAlertType.addServiceDelete],
      );

      expect(
        _typesFor(
          carrier: 'KT',
          joinDate: '2026-03-15',
          addService: '보험',
          contractType: '',
          today: DateTime(2026, 7),
        ),
        [PlanChangeAlertType.addServiceDelete],
      );

      expect(
        _typesFor(
          carrier: 'LG',
          joinDate: '2026-03-30',
          addService: '부가서비스',
          contractType: '',
          today: DateTime(2026, 7, 2),
        ),
        [PlanChangeAlertType.addServiceDelete],
      );

      expect(
        _typesFor(
          carrier: 'KTM / 유피',
          joinDate: '2026-03-15',
          addService: '보험',
          contractType: '',
          today: DateTime(2026, 7),
        ),
        [PlanChangeAlertType.addServiceDelete],
      );
    });

    test('classifies 유피 carrier as 알뜰폰', () {
      final entries = _entriesFor(
        carrier: 'KTM / 유피',
        joinDate: '2026-03-15',
        addService: '보험',
        contractType: '',
        today: DateTime(2026, 7),
      );

      expect(entries.single.carrier, '알뜰폰');
      expect(PlanChangeAlertService.carrierOrder, ['SK', 'KT', 'LG', '알뜰폰']);
    });

    test('calculates plan-change due dates by carrier and contract type', () {
      expect(
        _typesFor(
          carrier: 'SK',
          joinDate: '2026-03-15',
          contractType: '선약',
          supportMoney: 0,
          today: DateTime(2026, 8),
        ),
        [PlanChangeAlertType.selectivePlanChange],
      );

      expect(
        _typesFor(
          carrier: 'KT',
          joinDate: '2026-03-01',
          contractType: '선택약정',
          supportMoney: '',
          today: DateTime(2026, 7),
        ),
        [PlanChangeAlertType.selectivePlanChange],
      );

      expect(
        _typesFor(
          carrier: 'LG',
          joinDate: '2026-03-30',
          contractType: '선약',
          supportMoney: 0,
          today: DateTime(2026, 7, 2),
        ),
        [PlanChangeAlertType.selectivePlanChange],
      );

      expect(
        _typesFor(
          carrier: 'KTM / 유피',
          joinDate: '2026-03-01',
          contractType: '선약',
          supportMoney: 0,
          today: DateTime(2026, 7, 1),
        ),
        [PlanChangeAlertType.selectivePlanChange],
      );

      expect(
        _typesFor(
          carrier: 'KTM / 유피',
          joinDate: '2026-01-01',
          contractType: '공시',
          supportMoney: 0,
          today: DateTime(2026, 7, 3),
        ),
        [PlanChangeAlertType.publicSubsidy],
      );

      expect(
        _typesFor(
          carrier: 'KTM / 유피',
          joinDate: '2026-01-01',
          contractType: '선약',
          supportMoney: '10,000원',
          today: DateTime(2026, 7, 3),
        ),
        [PlanChangeAlertType.selectiveWithSupport],
      );
    });

    test('classifies subsidy and selective support contracts', () {
      expect(
        _typesFor(
          carrier: 'SK',
          joinDate: '2026-01-01',
          contractType: '공시',
          today: DateTime(2026, 7, 3),
        ),
        [PlanChangeAlertType.publicSubsidy],
      );

      expect(
        _typesFor(
          carrier: 'KT',
          joinDate: '2026-01-01',
          contractType: '선약',
          supportMoney: '10,000원',
          today: DateTime(2026, 7, 3),
        ),
        [PlanChangeAlertType.selectiveWithSupport],
      );
    });

    test('ignores inactive add-service values', () {
      for (final value in ['', '없음', 'X', '미적용', '0', '0원', '-']) {
        expect(PlanChangeAlertService.hasActiveAddService(value), isFalse);
      }

      expect(PlanChangeAlertService.hasActiveAddService('보험'), isTrue);
    });

    test('maps task rows to labels and overdue state', () {
      final task = PlanChangeTask.fromMap({
        'id': 'task-1',
        'customer_id': 'customer-1',
        'customer_name': '홍길동',
        'phone': '010-0000-0000',
        'store': '본점',
        'carrier_group': 'LG',
        'task_type': 'selective_plan_change',
        'due_date': '2026-07-01',
        'status': 'pending',
        'before_value': '프리미어',
      });

      expect(task.typeLabel, '선택약정 요금제변경');
      expect(task.statusLabel, '미처리');
      expect(task.isOverdue(DateTime(2026, 7, 2)), isTrue);
      expect(task.isOverdue(DateTime(2026, 7, 1)), isFalse);
    });
  });
}

List<PlanChangeAlertType> _typesFor({
  required String carrier,
  required String joinDate,
  required String contractType,
  required DateTime today,
  String addService = '',
  Object? supportMoney = 0,
}) {
  return _entriesFor(
    carrier: carrier,
    joinDate: joinDate,
    addService: addService,
    contractType: contractType,
    supportMoney: supportMoney,
    today: today,
  ).map((entry) => entry.type).toList();
}

List<PlanChangeAlertEntry> _entriesFor({
  required String carrier,
  required String joinDate,
  required String contractType,
  required DateTime today,
  String addService = '',
  Object? supportMoney = 0,
}) {
  return PlanChangeAlertService.entriesForCustomer(
    customer: {
      'id': 'customer-1',
      'carrier': carrier,
      'join_date': joinDate,
      'add_service': addService,
      'contract_type': contractType,
      'support_money': supportMoney,
    },
    today: today,
  );
}
