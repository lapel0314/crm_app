import 'dart:async';
import 'dart:io' show exit;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crm_app/pages/login_page.dart';
import 'package:crm_app/services/update_service.dart';
import 'package:crm_app/utils/store_utils.dart';
import 'package:crm_app/widgets/app_layout.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://ysafjyubntkeorriywmu.supabase.co',
    anonKey: 'sb_publishable_LLt7Nx5xNWoROgTKD82YkA_eKtp-HLy',
  );

  try {
    await Supabase.instance.client.auth.signOut();
  } catch (e) {
    debugPrint('startup signOut skipped: $e');
  }

  runApp(const MyApp());
}

final supabase = Supabase.instance.client;

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '핑크폰 CRM',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ko', 'KR'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ko', 'KR'),
        Locale('en', 'US'),
      ],
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Pretendard',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFC94C6E),
          primary: const Color(0xFFC94C6E),
        ),
        scaffoldBackgroundColor: const Color(0xFFF4F5F8),
      ),
      home: const UpdateGate(child: AuthGate()),
    );
  }
}

class UpdateGate extends StatefulWidget {
  final Widget child;

  const UpdateGate({super.key, required this.child});

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  bool _checked = false;
  bool _updating = false;
  String _updateStatus = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkUpdate());
  }

  Future<void> _checkUpdate() async {
    if (_checked || !mounted) return;
    _checked = true;

    final updateService = UpdateService(supabase);
    final update = await updateService.checkForUpdate();
    if (update == null || !mounted) return;

    await _installUpdate(updateService, update);
  }

  Future<void> _installUpdate(
    UpdateService updateService,
    AppUpdateInfo update,
  ) async {
    setState(() {
      _updating = true;
      _updateStatus = '새 버전 ${update.version} 업데이트를 준비하고 있습니다.';
    });

    try {
      final installer = await updateService.downloadInstaller(update);
      if (!mounted) return;

      setState(() {
        _updateStatus = '설치 파일을 실행합니다. 앱이 자동으로 종료됩니다.';
      });

      await updateService.runInstaller(installer);
      exit(0);
    } catch (e) {
      debugPrint('update install failed: $e');
      if (!mounted) return;
      setState(() {
        _updating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_updating) return widget.child;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      body: Center(
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE8E9EF)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '업데이트 중',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _updateStatus,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: Color(0xFF6B7280),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 18),
              const LinearProgressIndicator(
                color: Color(0xFFC94C6E),
                backgroundColor: Color(0xFFF3F4F6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  Session? session;
  late final StreamSubscription<AuthState> _authSubscription;

  @override
  void initState() {
    super.initState();
    session = supabase.auth.currentSession;

    _authSubscription = supabase.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;
      setState(() {
        session = data.session;
      });
    });
  }

  Future<Map<String, dynamic>?> fetchProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return null;

    try {
      final profile = await supabase
          .from('profiles')
          .select('role, approval_status, store, name, phone')
          .eq('id', user.id)
          .maybeSingle();

      return profile;
    } catch (e) {
      debugPrint('fetchProfile error: $e');
      return null;
    }
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (session == null) {
      return const LoginPage();
    }

    return FutureBuilder<Map<String, dynamic>?>(
      future: fetchProfile(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final profile = snapshot.data;

        // 프로필이 없으면 공개용으로 보내지 말고 로그인 화면으로 복귀
        if (profile == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            await supabase.auth.signOut();
          });

          return const Scaffold(
            body: Center(
              child: Text('사용자 프로필을 찾을 수 없습니다. 다시 로그인해주세요.'),
            ),
          );
        }

        final approvalStatus =
            (profile['approval_status'] ?? 'pending').toString();
        final role = (profile['role'] ?? '').toString();
        final store = normalizeStoreName(profile['store']);

        if (approvalStatus != 'approved' || role.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            await supabase.auth.signOut();
          });

          return const Scaffold(
            body: Center(
              child: Text('승인되지 않았거나 권한 정보가 올바르지 않습니다.'),
            ),
          );
        }

        return AppLayout(role: role, store: store);
      },
    );
  }
}
