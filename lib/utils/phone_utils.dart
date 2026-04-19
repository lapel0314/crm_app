String normalizePhoneNumber(String value) {
  final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length == 10 || digits.length == 11) return digits;
  return '';
}

String formatPhoneNumber(String value) {
  final digits = normalizePhoneNumber(value);
  if (digits.isEmpty) return value.trim();
  if (digits.length == 10) {
    return '${digits.substring(0, 3)}-${digits.substring(3, 6)}-${digits.substring(6)}';
  }
  return '${digits.substring(0, 3)}-${digits.substring(3, 7)}-${digits.substring(7)}';
}

bool hasUsablePhoneNumber(String value) =>
    normalizePhoneNumber(value).isNotEmpty;
