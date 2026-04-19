const String defaultContactMessageTemplate = '안녕하세요 {고객명}님, 핑크폰 CRM에서 안내드립니다.';

String buildContactMessage({
  required String customerName,
  String template = defaultContactMessageTemplate,
}) {
  final name = customerName.trim().isEmpty ? '고객' : customerName.trim();
  return template.replaceAll('{고객명}', name);
}
