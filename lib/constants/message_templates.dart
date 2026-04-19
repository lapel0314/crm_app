const String defaultContactMessageTemplate =
    '안녕하세요 고객님, 이대역점 핸드폰 매장 핑크폰에서 안내드립니다.';

String buildContactMessage({
  required String customerName,
  String template = defaultContactMessageTemplate,
}) {
  final name = customerName.trim().isEmpty ? '고객님' : customerName.trim();
  final normalizedTemplate =
      template.trim().isEmpty ? defaultContactMessageTemplate : template;
  return normalizedTemplate
      .replaceAll('{고객명}', name)
      .replaceAll('{매장명}', '이대역점');
}
