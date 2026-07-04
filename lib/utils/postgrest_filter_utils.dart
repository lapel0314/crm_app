String postgrestIlikeFilter(String column, String value) {
  final escaped = value.trim().replaceAll('\\', '\\\\').replaceAll('"', r'\"');
  return '$column.ilike."%$escaped%"';
}

String postgrestIlikeAnyFilter(Iterable<String> columns, String value) {
  final text = value.trim();
  if (text.isEmpty) return '';
  return columns.map((column) => postgrestIlikeFilter(column, text)).join(',');
}
