// 매장이 늘어나면 발송 문자가 전부 특정 지점 명의가 되지 않도록,
// {매장명}은 하드코딩 대신 호출부(현재 로그인 매장)에서 주입한다.
const String defaultContactMessageTemplate =
    '안녕하세요 고객님, {매장명} 핸드폰 매장 핑크폰에서 안내드립니다.';

String buildContactMessage({
  required String customerName,
  String storeName = '',
  String template = defaultContactMessageTemplate,
}) {
  final name = customerName.trim().isEmpty ? '고객님' : customerName.trim();
  final normalizedTemplate =
      template.trim().isEmpty ? defaultContactMessageTemplate : template;
  final message = normalizedTemplate
      .replaceAll('{고객명}', name)
      .replaceAll('{매장명}', storeName.trim());
  // 매장명이 비어 있으면(전체 매장 보기 등) 토큰 자리의 이중 공백만 정리한다.
  return message.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
}
