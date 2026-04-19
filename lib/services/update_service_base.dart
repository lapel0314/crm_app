import 'package:supabase_flutter/supabase_flutter.dart';

const String installerPassword = String.fromEnvironment(
  'INSTALLER_PASSWORD',
  defaultValue: '123456',
);

class AppUpdateInfo {
  final String platform;
  final String currentVersion;
  final String latestVersion;
  final String minRequiredVersion;
  final String packageUrl;
  final String message;
  final bool isRequired;

  const AppUpdateInfo({
    required this.platform,
    required this.currentVersion,
    required this.latestVersion,
    required this.minRequiredVersion,
    required this.packageUrl,
    required this.message,
    required this.isRequired,
  });
}

abstract class UpdateServiceBase {
  final SupabaseClient supabase;

  const UpdateServiceBase(this.supabase);

  Future<AppUpdateInfo?> checkForUpdate();

  Future<void> startUpdate(AppUpdateInfo update);

  int compareVersions(String left, String right) {
    final leftParts = left.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final rightParts =
        right.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final length = leftParts.length > rightParts.length
        ? leftParts.length
        : rightParts.length;

    for (var i = 0; i < length; i++) {
      final leftValue = i < leftParts.length ? leftParts[i] : 0;
      final rightValue = i < rightParts.length ? rightParts[i] : 0;
      if (leftValue != rightValue) return leftValue.compareTo(rightValue);
    }
    return 0;
  }
}
