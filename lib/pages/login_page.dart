import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crm_app/services/notice_service.dart';
import 'package:crm_app/utils/store_utils.dart';

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
  bool agreedTerms = false;
  final noticeService = NoticeService(supabase);
  Notice? latestNotice;

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
    _loadLatestNotice();
  }

  Future<void> _loadLatestNotice() async {
    final notice = await noticeService.fetchLatestNotice();
    if (!mounted) return;
    setState(() {
      latestNotice = notice;
    });
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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

      showMessage('로그인되었습니다.');
    } catch (e) {
      debugPrint('login failed: $e');
      showMessage('로그인에 실패했습니다.');
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

    if (!agreedTerms) {
      showMessage('서비스약관에 동의해주세요.');
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
          'store': normalizeStoreName(signupStoreController.text.trim()),
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
      agreedTerms = false;
    } catch (e) {
      debugPrint('signup failed: $e');
      showMessage('회원가입에 실패했습니다.');
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

  void _showTermsDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('서비스약관'),
        content: const SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Text(
              'Pink Phone CRM은 매장 고객 관리, 개통 정보 관리, 정산 확인을 위한 내부 업무용 서비스입니다.\n\n'
              '1. 계정은 본인만 사용해야 하며 타인에게 공유할 수 없습니다.\n'
              '2. 고객 개인정보는 업무 목적 범위 안에서만 조회하고 사용할 수 있습니다.\n'
              '3. 허위 정보 입력, 무단 삭제, 외부 유출은 금지됩니다.\n'
              '4. 회원가입 후 이메일 인증과 관리자 승인이 완료되어야 로그인할 수 있습니다.\n'
              '5. 서비스 운영을 위해 접속 및 업무 처리 기록이 보관될 수 있습니다.',
              style: TextStyle(height: 1.6),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                agreedTerms = true;
              });
              Navigator.pop(context);
            },
            child: const Text('동의'),
          ),
        ],
      ),
    );
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
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFC94C6E), width: 1.6),
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
        borderRadius: BorderRadius.circular(8),
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
                  borderRadius: BorderRadius.circular(8),
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
                  borderRadius: BorderRadius.circular(8),
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
      width: 430,
      constraints: const BoxConstraints(maxHeight: 720),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE8E9EF)),
        boxShadow: const [
          BoxShadow(
            blurRadius: 18,
            offset: Offset(0, 8),
            color: Color(0x14000000),
          ),
        ],
      ),
      child: Padding(padding: const EdgeInsets.all(12), child: child),
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
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: isLoading ? null : login,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC94C6E),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
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
          inputFormatters: [LengthLimitingTextInputFormatter(13)],
          decoration: _inputDecoration('전화번호', prefixIcon: Icons.call_outlined),
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
            color: const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE8E9EF)),
          ),
          child: const Text(
            '가입 완료 버튼을 누르면 입력한 이메일로 인증 메일이 발송됩니다. 이메일 인증과 관리자 승인 완료 후 로그인할 수 있습니다.',
            style: TextStyle(
              color: Color(0xFF6B7280),
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
          decoration: _inputDecoration('직급', prefixIcon: Icons.badge_outlined),
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
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: agreedTerms
                ? const Color(0xFFF0FDF4)
                : const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: agreedTerms
                  ? const Color(0xFFBBF7D0)
                  : const Color(0xFFE8E9EF),
            ),
          ),
          child: Row(
            children: [
              Checkbox(
                value: agreedTerms,
                activeColor: const Color(0xFFC94C6E),
                onChanged: (value) {
                  setState(() {
                    agreedTerms = value ?? false;
                  });
                },
              ),
              const Expanded(
                child: Text(
                  '서비스약관에 동의합니다.',
                  style: TextStyle(
                    color: Color(0xFF374151),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton(
                onPressed: _showTermsDialog,
                child: const Text('약관 보기'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: isLoading || !agreedTerms ? null : signup,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC94C6E),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
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
        color: const Color(0xFF191B2A),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: const Color(0xFFC94C6E),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.phone_iphone_rounded,
              size: 28,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 30),
          const Text(
            'Pink Phone CRM',
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            latestNotice?.title ?? '공지사항',
            style: const TextStyle(
              fontSize: 15,
              height: 1.8,
              color: Color(0xFFD1D5DB),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            latestNotice?.content ?? '등록된 공지사항이 없습니다.',
            style: const TextStyle(
              fontSize: 14,
              height: 1.7,
              color: Color(0xFFA7ABBD),
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF252740)),
            ),
            child: Container(
              constraints: const BoxConstraints(minHeight: 90),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '계정 승인 안내',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    '회원가입 후 이메일 인증을 완료하면 관리자 승인 대기 상태가 됩니다.',
                    style: TextStyle(
                      color: Color(0xFFA7ABBD),
                      height: 1.6,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
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
    final narrow = MediaQuery.of(context).size.width < 900;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1240),
              child: narrow
                  ? Column(
                      children: [
                        SizedBox(height: 360, child: _leftPanel()),
                        const SizedBox(height: 20),
                        _phoneFrame(child: _phoneScreen()),
                      ],
                    )
                  : SizedBox(
                      height: 760,
                      child: Row(
                        children: [
                          Expanded(flex: 11, child: _leftPanel()),
                          const SizedBox(width: 24),
                          Expanded(
                            flex: 9,
                            child: Center(
                              child: _phoneFrame(child: _phoneScreen()),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
