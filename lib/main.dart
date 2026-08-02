import 'dart:async';
import 'dart:io' show Platform, exit;

import 'package:crm_app/pages/login_page.dart';
import 'package:crm_app/services/desktop_auth_session_service.dart';
import 'package:crm_app/services/login_policy_service.dart';
import 'package:crm_app/services/update_service.dart';
import 'package:crm_app/utils/store_utils.dart';
import 'package:crm_app/widgets/app_layout.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const BootstrapApp());
}

class BootstrapApp extends StatefulWidget {
  const BootstrapApp({super.key});

  @override
  State<BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<BootstrapApp> {
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
    const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      if (!mounted) return;
      setState(() {
        _error = ConfigErrorApp.configErrorMessage;
      });
      return;
    }

    try {
      await DesktopAuthSessionService.clearPersistedSession();

      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseAnonKey,
        authOptions: DesktopAuthSessionService.authOptions,
      ).timeout(const Duration(seconds: 10));

      await DesktopAuthSessionService.clearPersistedSession();

      if (!mounted) return;
      setState(() {
        _ready = true;
      });
    } catch (e) {
      debugPrint('startup initialize failed: $e');
      if (!mounted) return;
      setState(() {
        _error = 'CRM 초기화에 실패했습니다.\n네트워크 연결을 확인한 뒤 앱을 다시 실행해 주세요.\n\n$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return const MyApp();
    return StartupStatusApp(message: _error);
  }
}

class StartupStatusApp extends StatelessWidget {
  final String? message;

  const StartupStatusApp({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('ko', 'KR'),
      home: Scaffold(
        backgroundColor: const Color(0xFFF4F5F8),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '핑크폰 CRM',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (message == null) ...[
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        const Text('CRM을 시작하고 있습니다.'),
                      ] else ...[
                        const Icon(
                          Icons.error_outline,
                          color: Colors.redAccent,
                          size: 40,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          message!,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final supabase = Supabase.instance.client;

class ConfigErrorApp extends StatelessWidget {
  const ConfigErrorApp({super.key});

  static const configErrorMessage =
      'Supabase \uC124\uC815\uC774 \uC5C6\uC2B5\uB2C8\uB2E4. '
      'SUPABASE_URL / SUPABASE_ANON_KEY\uB97C dart-define\uC73C\uB85C '
      '\uC804\uB2EC\uD574 \uC8FC\uC138\uC694.';

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              configErrorMessage,
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
      title: '\uD551\uD06C\uD3F0 CRM',
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

class _UpdateGateState extends State<UpdateGate> with WidgetsBindingObserver {
  static const Duration _resumeUpdateCheckCooldown = Duration(minutes: 10);

  bool _checked = false;
  bool _ready = false;
  bool _failed = false;
  bool _isUpdating = false;
  bool _checkInProgress = false;
  bool _needsLoginForUpdate = false;
  DateTime? _lastUpdateCheckAt;
  AppUpdateInfo? _blockedUpdate;
  String _updateStatus =
      '\uC5C5\uB370\uC774\uD2B8 \uBC84\uC804\uC744 \uD655\uC778\uD558\uACE0 \uC788\uC2B5\uB2C8\uB2E4.';
  late final StreamSubscription<AuthState> _authSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkUpdate());
    // storagePath \uAE30\uBC18(\uBE44\uACF5\uAC1C \uC2A4\uD1A0\uB9AC\uC9C0) \uC5C5\uB370\uC774\uD2B8 \uB2E4\uC6B4\uB85C\uB4DC\uB294 \uB85C\uADF8\uC778 \uC138\uC158\uC774 \uC788\uC5B4\uC57C
    // signed URL\uC744 \uBC1B\uC744 \uC218 \uC788\uB2E4. \uAC15\uC81C \uC5C5\uB370\uC774\uD2B8 \uD654\uBA74\uC740 AuthGate\uBCF4\uB2E4 \uBA3C\uC800 \uB728\uBBC0\uB85C,
    // \uB85C\uADF8\uC778 \uC131\uACF5\uC744 \uAC10\uC9C0\uD574 \uC5C5\uB370\uC774\uD2B8 \uC7AC\uC2DC\uB3C4\uB97C \uC774\uC5B4\uAC04\uB2E4.
    _authSubscription = supabase.auth.onAuthStateChange.listen((data) {
      if (!mounted || !_needsLoginForUpdate || data.session == null) return;
      final blockedUpdate = _blockedUpdate;
      setState(() {
        _needsLoginForUpdate = false;
      });
      if (blockedUpdate != null) {
        unawaited(_startUpdate(UpdateService(supabase), blockedUpdate));
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_ready || _isUpdating) return;
    final lastCheckedAt = _lastUpdateCheckAt;
    if (lastCheckedAt != null &&
        DateTime.now().difference(lastCheckedAt) < _resumeUpdateCheckCooldown) {
      return;
    }
    unawaited(_checkUpdate(force: true));
  }

  Future<void> _checkUpdate({bool force = false}) async {
    if (_checkInProgress || (!force && _checked) || !mounted) return;
    _checked = true;
    _checkInProgress = true;
    _lastUpdateCheckAt = DateTime.now();

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
        _ready = false;
        _blockedUpdate = update;
        _updateStatus = update.message;
      });
    } catch (e) {
      debugPrint('forced update check failed: $e');
      if (!mounted) return;
      // 업데이트 서버/RLS/네트워크 일시 오류 때문에 앱 실행 자체가 막히면
      // 정상 네트워크 사용자도 로그인 화면에 진입하지 못한다.
      // 실제 네트워크 장애는 로그인/Supabase 요청 단계에서 다시 드러나므로,
      // 업데이트 확인 실패는 차단하지 않고 앱을 계속 실행한다.
      setState(() {
        _failed = false;
        _blockedUpdate = null;
        _ready = true;
      });
    } finally {
      _checkInProgress = false;
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
          ? 'APK \uB2E4\uC6B4\uB85C\uB4DC \uD398\uC774\uC9C0\uB97C \uC5EC\uB294 \uC911\uC785\uB2C8\uB2E4.'
          : '\uC0C8 \uBC84\uC804 ${update.latestVersion} '
              '\uC5C5\uB370\uC774\uD2B8\uB97C \uC900\uBE44\uD558\uACE0 \uC788\uC2B5\uB2C8\uB2E4.';
    });

    try {
      await updateService.startUpdate(update);
      if (!mounted) return;
      if (Platform.isWindows) {
        exit(0);
      }
      if (Platform.isAndroid) {
        // \uB2E4\uC6B4\uB85C\uB4DC \uD398\uC774\uC9C0\uB97C \uC5F0 \uB4A4 \uAD6C\uBC84\uC804 \uD504\uB85C\uC138\uC2A4\uB97C \uC885\uB8CC\uD55C\uB2E4 \u2014 \uC124\uCE58\uD558\uB294 \uB3D9\uC548
        // \uC774\uC804 \uBC84\uC804\uC774 \uBC31\uADF8\uB77C\uC6B4\uB4DC\uC5D0 \uACC4\uC18D \uB5A0 \uC788\uC5B4 \uC0C8 \uBC84\uC804\uACFC \uB3D9\uC2DC\uC5D0 \uBCF4\uC774\uB358 \uBB38\uC81C.
        setState(() {
          _isUpdating = false;
          _updateStatus = '\uB2E4\uC6B4\uB85C\uB4DC\uD55C APK\uB97C \uC124\uCE58\uD55C \uB4A4 \uC571\uC744 \uB2E4\uC2DC \uC2E4\uD589\uD574 \uC8FC\uC138\uC694.';
        });
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        await SystemNavigator.pop();
        return;
      }
      setState(() {
        _isUpdating = false;
        _updateStatus =
            '\uB2E4\uC6B4\uB85C\uB4DC\uD55C APK\uB97C \uC124\uCE58\uD55C \uB4A4 '
            '\uC571\uC744 \uB2E4\uC2DC \uC2E4\uD589\uD574 \uC8FC\uC138\uC694.';
      });
    } on UpdateAuthRequiredException {
      if (!mounted) return;
      setState(() {
        _isUpdating = false;
        _needsLoginForUpdate = true;
        _updateStatus = '\uC5C5\uB370\uC774\uD2B8 \uD30C\uC77C\uC744 \uBC1B\uC73C\uB824\uBA74 \uBA3C\uC800 \uB85C\uADF8\uC778\uD574 \uC8FC\uC138\uC694.';
      });
    } catch (e) {
      debugPrint('update install failed: $e');
      if (!mounted) return;
      setState(() {
        _isUpdating = false;
        _failed = true;
        _updateStatus =
            '\uC5C5\uB370\uC774\uD2B8\uB97C \uC2DC\uC791\uD558\uC9C0 \uBABB\uD588\uC2B5\uB2C8\uB2E4. '
            '\uB2E4\uC2DC \uC2DC\uB3C4\uD574 \uC8FC\uC138\uC694.';
      });
    }
  }

  void _retryCheck() {
    setState(() {
      _checked = false;
      _failed = false;
      _blockedUpdate = null;
      _updateStatus =
          '\uC5C5\uB370\uC774\uD2B8 \uBC84\uC804\uC744 \uD655\uC778\uD558\uACE0 \uC788\uC2B5\uB2C8\uB2E4.';
    });
    _checkUpdate();
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.child;
    if (_needsLoginForUpdate) return const LoginPage();
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
                '\uC5C5\uB370\uC774\uD2B8 \uD655\uC778',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111827),
                ),
              ),
              if (blockedUpdate != null) ...[
                const SizedBox(height: 12),
                _UpdateVersionRow(
                  label: '\uD604\uC7AC \uBC84\uC804',
                  value: blockedUpdate.currentVersion,
                ),
                _UpdateVersionRow(
                  label: '\uD544\uC218 \uBC84\uC804',
                  value: blockedUpdate.minRequiredVersion,
                ),
                _UpdateVersionRow(
                  label: '\uCD5C\uC2E0 \uBC84\uC804',
                  value: blockedUpdate.latestVersion,
                ),
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
                    label: Text(
                      _isUpdating
                          ? '\uC5C5\uB370\uC774\uD2B8 \uC900\uBE44 \uC911'
                          : '\uC5C5\uB370\uC774\uD2B8',
                    ),
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
                    child: const Text('\uB2E4\uC2DC \uD655\uC778'),
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
                    child: const Text('\uB2E4\uC2DC \uC2DC\uB3C4'),
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

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  Session? session;
  late final StreamSubscription<AuthState> _authSubscription;
  final loginPolicyService = LoginPolicyService(supabase);
  Future<Map<String, dynamic>?>? _profileFuture;
  Timer? _policyCheckTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _networkChangeDebounce;
  String? _authErrorMessage;
  bool _logoutScheduled = false;
  bool _policyCheckInProgress = false;
  bool _profileErrorTransient = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    session = supabase.auth.currentSession;
    if (session != null) {
      _profileFuture = fetchProfile();
      _startPolicyCheckTimer();
      _startNetworkChangeMonitor();
    }

    _authSubscription = supabase.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;
      setState(() {
        session = data.session;
        _profileFuture = session == null ? null : fetchProfile();
      });
      if (data.session == null) {
        _stopPolicyCheckTimer();
        _stopNetworkChangeMonitor();
      } else {
        _startPolicyCheckTimer();
        _startNetworkChangeMonitor();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPolicyWhileActive();
    }
  }

  void _startPolicyCheckTimer() {
    _policyCheckTimer?.cancel();
    _policyCheckTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _checkPolicyWhileActive(),
    );
  }

  void _stopPolicyCheckTimer() {
    _policyCheckTimer?.cancel();
    _policyCheckTimer = null;
    _policyCheckInProgress = false;
  }

  void _startNetworkChangeMonitor() {
    if (_connectivitySubscription != null) return;
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (results) {
        if (results.contains(ConnectivityResult.none)) return;
        debugPrint('network changed: $results');
        _networkChangeDebounce?.cancel();
        _networkChangeDebounce = Timer(
          const Duration(seconds: 2),
          _checkPolicyWhileActive,
        );
      },
    );
  }

  void _stopNetworkChangeMonitor() {
    _networkChangeDebounce?.cancel();
    _networkChangeDebounce = null;
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
  }

  Future<void> _checkPolicyWhileActive() async {
    if (_policyCheckInProgress || supabase.auth.currentUser == null) return;
    _policyCheckInProgress = true;

    try {
      await loginPolicyService.checkLoginPolicy();
    } on LoginPolicyException catch (e) {
      // 정책이 명시적으로 거부한 경우만 로그아웃한다 (사원 IP 차단 등).
      debugPrint('active login policy denied: $e');
      _authErrorMessage = e.message;
      _scheduleSignOutOnce();
    } catch (e) {
      // 일시적 네트워크/서버 오류로는 세션을 유지한다. 다음 주기(1분) 또는
      // 네트워크 변경 시 재검사되며, 진짜 거부라면 그때 로그아웃된다.
      // (지하철/엘리베이터 같은 순간 끊김마다 로그아웃되던 문제의 수정)
      debugPrint('active login policy check failed (transient, kept): $e');
    } finally {
      _policyCheckInProgress = false;
    }
  }

  Future<Map<String, dynamic>?> fetchProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return null;

    try {
      _authErrorMessage = null;
      _profileErrorTransient = false;
      final decision = await loginPolicyService.checkLoginPolicy();
      final profile = await supabase
          .from('profiles')
          .select(
            'role, role_code, approval_status, store, store_id, name, phone',
          )
          .eq('id', user.id)
          .maybeSingle();

      if (profile == null) return null;

      return {
        ...profile,
        'role': decision.role ?? profile['role_code'] ?? profile['role'],
        'store': decision.storeName ?? profile['store'],
        'store_id': decision.storeId ?? profile['store_id'],
      };
    } on LoginPolicyException catch (e) {
      debugPrint('fetchProfile policy denied: $e');
      _authErrorMessage = e.message;
      return null;
    } catch (e) {
      // 일시적 네트워크/서버 오류 — 세션을 지우지 않고 재시도 화면을 보여준다.
      debugPrint('fetchProfile transient error: $e');
      _authErrorMessage = e.toString().replaceFirst('Exception: ', '');
      _profileErrorTransient = true;
      return null;
    }
  }

  void _scheduleSignOutOnce() {
    if (_logoutScheduled) return;
    _logoutScheduled = true;
    _stopPolicyCheckTimer();
    _stopNetworkChangeMonitor();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await DesktopAuthSessionService.signOutAndClear(supabase);
      if (mounted) {
        setState(() {
          _logoutScheduled = false;
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPolicyCheckTimer();
    _stopNetworkChangeMonitor();
    _authSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (session == null) {
      return const LoginPage();
    }

    return FutureBuilder<Map<String, dynamic>?>(
      future: _profileFuture ??= fetchProfile(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final profile = snapshot.data;

        if (profile == null) {
          // \uC77C\uC2DC\uC801 \uC624\uB958(\uB124\uD2B8\uC6CC\uD06C \uB4F1)\uB294 \uC138\uC158\uC744 \uC9C0\uC6B0\uC9C0 \uC54A\uACE0 \uC7AC\uC2DC\uB3C4\uB9CC \uD5C8\uC6A9\uD55C\uB2E4.
          if (_profileErrorTransient) {
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '\uB124\uD2B8\uC6CC\uD06C \uC5F0\uACB0\uC744 \uD655\uC778\uD574 \uC8FC\uC138\uC694.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _profileFuture = fetchProfile();
                          });
                        },
                        icon: const Icon(Icons.refresh_rounded, size: 17),
                        label: const Text('\uB2E4\uC2DC \uC2DC\uB3C4'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFC94C6E),
                          foregroundColor: Colors.white,
                          elevation: 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          final message = _authErrorMessage ??
              '\uD504\uB85C\uD544 \uC815\uBCF4\uB97C \uBD88\uB7EC\uC624\uC9C0 '
                  '\uBABB\uD588\uC2B5\uB2C8\uB2E4. \uB2E4\uC2DC \uB85C\uADF8\uC778\uD574 '
                  '\uC8FC\uC138\uC694.';
          _scheduleSignOutOnce();

          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        final approvalStatus =
            (profile['approval_status'] ?? 'pending').toString();
        final role = (profile['role'] ?? '').toString();
        final store = normalizeStoreName(profile['store']);

        if (approvalStatus != 'approved' || role.isEmpty) {
          _scheduleSignOutOnce();

          return const Scaffold(
            body: Center(
              child: Text(
                '\uC2B9\uC778\uB418\uC9C0 \uC54A\uC740 \uACC4\uC815\uC785\uB2C8\uB2E4. '
                '\uAD00\uB9AC\uC790 \uC2B9\uC778 \uD6C4 \uB2E4\uC2DC '
                '\uB85C\uADF8\uC778\uD574 \uC8FC\uC138\uC694.',
              ),
            ),
          );
        }

        return AppLayout(role: role, store: store);
      },
    );
  }
}
