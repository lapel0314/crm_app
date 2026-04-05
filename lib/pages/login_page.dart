import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  final signupNameController = TextEditingController();
  final signupPhoneController = TextEditingController();
  final signupEmailController = TextEditingController();
  final signupPasswordController = TextEditingController();
  final signupStoreController = TextEditingController();

  String? signupRole;

  bool isLoginMode = true;
  bool isLoading = false;
  bool obscureLoginPassword = true;
  bool obscureSignupPassword = true;
  bool autoLogin = true;

  late final AnimationController _animationController;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );

    _animationController.forward();
  }

  String _formatPhone(String input) {
    final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length <= 3) return digits;
    if (digits.length <= 7) {
      return '${digits.substring(0, 3)}-${digits.substring(3)}';
    }
    final cut = digits.length > 11 ? 11 : digits.length;
    return '${digits.substring(0, 3)}-${digits.substring(3, 7)}-${digits.substring(7, cut)}';
  }

  bool _isValidPhone(String value) {
    return RegExp(r'^01[0-9]-\d{3,4}-\d{4}$').hasMatch(value.trim());
  }

  void _applyPhoneFormat(TextEditingController controller, String value) {
    final formatted = _formatPhone(value);
    controller.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  void showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<void> login() async {
    if (emailController.text.trim().isEmpty ||
        passwordController.text.trim().isEmpty) {
      showMessage('이메일과 비밀번호를 입력하세요.');
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final result = await supabase.auth.signInWithPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      final user = result.user;
      if (user == null) {
        throw Exception('로그인 사용자 정보를 가져오지 못했습니다.');
      }

      final profile = await supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (profile == null) {
        await supabase.auth.signOut();
        throw Exception('프로필 정보가 없습니다. 관리자에게 문의해주세요.');
      }

      if ((profile['approval_status'] ?? 'pending') != 'approved') {
        await supabase.auth.signOut();
        throw Exception('이메일 인증 후 관리자 승인 완료 시 로그인할 수 있습니다.');
      }

      if (!autoLogin) {
        showMessage('로그인되었습니다.');
      }
    } catch (e) {
      showMessage('로그인 실패: $e');
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> signup() async {
    if (signupNameController.text.trim().isEmpty ||
        signupPhoneController.text.trim().isEmpty ||
        signupEmailController.text.trim().isEmpty ||
        signupPasswordController.text.trim().isEmpty ||
        signupRole == null) {
      showMessage('이름, 전화번호, 이메일, 비밀번호, 직급은 필수입니다.');
      return;
    }

    if (!_isValidPhone(signupPhoneController.text.trim())) {
      showMessage('전화번호 형식은 010-1234-1234 입니다.');
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final authResponse = await supabase.auth.signUp(
        email: signupEmailController.text.trim(),
        password: signupPasswordController.text.trim(),
        data: {
          'name': signupNameController.text.trim(),
          'phone': signupPhoneController.text.trim(),
          'role': signupRole,
          'store': signupStoreController.text.trim(),
        },
      );

      final user = authResponse.user;
      if (user == null) {
        throw Exception('회원가입 사용자 정보를 가져오지 못했습니다.');
      }

      showMessage('이메일 인증 메일이 발송되었습니다. 이메일 인증 후 관리자 승인되면 로그인할 수 있습니다.');

      setState(() {
        isLoginMode = true;
      });

      signupNameController.clear();
      signupPhoneController.clear();
      signupEmailController.clear();
      signupPasswordController.clear();
      signupStoreController.clear();
      signupRole = null;
    } catch (e) {
      showMessage('회원가입 실패: $e');
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  void switchMode(bool toLogin) {
    if (isLoginMode == toLogin) return;

    _animationController.reverse().then((_) {
      if (!mounted) return;
      setState(() {
        isLoginMode = toLogin;
      });
      _animationController.forward();
    });
  }

  InputDecoration _inputDecoration(
    String label, {
    IconData? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon, color: const Color(0xFF6B7280))
          : null,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xFFF9FAFB),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFFF4D9D), width: 1.6),
      ),
      labelStyle: const TextStyle(
        color: Color(0xFF6B7280),
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _modeSwitch() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => switchMode(true),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isLoginMode ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: isLoginMode
                      ? [
                          BoxShadow(
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                            color: Colors.black.withValues(alpha: 0.05),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  '로그인',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: isLoginMode
                        ? const Color(0xFF111827)
                        : const Color(0xFF6B7280),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => switchMode(false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: !isLoginMode ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: !isLoginMode
                      ? [
                          BoxShadow(
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                            color: Colors.black.withValues(alpha: 0.05),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  '회원가입',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: !isLoginMode
                        ? const Color(0xFF111827)
                        : const Color(0xFF6B7280),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _phoneFrame({required Widget child}) {
    return Container(
      width: 370,
      height: 680,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(42),
        boxShadow: [
          BoxShadow(
            blurRadius: 30,
            offset: const Offset(0, 20),
            color: Colors.black.withValues(alpha: 0.18),
          ),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFDFDFE),
          borderRadius: BorderRadius.circular(32),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 120,
                height: 8,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _phoneScreen() {
    return Column(
      children: [
        _modeSwitch(),
        const SizedBox(height: 20),
        Expanded(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SingleChildScrollView(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: isLoginMode
                    ? Container(
                        key: const ValueKey('login_mode'),
                        child: _loginView(),
                      )
                    : Container(
                        key: const ValueKey('signup_mode'),
                        child: _signupView(),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _loginView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '로그인',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '등록된 계정으로 CRM에 접속하세요.',
          style: TextStyle(
            color: Color(0xFF6B7280),
            fontWeight: FontWeight.w600,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: emailController,
          decoration: _inputDecoration(
            '이메일',
            prefixIcon: Icons.mail_outline_rounded,
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: passwordController,
          obscureText: obscureLoginPassword,
          decoration: _inputDecoration(
            '비밀번호',
            prefixIcon: Icons.lock_outline_rounded,
            suffixIcon: IconButton(
              onPressed: () {
                setState(() {
                  obscureLoginPassword = !obscureLoginPassword;
                });
              },
              icon: Icon(
                obscureLoginPassword
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Checkbox(
              value: autoLogin,
              onChanged: (value) {
                setState(() {
                  autoLogin = value ?? true;
                });
              },
            ),
            const Text(
              '자동 로그인',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF374151),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: isLoading ? null : login,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF2D8D),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              elevation: 0,
              textStyle: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            child: Text(isLoading ? '처리 중...' : '로그인'),
          ),
        ),
      ],
    );
  }

  Widget _signupView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '회원가입',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '회원가입 완료 후 이메일 인증과 관리자 승인이 필요합니다.',
          style: TextStyle(
            color: Color(0xFF6B7280),
            fontWeight: FontWeight.w600,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 22),
        TextField(
          controller: signupNameController,
          decoration: _inputDecoration(
            '이름',
            prefixIcon: Icons.person_outline_rounded,
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: signupPhoneController,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            LengthLimitingTextInputFormatter(13),
          ],
          decoration: _inputDecoration(
            '전화번호',
            prefixIcon: Icons.call_outlined,
          ),
          onChanged: (value) {
            _applyPhoneFormat(signupPhoneController, value);
          },
        ),
        const SizedBox(height: 14),
        TextField(
          controller: signupEmailController,
          decoration: _inputDecoration(
            '이메일',
            prefixIcon: Icons.mail_outline_rounded,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3F8),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFFFD3E5)),
          ),
          child: const Text(
            '입력한 이메일로 인증 메일이 발송됩니다. 이메일 인증을 완료해야 로그인할 수 있습니다.',
            style: TextStyle(
              color: Color(0xFFBE185D),
              fontWeight: FontWeight.w700,
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: signupPasswordController,
          obscureText: obscureSignupPassword,
          decoration: _inputDecoration(
            '비밀번호',
            prefixIcon: Icons.lock_outline_rounded,
            suffixIcon: IconButton(
              onPressed: () {
                setState(() {
                  obscureSignupPassword = !obscureSignupPassword;
                });
              },
              icon: Icon(
                obscureSignupPassword
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          initialValue: signupRole,
          decoration: _inputDecoration(
            '직급',
            prefixIcon: Icons.badge_outlined,
          ),
          items: const [
            DropdownMenuItem(value: '점장', child: Text('점장')),
            DropdownMenuItem(value: '사원', child: Text('사원')),
          ],
          onChanged: (value) {
            setState(() {
              signupRole = value;
            });
          },
        ),
        const SizedBox(height: 14),
        TextField(
          controller: signupStoreController,
          decoration: _inputDecoration(
            '매장',
            prefixIcon: Icons.storefront_outlined,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: isLoading ? null : signup,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF2D8D),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              elevation: 0,
              textStyle: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            child: Text(isLoading ? '처리 중...' : '가입 완료'),
          ),
        ),
      ],
    );
  }

  Widget _leftPanel() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFF1F7),
            Color(0xFFFFD7E8),
            Color(0xFFFFC3DD),
          ],
        ),
        borderRadius: BorderRadius.circular(34),
      ),
      padding: const EdgeInsets.all(36),
      child: Stack(
        children: [
          Positioned(
            top: 20,
            right: 10,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.20),
              ),
            ),
          ),
          Positioned(
            bottom: 110,
            left: 10,
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.18),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 16,
                      offset: const Offset(0, 10),
                      color: Colors.black.withValues(alpha: 0.06),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.phone_iphone_rounded,
                  size: 34,
                  color: Color(0xFFFF2D8D),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Pink Phone CRM',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF111827),
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'PinkPhone CRM에 오신 걸 환영합니다',
                style: TextStyle(
                  fontSize: 15,
                  height: 1.8,
                  color: Color(0xFF4B5563),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Center(
                child: SizedBox(
                  width: 360,
                  height: 360,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 300,
                        height: 300,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              Colors.white.withValues(alpha: 0.70),
                              Colors.white.withValues(alpha: 0.10),
                            ],
                          ),
                        ),
                      ),
                      Transform.rotate(
                        angle: -0.18,
                        child: Container(
                          width: 160,
                          height: 290,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2A2D34),
                            borderRadius: BorderRadius.circular(32),
                            boxShadow: [
                              BoxShadow(
                                blurRadius: 28,
                                offset: const Offset(0, 16),
                                color: Colors.black.withValues(alpha: 0.18),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(24),
                                gradient: const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color(0xFFFFFAFC),
                                    Color(0xFFFFE6F1),
                                  ],
                                ),
                              ),
                              child: Stack(
                                children: [
                                  Positioned(
                                    top: 12,
                                    left: 0,
                                    right: 0,
                                    child: Center(
                                      child: Container(
                                        width: 56,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFD1D5DB),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 50,
                                    left: 18,
                                    right: 18,
                                    child: Container(
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 104,
                                    left: 18,
                                    right: 18,
                                    child: Container(
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 166,
                                    left: 18,
                                    right: 18,
                                    child: Container(
                                      height: 46,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFF4D9D),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 32,
                        top: 70,
                        child: Transform.rotate(
                          angle: 0.18,
                          child: Container(
                            width: 86,
                            height: 86,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(22),
                              boxShadow: [
                                BoxShadow(
                                  blurRadius: 18,
                                  offset: const Offset(0, 8),
                                  color: Colors.black.withValues(alpha: 0.08),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.favorite_rounded,
                              color: Color(0xFFFF4D9D),
                              size: 38,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 38,
                        bottom: 52,
                        child: Transform.rotate(
                          angle: -0.12,
                          child: Container(
                            width: 104,
                            height: 54,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(
                                  blurRadius: 18,
                                  offset: const Offset(0, 8),
                                  color: Colors.black.withValues(alpha: 0.08),
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.phone_android_rounded,
                                  color: Color(0xFFFF2D8D),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Pink',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF111827),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    signupNameController.dispose();
    signupPhoneController.dispose();
    signupEmailController.dispose();
    signupPasswordController.dispose();
    signupStoreController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      body: SafeArea(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 1240, maxHeight: 780),
            margin: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  flex: 11,
                  child: _leftPanel(),
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 9,
                  child: Center(
                    child: _phoneFrame(
                      child: _phoneScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
