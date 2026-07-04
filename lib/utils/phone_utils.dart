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

String formatPartialPhoneNumber(String value) {
  final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length <= 3) return digits;
  if (digits.length <= 7) {
    return '${digits.substring(0, 3)}-${digits.substring(3)}';
  }
  final cut = digits.length > 11 ? 11 : digits.length;
  return '${digits.substring(0, 3)}-${digits.substring(3, 7)}-${digits.substring(7, cut)}';
}

bool isValidKoreanMobilePhoneNumber(String value) {
  return RegExp(r'^01[0-9]-\d{3,4}-\d{4}$').hasMatch(value.trim());
}

bool hasUsablePhoneNumber(String value) =>
    normalizePhoneNumber(value).isNotEmpty;
