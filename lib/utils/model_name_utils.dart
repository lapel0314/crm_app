class ModelNameMapping {
  final String displayName;
  final List<String> registeredNames;
  final bool isActive;

  const ModelNameMapping({
    required this.displayName,
    required this.registeredNames,
    this.isActive = true,
  });

  factory ModelNameMapping.fromJson(Map<String, dynamic> json) {
    return ModelNameMapping(
      displayName: json['display_name']?.toString().trim() ?? '',
      registeredNames: (json['registered_names'] as List<dynamic>? ?? const [])
          .map((value) => value.toString().trim())
          .where((value) => value.isNotEmpty)
          .toList(),
      isActive: json['is_active'] != false,
    );
  }
}

String modelAliasKey(dynamic value) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty || text == '-') return '';

  return text
      .toLowerCase()
      .replaceAll('아이폰', 'iphone')
      .replaceAll('프로맥스', 'promax')
      .replaceAll('프로', 'pro')
      .replaceAll('플러스', 'plus')
      .replaceAll(RegExp(r'[\s_\-./]+'), '');
}

Map<String, String> buildModelAliasLookup(Iterable<ModelNameMapping> mappings) {
  final lookup = <String, String>{};
  for (final mapping in mappings) {
    if (!mapping.isActive || mapping.displayName.isEmpty) continue;

    final displayKey = modelAliasKey(mapping.displayName);
    if (displayKey.isNotEmpty) {
      lookup[displayKey] = mapping.displayName;
    }

    for (final alias in mapping.registeredNames) {
      final key = modelAliasKey(alias);
      if (key.isNotEmpty) {
        lookup[key] = mapping.displayName;
      }
    }
  }
  return lookup;
}

String normalizeModelNameWithAliases(
  String value,
  Map<String, String> aliasLookup,
) {
  final mapped = aliasLookup[modelAliasKey(value)];
  if (mapped != null && mapped.trim().isNotEmpty) return mapped;
  return normalizeModelName(value);
}

String normalizeModelName(String value) {
  final text = value.trim();
  if (text.isEmpty) return text;

  final iphone = _normalizeIphoneModel(text);
  if (iphone != null) return iphone;

  final samsung = _normalizeSamsungModel(text);
  if (samsung != null) return samsung;

  if (RegExp(r'[가-힣]').hasMatch(text)) return text;
  if (RegExp(r'^A[0-9]{4}-[0-9]{3}$', caseSensitive: false).hasMatch(text)) {
    return text;
  }

  return text;
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
    r'^iphone([0-9]{1,2})(pm|pr|promax|pro|max|plus|pl|e)?(?:[a-z])?(128|256|512|1024|1tb|2tb)?(?:gb|tb)?$',
  ).firstMatch(compact);
  if (explicit != null) {
    return _iphoneLabel(
      explicit.group(1)!,
      explicit.group(2) ?? '',
      _storageLabel(explicit.group(3)),
    );
  }

  final shorthand = RegExp(
    r'^(?:aip)?([0-9]{2})(pm|pr|promax|pro|max|pl|plus|e)?(?:[a-z])?(128|256|512|1024|1tb|2tb)?(?:gb|tb)?$',
  ).firstMatch(compact);
  if (shorthand != null) {
    return _iphoneLabel(
      shorthand.group(1)!,
      shorthand.group(2) ?? '',
      _storageLabel(shorthand.group(3)),
    );
  }

  return null;
}

String _iphoneLabel(String number, String suffix, String storage) {
  final normalizedSuffix = switch (suffix) {
    'pm' || 'promax' || 'max' => ' 프로 맥스',
    'pr' || 'pro' => ' 프로',
    'pl' || 'plus' => ' 플러스',
    'e' => 'e',
    _ => '',
  };
  return '아이폰 $number$normalizedSuffix $storage';
}

String? _normalizeSamsungModel(String value) {
  final korean = _normalizeKoreanSamsungModel(value);
  if (korean != null) return korean;

  if (RegExp(r'^A[0-9]{4}-[0-9]{3}$', caseSensitive: false).hasMatch(value)) {
    return null;
  }

  final compact = value.toUpperCase().replaceAll(RegExp(r'[\s_-]+'), '');
  final match =
      RegExp(r'^(?:SM|AT)?([AFMLXS][0-9]{3,4})[A-Z0-9]*$').firstMatch(compact);
  if (match == null) return null;

  final code = match.group(1)!;
  final label = _samsungModelLabels[code] ?? '갤럭시 SM-$code';
  if (_samsungNoStorageCodes.contains(code)) return label;
  return '$label ${_storageFromCompact(compact)}';
}

String? _normalizeKoreanSamsungModel(String value) {
  final compact = value
      .toUpperCase()
      .replaceAll('갤럭시', '')
      .replaceAll(RegExp(r'[\s_-]+'), '');

  final sSeries = RegExp(
    r'^S([0-9]{2})(울트라|ULTRA|플러스|PLUS|FE|엣지|EDGE)?(128|256|512|1024)?(?:GB)?$',
  ).firstMatch(compact);
  if (sSeries != null) {
    final suffix = switch (sSeries.group(2)) {
      '울트라' || 'ULTRA' => ' 울트라',
      '플러스' || 'PLUS' => ' 플러스',
      '엣지' || 'EDGE' => ' 엣지',
      'FE' => ' FE',
      _ => '',
    };
    return '갤럭시 S${sSeries.group(1)}$suffix ${_storageLabel(sSeries.group(3))}';
  }

  final simple = RegExp(
    r'^([AFM])([0-9]{2})(128|256|512|1024)?(?:GB)?$',
  ).firstMatch(compact);
  if (simple != null) {
    return '갤럭시 ${simple.group(1)}${simple.group(2)} ${_storageLabel(simple.group(3))}';
  }

  return null;
}

String _storageFromCompact(String compact) {
  final storage =
      RegExp(r'(128|256|512|1024|1TB|2TB)(?:GB|TB)?$').firstMatch(compact);
  return _storageLabel(storage?.group(1));
}

String _storageLabel(String? value) {
  if (value == null || value.isEmpty) return '256GB';
  final upper = value.toUpperCase();
  if (upper.endsWith('TB')) return upper;
  if (upper == '1024') return '1TB';
  return '${upper}GB';
}

const _samsungModelLabels = {
  'A166': '갤럭시 A16',
  'A175': '갤럭시 A17',
  'A176': '갤럭시 A17',
  'F741': '갤럭시 Z 플립6',
  'F766': '갤럭시 Z 플립7',
  'M140': '스타일폴더2',
  'M166': '갤럭시 M16',
  'M366': '갤럭시 M36',
  'S721': '갤럭시 S24 FE',
  'S731': '갤럭시 S25 FE',
  'S937': '갤럭시 S25 엣지',
  'S938': '갤럭시 S25 울트라',
  'S942': '갤럭시 S26',
  'S947': '갤럭시 S26 플러스',
  'S948': '갤럭시 S26 울트라',
  'X216': '갤럭시 탭 A9+',
};

const _samsungNoStorageCodes = {
  'M140',
  'L325',
  'L335',
  'X216',
};
