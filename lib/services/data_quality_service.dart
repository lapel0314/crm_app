import 'package:crm_app/utils/supabase_fetch_utils.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DataQualityIssue {
  final String type;
  final String title;
  final String severity;
  final String customerId;
  final String name;
  final String phone;
  final String store;
  final String joinDate;
  final String carrier;
  final String previousCarrier;
  final String detail;

  const DataQualityIssue({
    required this.type,
    required this.title,
    required this.severity,
    required this.customerId,
    required this.name,
    required this.phone,
    required this.store,
    required this.joinDate,
    required this.carrier,
    required this.previousCarrier,
    required this.detail,
  });
}

class DataQualityService {
  final SupabaseClient supabase;

  const DataQualityService(this.supabase);

  Future<List<Map<String, dynamic>>> fetchCustomers() async {
    return fetchAllRows(() => supabase
        .from('customers')
        .select(
          'id, name, phone, store, join_date, carrier, previous_carrier, created_at',
        )
        .eq('is_deleted', false)
        .order('join_date', ascending: false)
        .order('created_at', ascending: false));
  }

  List<DataQualityIssue> analyzeCustomers(List<Map<String, dynamic>> rows) {
    final issues = <DataQualityIssue>[];
    final phoneGroups = <String, List<Map<String, dynamic>>>{};

    for (final row in rows) {
      final phoneDigits = digitsOnly(row['phone']);
      if (phoneDigits.isNotEmpty) {
        phoneGroups.putIfAbsent(phoneDigits, () => []).add(row);
      }

      if (!_isValidPhone(phoneDigits)) {
        issues.add(_issue(
          row,
          type: 'phone',
          title: phoneDigits.isEmpty ? '전화번호 누락' : '전화번호 형식 오류',
          severity: '높음',
          detail: '전화번호는 숫자 기준 10~11자리 국내 번호여야 합니다.',
        ));
      }

      if (!_isValidDate(row['join_date'])) {
        issues.add(_issue(
          row,
          type: 'join_date',
          title: '가입일 누락/오류',
          severity: '높음',
          detail: '가입일이 비어 있거나 날짜로 해석되지 않습니다.',
        ));
      }

      final carrierText = text(row['carrier']);
      final previousCarrierText = text(row['previous_carrier']);
      if (!_looksLikeCarrier(carrierText) &&
          !_looksLikeCarrier(previousCarrierText)) {
        issues.add(_issue(
          row,
          type: 'carrier',
          title: '통신사/거래처 이상값',
          severity: '보통',
          detail: 'SK, KT, LG, 유피, 알뜰폰 계열 키워드가 확인되지 않습니다.',
        ));
      }
    }

    for (final entry in phoneGroups.entries) {
      if (entry.value.length < 2 || !_isValidPhone(entry.key)) continue;
      for (final row in entry.value) {
        issues.add(_issue(
          row,
          type: 'duplicate',
          title: '중복 고객 의심',
          severity: '보통',
          detail: '같은 전화번호 고객이 ${entry.value.length}건 있습니다.',
        ));
      }
    }

    issues.sort((a, b) {
      final severity = _severityRank(a.severity).compareTo(
        _severityRank(b.severity),
      );
      if (severity != 0) return severity;
      return a.name.compareTo(b.name);
    });
    return issues;
  }

  static String text(dynamic value) {
    final text = value?.toString().trim() ?? '';
    return text;
  }

  static String digitsOnly(dynamic value) {
    return text(value).replaceAll(RegExp(r'[^0-9]'), '');
  }

  bool _isValidPhone(String digits) {
    if (digits.length != 10 && digits.length != 11) return false;
    return digits.startsWith('0');
  }

  bool _isValidDate(dynamic value) {
    final raw = text(value);
    if (raw.isEmpty) return false;
    return DateTime.tryParse(raw.length >= 10 ? raw.substring(0, 10) : raw) !=
        null;
  }

  bool _looksLikeCarrier(String value) {
    final normalized = value.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    if (normalized.isEmpty || normalized == '-' || normalized == '없음') {
      return false;
    }
    const tokens = [
      'sk',
      'kt',
      'lg',
      'lgu',
      'u+',
      '유플',
      '유피',
      '알뜰',
      'ktm',
      'm모바일',
      '헬로',
      '스카이',
      '세븐',
      '리브',
      '이야기',
    ];
    return tokens.any(normalized.contains);
  }

  DataQualityIssue _issue(
    Map<String, dynamic> row, {
    required String type,
    required String title,
    required String severity,
    required String detail,
  }) {
    return DataQualityIssue(
      type: type,
      title: title,
      severity: severity,
      customerId: text(row['id']),
      name: text(row['name']).isEmpty ? '-' : text(row['name']),
      phone: text(row['phone']).isEmpty ? '-' : text(row['phone']),
      store: text(row['store']).isEmpty ? '-' : text(row['store']),
      joinDate: text(row['join_date']).isEmpty ? '-' : text(row['join_date']),
      carrier: text(row['carrier']).isEmpty ? '-' : text(row['carrier']),
      previousCarrier: text(row['previous_carrier']).isEmpty
          ? '-'
          : text(row['previous_carrier']),
      detail: detail,
    );
  }

  static int _severityRank(String severity) {
    return switch (severity) {
      '높음' => 0,
      '보통' => 1,
      _ => 2,
    };
  }
}
