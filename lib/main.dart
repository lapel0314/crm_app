import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crm_app/pages/login_page.dart';
import 'package:crm_app/widgets/app_layout.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://ysafjyubntkeorriywmu.supabase.co',
    anonKey: 'sb_publishable_LLt7Nx5xNWoROgTKD82YkA_eKtp-HLy',
  );

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
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Pretendard',
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF2D8D)),
        scaffoldBackgroundColor: const Color(0xFFF7F8FA),
      ),
      home: const AuthGate(),
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

  @override
  void initState() {
    super.initState();
    session = supabase.auth.currentSession;

    supabase.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;
      setState(() {
        session = data.session;
      });
    });
  }

  Future<String> fetchRole() async {
    final user = supabase.auth.currentUser;
    if (user == null) return '공개용';

    try {
      final profile = await supabase
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .single();

      return profile['role']?.toString() ?? '공개용';
    } catch (_) {
      return '공개용';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (session == null) {
      return const LoginPage();
    }

    return FutureBuilder<String>(
      future: fetchRole(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        return AppLayout(role: snapshot.data!);
      },
    );
  }
}
