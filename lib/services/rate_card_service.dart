import 'package:supabase_flutter/supabase_flutter.dart';

const samsungAppleModels2024Plus = [
  'SM-S921N',
  'SM-S926N',
  'SM-S928N',
  'SM-S931N',
  'SM-S936N',
  'SM-S938N',
  'SM-S721N',
  'SM-S731N',
  'SM-F741N',
  'SM-F956N',
  'SM-F761N',
  'SM-F966N',
  'SM-A356N',
  'SM-A366N',
  'SM-A556N',
  'SM-M156S',
  'SM-M166S',
  'iPhone 16',
  'iPhone 16 Plus',
  'iPhone 16 Pro',
  'iPhone 16 Pro Max',
  'iPhone 16e',
  'iPhone 17',
  'iPhone 17 Pro',
  'iPhone 17 Pro Max',
  'iPhone Air',
];

const officialPlanCandidates = {
  'SKT': [
    '5GX 플래티넘',
    '5GX 프라임플러스',
    '5GX 프라임',
    '5GX 레귤러플러스',
    '5GX 레귤러',
    '베이직플러스',
    '베이직',
    '컴팩트플러스',
    '컴팩트',
    '0 청년 99',
    '0 청년 89',
    '0 청년 79',
    '0 청년 69',
    '0 청년 59',
    '0 청년 49',
    '0 청년 43',
    '0 청년 37',
    '다이렉트 5G 69',
    '다이렉트 5G 62',
    '다이렉트 5G 55',
    '다이렉트 5G 48',
    '다이렉트 5G 42',
    '다이렉트 5G 31',
    '다이렉트 5G 27',
  ],
  'KT': [
    '초이스 프리미엄',
    '초이스 스페셜',
    '초이스 베이직',
    '베이직',
    '슬림',
    '세이브',
    '5G Y틴',
    '5G Y덤',
    '가전구독 초이스스페셜',
    '가전구독 초이스베이직',
  ],
  'LG': [
    '5G 시그니처',
    '5G 프리미어 슈퍼',
    '5G 프리미어 플러스',
    '5G 프리미어 레귤러',
    '5G 프리미어 에센셜',
    '5G 스탠다드',
    '5G 라이트+',
    '5G 슬림+',
    '유쓰 5G 프리미어',
    '유쓰 5G 스탠다드',
    '유쓰 5G 라이트 플러스',
    '유쓰 5G 슬림 플러스',
    '너겟69',
    '너겟65',
    '너겟59',
  ],
};

class RateCardRule {
  final String id;
  final String carrier;
  final String modelName;
  final String planName;
  final String joinType;
  final String contractType;
  final String addServiceName;
  final int baseRebate;
  final int addRebate;
  final int deduction;
  final String memo;
  final bool isActive;

  const RateCardRule({
    required this.id,
    required this.carrier,
    required this.modelName,
    required this.planName,
    required this.joinType,
    required this.contractType,
    required this.addServiceName,
    required this.baseRebate,
    required this.addRebate,
    required this.deduction,
    required this.memo,
    required this.isActive,
  });

  factory RateCardRule.fromMap(Map<String, dynamic> data) {
    return RateCardRule(
      id: (data['id'] ?? '').toString(),
      carrier: (data['carrier'] ?? '').toString(),
      modelName: (data['model_name'] ?? '').toString(),
      planName: (data['plan_name'] ?? '').toString(),
      joinType: (data['join_type'] ?? '').toString(),
      contractType: (data['contract_type'] ?? '').toString(),
      addServiceName: (data['add_service_name'] ?? '').toString(),
      baseRebate: _toInt(data['base_rebate']),
      addRebate: _toInt(data['add_rebate']),
      deduction: _toInt(data['deduction']),
      memo: (data['memo'] ?? '').toString(),
      isActive: data['is_active'] == true,
    );
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse((value ?? '').toString()) ?? 0;
  }
}

class RateCardService {
  final SupabaseClient supabase;

  const RateCardService(this.supabase);

  Future<String> fetchGoogleSheetCsvUrl(String carrier) async {
    final row = await supabase
        .from('rebate_rate_card_sources')
        .select('csv_url')
        .eq('carrier', carrier)
        .maybeSingle();

    return (row?['csv_url'] ?? '').toString();
  }

  Future<Map<String, String>> fetchGoogleSheetCsvUrls() async {
    final rows = await supabase
        .from('rebate_rate_card_sources')
        .select('carrier,csv_url')
        .inFilter('carrier', const ['SKT', 'KT', 'LG']);

    return {
      for (final row in rows)
        (row['carrier'] ?? '').toString(): (row['csv_url'] ?? '').toString(),
    };
  }

  Future<void> saveGoogleSheetCsvUrl({
    required String carrier,
    required String csvUrl,
  }) async {
    final trimmedUrl = csvUrl.trim();
    if (!_isAllowedCsvUrl(trimmedUrl)) {
      throw const FormatException('구글시트 공개 CSV 링크만 등록할 수 있습니다.');
    }

    await supabase.from('rebate_rate_card_sources').upsert(
      {
        'carrier': carrier,
        'csv_url': trimmedUrl,
        'updated_by': supabase.auth.currentUser?.id,
      },
      onConflict: 'carrier',
    );
  }

  Future<void> saveGoogleSheetCsvUrls(Map<String, String> csvUrls) async {
    final payloads = <Map<String, dynamic>>[];
    for (final carrier in const ['SKT', 'KT', 'LG']) {
      final trimmedUrl = (csvUrls[carrier] ?? '').trim();
      if (trimmedUrl.isEmpty) continue;
      if (!_isAllowedCsvUrl(trimmedUrl)) {
        throw FormatException('$carrier 링크가 구글시트 공개 CSV 형식이 아닙니다.');
      }
      payloads.add({
        'carrier': carrier,
        'csv_url': trimmedUrl,
        'updated_by': supabase.auth.currentUser?.id,
      });
    }

    if (payloads.isEmpty) {
      throw const FormatException('저장할 구글시트 CSV 링크가 없습니다.');
    }

    await supabase.from('rebate_rate_card_sources').upsert(
          payloads,
          onConflict: 'carrier',
        );
  }

  static bool _isAllowedCsvUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) return false;
    if (uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    final isGoogleSheet = host == 'docs.google.com';
    final exportsCsv = value.contains('/spreadsheets/') &&
        (value.contains('output=csv') || value.contains('format=csv'));
    return isGoogleSheet && exportsCsv;
  }

  Future<List<RateCardRule>> fetchRules({
    String keyword = '',
    String carrier = '',
  }) async {
    final trimmedKeyword = keyword.trim();
    final trimmedCarrier = carrier.trim();
    var query = supabase.from('rebate_rate_cards').select();

    if (trimmedCarrier.isNotEmpty) {
      query = query.eq('carrier', trimmedCarrier);
    }

    final rows = trimmedKeyword.isEmpty
        ? await query.order('carrier').order('model_name').order('plan_name')
        : await query
            .or(
              'carrier.ilike.%$trimmedKeyword%,model_name.ilike.%$trimmedKeyword%,plan_name.ilike.%$trimmedKeyword%,add_service_name.ilike.%$trimmedKeyword%,memo.ilike.%$trimmedKeyword%',
            )
            .order('carrier')
            .order('model_name')
            .order('plan_name');

    return rows
        .map<RateCardRule>(
          (row) => RateCardRule.fromMap(Map<String, dynamic>.from(row)),
        )
        .toList();
  }

  Future<RateCardRule?> findBestMatch({
    required String carrier,
    required String modelName,
    required String planName,
    required String addServiceName,
    String? joinType,
    String? contractType,
  }) async {
    if (modelName.trim().isEmpty || planName.trim().isEmpty) return null;

    final rows = await supabase
        .from('rebate_rate_cards')
        .select()
        .eq('is_active', true)
        .eq('model_key', normalizeKey(modelName))
        .eq('plan_key', normalizeKey(planName));

    final rules = rows
        .map<RateCardRule>(
          (row) => RateCardRule.fromMap(Map<String, dynamic>.from(row)),
        )
        .where((rule) => _optionalMatches(rule.carrier, carrier))
        .where((rule) => _optionalMatches(rule.joinType, joinType ?? ''))
        .where(
            (rule) => _optionalMatches(rule.contractType, contractType ?? ''))
        .where((rule) =>
            rule.addServiceName.trim().isEmpty ||
            normalizeKey(addServiceName)
                .contains(normalizeKey(rule.addServiceName)))
        .toList();

    if (rules.isEmpty) return null;
    rules.sort((a, b) => _score(b).compareTo(_score(a)));
    return rules.first;
  }

  Future<void> createRule(Map<String, dynamic> values) async {
    await supabase.from('rebate_rate_cards').insert({
      ..._payload(values),
      'created_by': supabase.auth.currentUser?.id,
    });
  }

  Future<void> updateRule(String id, Map<String, dynamic> values) async {
    await supabase
        .from('rebate_rate_cards')
        .update(_payload(values))
        .eq('id', id);
  }

  Future<void> deleteRule(String id) async {
    await supabase.from('rebate_rate_cards').delete().eq('id', id);
  }

  static String normalizeKey(String value) {
    return value.toUpperCase().replaceAll(RegExp(r'[\s_\-+/()]'), '');
  }

  bool _optionalMatches(String ruleValue, String inputValue) {
    final ruleKey = normalizeKey(ruleValue);
    if (ruleKey.isEmpty) return true;
    return normalizeKey(inputValue) == ruleKey;
  }

  int _score(RateCardRule rule) {
    var score = 0;
    if (rule.carrier.trim().isNotEmpty) score += 8;
    if (rule.joinType.trim().isNotEmpty) score += 4;
    if (rule.contractType.trim().isNotEmpty) score += 4;
    if (rule.addServiceName.trim().isNotEmpty) score += 2;
    return score;
  }

  Map<String, dynamic> _payload(Map<String, dynamic> values) {
    final carrier = (values['carrier'] ?? '').toString().trim();
    final modelName = (values['model_name'] ?? '').toString().trim();
    final planName = (values['plan_name'] ?? '').toString().trim();
    final addService = (values['add_service_name'] ?? '').toString().trim();

    return {
      'carrier': carrier,
      'model_name': modelName,
      'model_key': normalizeKey(modelName),
      'plan_name': planName,
      'plan_key': normalizeKey(planName),
      'join_type': (values['join_type'] ?? '').toString().trim(),
      'contract_type': (values['contract_type'] ?? '').toString().trim(),
      'add_service_name': addService,
      'add_service_key': normalizeKey(addService),
      'base_rebate': values['base_rebate'] ?? 0,
      'add_rebate': values['add_rebate'] ?? 0,
      'deduction': values['deduction'] ?? 0,
      'memo': (values['memo'] ?? '').toString().trim(),
      'is_active': values['is_active'] == true,
    };
  }
}
