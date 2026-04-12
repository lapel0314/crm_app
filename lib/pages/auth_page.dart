import 'package:flutter/material.dart';
import 'package:crm_app/utils/store_utils.dart';
import '../services/auth_service.dart';
import 'home_page.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  bool isLogin = true;

  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  final authService = AuthService();

  Future<void> handleAuth() async {
    try {
      if (isLogin) {
        final profile = await authService.signIn(
          emailController.text.trim(),
          passwordController.text.trim(),
        );

        if (profile == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('로그인 실패')),
          );
          return;
        }

        final role = (profile['role'] ?? '사원').toString();
        final store = normalizeStoreName(profile['store']);

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => HomePage(role: role, currentStore: store),
          ),
        );
      } else {
        await authService.signUp(
          emailController.text.trim(),
          passwordController.text.trim(),
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('회원가입 완료 (로그인 해주세요)')),
        );

        setState(() {
          isLogin = true;
        });
      }
    } catch (e) {
      debugPrint('legacy auth failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('핑크폰 CRM')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: '이메일'),
            ),
            TextField(
              controller: passwordController,
              decoration: const InputDecoration(labelText: '비밀번호'),
              obscureText: true,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: handleAuth,
              child: Text(isLogin ? '로그인' : '회원가입'),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  isLogin = !isLogin;
                });
              },
              child: Text(isLogin ? '회원가입으로' : '로그인으로'),
            ),
          ],
        ),
      ),
    );
  }
}
