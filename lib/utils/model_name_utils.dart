String normalizeModelName(String value) {
  final text = value.trim();
  if (text.isEmpty) return text;

  final iphone = _normalizeIphoneModel(text);
  if (iphone != null) return iphone;

  if (RegExp(r'[가-힣]').hasMatch(text)) return text;
  if (RegExp(r'^A[0-9]{4}-[0-9]{3}$', caseSensitive: false).hasMatch(text)) {
    return text;
  }

  final compact = text.toUpperCase().replaceAll(RegExp(r'[\s_-]+'), '');
  final match =
      RegExp(r'^(?:SM)?([AFMLXS][0-9]{3,4})[A-Z0-9]*$').firstMatch(compact);
  if (match == null) return text;

  return 'SM-${match.group(1)}';
}

String? _normalizeIphoneModel(String value) {
  final compact = value
      .toLowerCase()
      .replaceAll('아이폰', 'iphone')
      .replaceAll('프로맥스', 'promax')
      .replaceAll('프로', 'pro')
      .replaceAll('플러스', 'plus')
      .replaceAll(RegExp(r'[\s_-]+'), '');

  final explicit = RegExp(
    r'^iphone([0-9]{1,2})(promax|pro|plus|e)?(?:[0-9]+(?:gb)?|1tb)?$',
  ).firstMatch(compact);
  if (explicit != null) {
    return _iphoneLabel(explicit.group(1)!, explicit.group(2) ?? '');
  }

  final shorthand = RegExp(
    r'^(?:aip)?([0-9]{2})(pm|pr|pro|max|pl|plus|e)?[a-z]*[0-9]*(?:gb|tb)?$',
  ).firstMatch(compact);
  if (shorthand != null) {
    return _iphoneLabel(shorthand.group(1)!, shorthand.group(2) ?? '');
  }

  return null;
}

String _iphoneLabel(String number, String suffix) {
  final normalizedSuffix = switch (suffix) {
    'pm' || 'promax' || 'max' => ' Pro Max',
    'pr' || 'pro' => ' Pro',
    'pl' || 'plus' => ' Plus',
    'e' => 'e',
    _ => '',
  };
  return 'iPhone $number$normalizedSuffix';
}
