import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class AuthService {
  Future<void> signUp(String email, String password) async {
    final res = await supabase.auth.signUp(
      email: email,
      password: password,
    );

    print('회원가입 결과: ${res.user}');
  }

  Future<Map<String, dynamic>?> signIn(String email, String password) async {
    final res = await supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );

    final user = res.user;
    if (user == null) {
      print('로그인 실패');
      return null;
    }

    final profile =
        await supabase.from('profiles').select().eq('id', user.id).single();

    return profile;
  }
}
