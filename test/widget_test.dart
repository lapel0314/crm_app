import 'package:crm_app/services/data_quality_service.dart';
import 'package:crm_app/services/plan_change_alert_service.dart';
import 'package:crm_app/utils/model_name_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('normalizeModelName', () {
    test('normalizes dashboard model aliases without changing stored values',
        () {
      expect(normalizeModelName('A175'), '갤럭시 A17 256GB');
      expect(normalizeModelName('a175'), '갤럭시 A17 256GB');
      expect(normalizeModelName('SM-A175'), '갤럭시 A17 256GB');
      expect(normalizeModelName('SM-A175N'), '갤럭시 A17 256GB');
      expect(normalizeModelName('SM A175'), '갤럭시 A17 256GB');
      expect(normalizeModelName('s928n'), '갤럭시 SM-S928 256GB');
      expect(normalizeModelName('S942'), '갤럭시 S26 256GB');
      expect(normalizeModelName('S942N256'), '갤럭시 S26 256GB');
      expect(normalizeModelName('S948N512GB'), '갤럭시 S26 울트라 512GB');
      expect(normalizeModelName('F766N256'), '갤럭시 Z 플립7 256GB');
      expect(normalizeModelName('M140'), '스타일폴더2');
      expect(normalizeModelName('AT-M140'), '스타일폴더2');
      expect(normalizeModelName('AT-M140S'), '스타일폴더2');
      expect(normalizeModelName('L325'), '갤럭시 SM-L325');
      expect(normalizeModelName('X216'), '갤럭시 탭 A9+');
      expect(normalizeModelName('아이폰17'), '아이폰 17 256GB');
      expect(normalizeModelName('iphone17'), '아이폰 17 256GB');
      expect(normalizeModelName('iPhone 17'), '아이폰 17 256GB');
      expect(normalizeModelName('아이폰17프로'), '아이폰 17 프로 256GB');
      expect(normalizeModelName('17PR-256'), '아이폰 17 프로 256GB');
      expect(normalizeModelName('17PM-512'), '아이폰 17 프로 맥스 512GB');
      expect(normalizeModelName('17PM256'), '아이폰 17 프로 맥스 256GB');
      expect(normalizeModelName('16E-128'), '아이폰 16e 128GB');
      expect(normalizeModelName('AIP16PMN512'), '아이폰 16 프로 맥스 512GB');
      expect(normalizeModelName('갤럭시 A17'), '갤럭시 A17 256GB');
      expect(normalizeModelName('iPhone 15'), '아이폰 15 256GB');
      expect(normalizeModelName('A2633-128'), 'A2633-128');
      expect(normalizeModelName('SE3 44MM'), 'SE3 44MM');
    });

    test('uses admin model mappings before automatic fallback', () {
      final lookup = buildModelAliasLookup(const [
        ModelNameMapping(
          displayName: '아이폰 17 256GB',
          registeredNames: ['IP-17', 'iphone17', '아이폰17'],
        ),
        ModelNameMapping(
          displayName: '스타일폴더2',
          registeredNames: ['M140', 'AT-M140', 'AT-M140S'],
        ),
      ]);

      expect(
        normalizeModelNameWithAliases('IP-17', lookup),
        '아이폰 17 256GB',
      );
      expect(
        normalizeModelNameWithAliases('아이폰17', lookup),
        '아이폰 17 256GB',
      );
      expect(normalizeModelNameWithAliases('AT-M140S', lookup), '스타일폴더2');
      expect(
        normalizeModelNameWithAliases('S942N256', lookup),
        '갤럭시 S26 256GB',
      );
    });
  });

  group('DataQualityService', () {
    test('detects duplicate, invalid phone, missing date, and carrier issues',
        () {
      final service = DataQualityService(
        SupabaseClient('https://example.supabase.co', 'test-key'),
      );
      final analysis = service.analyzeCustomers([
        {
          'id': '1',
          'name': '홍길동',
          'phone': '010-1234-5678',
          'join_date': '2026-07-20',
          'carrier': 'SK',
          'previous_carrier': '',
          'store': '본점',
        },
        {
          'id': '2',
          'name': '김길동',
          'phone': '01012345678',
          'join_date': '2026-07-21',
          'carrier': 'KT',
          'previous_carrier': '',
          'store': '본점',
        },
        {
          'id': '3',
          'name': '오류고객',
          'phone': '123',
          'join_date': '',
          'carrier': '미상',
          'previous_carrier': '',
          'store': '본점',
        },
      ]);

      final issues = analysis.active;
      expect(issues.where((issue) => issue.type == 'duplicate'), hasLength(2));
      expect(issues.any((issue) => issue.type == 'phone'), isTrue);
      expect(issues.any((issue) => issue.type == 'join_date'), isTrue);
      expect(issues.any((issue) => issue.type == 'carrier'), isTrue);
      expect(analysis.dismissed, isEmpty);
    });

    test('dismissed issues are separated and invalidated when value changes',
        () {
      final service = DataQualityService(
        SupabaseClient('https://example.supabase.co', 'test-key'),
      );
      const rows = [
        {
          'id': '3',
          'name': '오류고객',
          'phone': '123',
          'join_date': '2026-07-21',
          'carrier': 'KT',
          'previous_carrier': '',
          'store': '본점',
        },
      ];

      final dismissedMatch = service.analyzeCustomers(
        rows,
        dismissals: const [
          DataQualityDismissal(issueType: 'phone', issueKey: '3:123'),
        ],
      );
      expect(dismissedMatch.active.where((i) => i.type == 'phone'), isEmpty);
      expect(dismissedMatch.dismissed, hasLength(1));

      // 전화번호가 다른 값으로 바뀌면 지문이 달라져 다시 활성 이슈로 돌아온다.
      final invalidated = service.analyzeCustomers(
        rows,
        dismissals: const [
          DataQualityDismissal(issueType: 'phone', issueKey: '3:999'),
        ],
      );
      expect(
        invalidated.active.any((i) => i.type == 'phone'),
        isTrue,
      );
    });
  });

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
