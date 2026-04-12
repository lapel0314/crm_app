String normalizeStoreName(dynamic value) {
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty || raw == '-') return '';

  var normalized = raw
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll('매장', '')
      .replaceAll('지점', '')
      .replaceAll('점포', '');

  while (normalized.endsWith('점')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }

  if (normalized.isEmpty) return '';
  return '$normalized점';
}

bool isPrivilegedRole(dynamic role) {
  final text = role?.toString().trim() ?? '';
  return text == '대표' || text == '개발자';
}

bool isSameStore(dynamic a, dynamic b) {
  final left = normalizeStoreName(a);
  final right = normalizeStoreName(b);
  return left.isNotEmpty && left == right;
}
