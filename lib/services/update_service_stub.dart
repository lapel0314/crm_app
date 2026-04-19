import 'update_service_base.dart';

class UpdateService extends UpdateServiceBase {
  const UpdateService(super.supabase);

  @override
  Future<AppUpdateInfo?> checkForUpdate() async => null;

  @override
  Future<void> startUpdate(AppUpdateInfo update) async {}
}
