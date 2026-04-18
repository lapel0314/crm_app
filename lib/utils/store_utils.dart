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

bool isManagerRole(dynamic role) {
  return role?.toString().trim() == '점장';
}

bool isStaffRole(dynamic role) {
  return role?.toString().trim() == '사원';
}

bool isReadOnlyRole(dynamic role) {
  return role?.toString().trim() == '조회용';
}

bool canUseCustomerDb(dynamic role) {
  return isPrivilegedRole(role) || isManagerRole(role);
}

bool canUseOpenCustomerDb(dynamic role) {
  return isReadOnlyRole(role);
}

bool canUseLeads(dynamic role) {
  return isPrivilegedRole(role) || isManagerRole(role);
}

bool canUseWiredMembers(dynamic role) {
  return isPrivilegedRole(role) || isManagerRole(role);
}

bool canUseDashboard(dynamic role) {
  return isPrivilegedRole(role) || isManagerRole(role);
}

bool canUseInventory(dynamic role) {
  return isPrivilegedRole(role) || isManagerRole(role) || isReadOnlyRole(role);
}

bool canManageInventory(dynamic role) {
  return isPrivilegedRole(role) || isManagerRole(role);
}

bool canUseGlobalSearch(dynamic role) {
  return isPrivilegedRole(role) || isManagerRole(role);
}

bool canViewRebate(dynamic role) {
  return isPrivilegedRole(role) || isManagerRole(role) || isStaffRole(role);
}

bool canManageRateCards(dynamic role) {
  return isPrivilegedRole(role);
}

bool isSameStore(dynamic a, dynamic b) {
  final left = normalizeStoreName(a);
  final right = normalizeStoreName(b);
  return left.isNotEmpty && left == right;
}
