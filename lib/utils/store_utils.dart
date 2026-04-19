const String roleOwner = '대표';
const String roleDeveloper = '개발자';
const String roleManager = '점장';
const String roleStaff = '사원';
const String roleReadOnly = '조회용';

String normalizeStoreName(dynamic value) {
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty || raw == '-') return '';

  var normalized = raw
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll('매장', '')
      .replaceAll('지점', '')
      .replaceAll('스토어', '');

  if (normalized.isEmpty) return '';
  if (!normalized.endsWith('점')) {
    normalized = '$normalized점';
  }
  return normalized;
}

String normalizeRole(dynamic role) {
  final text = role?.toString().trim() ?? '';
  switch (text) {
    case roleOwner:
    case roleDeveloper:
    case roleManager:
    case roleStaff:
    case roleReadOnly:
      return text;
    default:
      return text;
  }
}

bool isPrivilegedRole(dynamic role) {
  final text = normalizeRole(role);
  return text == roleOwner || text == roleDeveloper;
}

bool isManagerRole(dynamic role) {
  return normalizeRole(role) == roleManager;
}

bool isStaffRole(dynamic role) {
  return normalizeRole(role) == roleStaff;
}

bool isReadOnlyRole(dynamic role) {
  return normalizeRole(role) == roleReadOnly;
}

bool canUseCustomerRegistration(dynamic role) {
  return isPrivilegedRole(role) ||
      isManagerRole(role) ||
      isStaffRole(role) ||
      isReadOnlyRole(role);
}

bool canUseCustomerDb(dynamic role) {
  return isPrivilegedRole(role) || isManagerRole(role) || isStaffRole(role);
}

bool canDeleteCustomer(dynamic role) {
  return isPrivilegedRole(role) || isManagerRole(role);
}

bool canUseOpenCustomerDb(dynamic role) {
  return isReadOnlyRole(role);
}

bool canUseLeads(dynamic role) {
  return isPrivilegedRole(role) || isManagerRole(role) || isStaffRole(role);
}

bool canDeleteLead(dynamic role) {
  return isPrivilegedRole(role) || isManagerRole(role);
}

bool canUseWiredMembers(dynamic role) {
  return isPrivilegedRole(role) || isManagerRole(role) || isStaffRole(role);
}

bool canDeleteWiredMember(dynamic role) {
  return isPrivilegedRole(role) || isManagerRole(role);
}

bool canUseDashboard(dynamic role) {
  return isPrivilegedRole(role) || isManagerRole(role);
}

bool canUseInventory(dynamic role) {
  return isPrivilegedRole(role) || isManagerRole(role);
}

bool canManageInventory(dynamic role) {
  return isPrivilegedRole(role) || isManagerRole(role);
}

bool canUseGlobalSearch(dynamic role) {
  return isPrivilegedRole(role);
}

bool canViewRebate(dynamic role) {
  return isPrivilegedRole(role);
}

bool canManageRateCards(dynamic role) {
  return isPrivilegedRole(role);
}

bool canUseSettings(dynamic role) {
  return isPrivilegedRole(role) || isManagerRole(role) || isStaffRole(role);
}

bool canManageNetworks(dynamic role) {
  return isPrivilegedRole(role) || isManagerRole(role);
}

bool isSameStore(dynamic a, dynamic b) {
  final left = normalizeStoreName(a);
  final right = normalizeStoreName(b);
  return left.isNotEmpty && left == right;
}
