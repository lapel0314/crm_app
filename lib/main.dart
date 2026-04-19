import 'dart:async';
import 'dart:io' show Platform, exit;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crm_app/pages/login_page.dart';
import 'package:crm_app/services/update_service.dart';
import 'package:crm_app/utils/store_utils.dart';
import 'package:crm_app/widgets/app_layout.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    runApp(const ConfigErrorApp());
    return;
  }

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      localStorage: EmptyLocalStorage(),
    ),
  );

  try {
    await Supabase.instance.client.auth.signOut();
  } catch (e) {
    debugPrint('startup signOut skipped: $e');
  }

  runApp(const MyApp());
}

final supabase = Supabase.instance.client;

class ConfigErrorApp extends StatelessWidget {
  const ConfigErrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Supabase ?ㅼ젙???놁뒿?덈떎. SUPABASE_URL / SUPABASE_ANON_KEY瑜?dart-define?쇰줈 ?꾨떖?댁＜?몄슂.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '?묓겕??CRM',
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
  bool _ready = false;
  bool _failed = false;
  bool _isUpdating = false;
  AppUpdateInfo? _blockedUpdate;
  String _updateStatus = '업데이트 버전을 확인하고 있습니다.';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkUpdate());
  }

  Future<void> _checkUpdate() async {
    if (_checked || !mounted) return;
    _checked = true;

    final updateService = UpdateService(supabase);
    try {
      final update = await updateService.checkForUpdate();
      if (!mounted) return;

      if (update == null) {
        setState(() {
          _ready = true;
          _blockedUpdate = null;
        });
        return;
      }

      setState(() {
        _failed = false;
        _blockedUpdate = update;
        _updateStatus = update.message;
      });
    } catch (e) {
      debugPrint('forced update check failed: $e');
      if (!mounted) return;
      setState(() {
        _failed = true;
        _updateStatus = '업데이트 확인에 실패했습니다. 인터넷 연결을 확인한 뒤 다시 시도해주세요.';
      });
    }
  }

  Future<void> _startUpdate(
    UpdateService updateService,
    AppUpdateInfo update,
  ) async {
    setState(() {
      _failed = false;
      _isUpdating = true;
      _updateStatus = update.platform == 'android'
          ? 'APK 다운로드 페이지를 여는 중입니다.'
          : '새 버전 ${update.latestVersion} 업데이트를 준비하고 있습니다.';
    });

    try {
      await updateService.startUpdate(update);
      if (!mounted) return;
      if (Platform.isWindows) {
        exit(0);
      }
      setState(() {
        _isUpdating = false;
        _updateStatus = '다운로드한 APK를 설치한 뒤 앱을 다시 실행해주세요.';
      });
    } catch (e) {
      debugPrint('update install failed: $e');
      if (!mounted) return;
      setState(() {
        _isUpdating = false;
        _failed = true;
        _updateStatus = '업데이트를 시작하지 못했습니다. 다시 시도해주세요.';
      });
    }
  }

  void _retryCheck() {
    setState(() {
      _checked = false;
      _failed = false;
      _blockedUpdate = null;
      _updateStatus = '업데이트 버전을 확인하고 있습니다.';
    });
    _checkUpdate();
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.child;
    final blockedUpdate = _blockedUpdate;
    final updateService = UpdateService(supabase);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F8),
      body: Center(
        child: Container(
          width: 420,
          constraints: const BoxConstraints(maxWidth: 420),
          margin: const EdgeInsets.all(18),
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
                '업데이트 확인',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111827),
                ),
              ),
              if (blockedUpdate != null) ...[
                const SizedBox(height: 12),
                _UpdateVersionRow(
                    label: '현재 버전', value: blockedUpdate.currentVersion),
                _UpdateVersionRow(
                    label: '필수 버전', value: blockedUpdate.minRequiredVersion),
                _UpdateVersionRow(
                    label: '최신 버전', value: blockedUpdate.latestVersion),
              ],
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
              if (blockedUpdate != null) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isUpdating
                        ? null
                        : () => _startUpdate(updateService, blockedUpdate),
                    icon: const Icon(Icons.system_update_alt_rounded),
                    label: Text(_isUpdating ? '업데이트 준비 중' : '업데이트'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFC94C6E),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _isUpdating ? null : _retryCheck,
                    child: const Text('다시 확인'),
                  ),
                ),
              ] else if (_failed)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _retryCheck,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFC94C6E),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('다시 시도'),
                  ),
                )
              else
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

class _UpdateVersionRow extends StatelessWidget {
  final String label;
  final String value;

  const _UpdateVersionRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Color(0xFF111827),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
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

        // ?꾨줈?꾩씠 ?놁쑝硫?怨듦컻?⑹쑝濡?蹂대궡吏 留먭퀬 濡쒓렇???붾㈃?쇰줈 蹂듦?
        if (profile == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            await supabase.auth.signOut();
          });

          return const Scaffold(
            body: Center(
              child: Text('?ъ슜???꾨줈?꾩쓣 李얠쓣 ???놁뒿?덈떎. ?ㅼ떆 濡쒓렇?명빐二쇱꽭??'),
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
              child: Text('?뱀씤?섏? ?딆븯嫄곕굹 沅뚰븳 ?뺣낫媛 ?щ컮瑜댁? ?딆뒿?덈떎.'),
            ),
          );
        }

        return AppLayout(role: role, store: store);
      },
    );
  }
}
