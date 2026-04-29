import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crm_app/services/login_policy_service.dart';
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
  final loginPolicyService = LoginPolicyService(supabase);
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
      showMessage('이메일과 비밀번호를 모두 입력해 주세요.');
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
        throw Exception('로그인에 실패했습니다. 다시 시도해 주세요.');
      }

      final profile = await supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (profile == null) {
        await supabase.auth.signOut();
        throw Exception('승인된 사용자 정보가 없습니다. 관리자에게 문의해 주세요.');
      }

      if ((profile['approval_status'] ?? 'pending') != 'approved') {
        await supabase.auth.signOut();
        throw Exception('아직 관리자 승인이 완료되지 않았습니다. 승인 후 다시 로그인해 주세요.');
      }

      await loginPolicyService.checkLoginPolicy();
      showMessage('로그인되었습니다.');
    } catch (e) {
      debugPrint('login failed: $e');
      if (e is LoginPolicyException) {
        await supabase.auth.signOut();
        showMessage(e.message);
      } else {
        showMessage('로그인에 실패했습니다. 이메일과 비밀번호를 확인해 주세요.');
      }
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
      showMessage('이름, 전화번호, 이메일, 비밀번호, 직급을 모두 입력해 주세요.');
      return;
    }

    if (!agreedTerms) {
      showMessage('서비스 약관 동의가 필요합니다.');
      return;
    }

    if (!_isValidPhone(signupPhoneController.text.trim())) {
      showMessage('전화번호는 010-1234-1234 형식으로 입력해 주세요.');
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final normalizedStore = normalizeStoreName(signupStoreController.text.trim());
      final authResponse = await supabase.auth.signUp(
        email: signupEmailController.text.trim(),
        password: signupPasswordController.text.trim(),
        data: {
          'name': signupNameController.text.trim(),
          'phone': signupPhoneController.text.trim(),
          'role': signupRole,
          'store': normalizedStore,
        },
      );

      final user = authResponse.user;
      if (user == null) {
        throw Exception('회원가입에 실패했습니다. 다시 시도해 주세요.');
      }

      if (normalizedStore.isNotEmpty &&
          (signupRole == roleOwner ||
              signupRole == roleDeveloper ||
              signupRole == roleManager)) {
        try {
          await loginPolicyService.bootstrapSignupNetwork(
            storeName: normalizedStore,
          );
        } catch (e) {
          debugPrint('signup network bootstrap failed: $e');
        }
      }

      showMessage('회원가입이 완료되었습니다. 이메일 인증과 관리자 승인이 완료된 뒤 로그인할 수 있습니다.');

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
      showMessage('회원가입 처리 중 오류가 발생했습니다.');
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
        title: const Text('개인정보처리방침'),
        content: const SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Text(
              '대산(이하 “회사”)은 회사 내부 직원이 사용하는 CRM 앱(이하 “서비스”)에서 처리되는 개인정보를 중요하게 생각하며, 관련 법령에 따라 개인정보를 안전하게 관리하고 보호하기 위해 다음과 같이 개인정보처리방침을 수립·운영합니다.\n\n'
              '1. 개인정보의 처리 목적\n\n'
              '회사는 다음 목적을 위해 개인정보를 처리합니다.\n\n'
              '고객 상담 및 응대 이력 관리\n'
              '고객 연락처 확인 및 고객관리 업무 수행\n'
              '판매, 예약, 문의, 사후관리 등 업무 처리\n'
              '직원 계정 관리 및 권한별 서비스 이용 관리\n'
              '서비스 보안, 접속기록 관리, 부정 이용 방지\n'
              '민원 처리 및 내부 운영 관리\n\n'
              '회사는 위 목적 범위 내에서만 개인정보를 처리하며, 목적이 변경되는 경우 필요한 조치를 진행합니다.\n\n'
              '2. 처리하는 개인정보 항목\n\n'
              '회사는 다음과 같은 개인정보를 처리할 수 있습니다.\n\n'
              '가. 고객 정보\n'
              '이름\n'
              '휴대전화번호\n'
              '상담 내용\n'
              '방문 기록\n'
              '판매 및 응대 이력\n'
              '기타 직원이 업무 처리 과정에서 입력한 정보\n'
              '나. 직원 정보\n'
              '이름\n'
              '아이디\n'
              '비밀번호(암호화 저장)\n'
              '직책 또는 권한 정보\n'
              '로그인 기록\n'
              '접속 기기 정보\n'
              '접속 IP 정보\n\n'
              '3. 개인정보의 처리 및 보유 기간\n\n'
              '회사는 개인정보를 처리 목적 달성에 필요한 기간 동안 보유하며, 목적 달성 후에는 지체 없이 파기합니다.\n\n'
              '다만, 회사는 내부 운영 및 업무 이력 관리 필요에 따라 다음 기준으로 개인정보를 보유할 수 있습니다.\n\n'
              '고객 정보: 상담 또는 거래 종료 후 1년\n'
              '직원 계정 정보: 퇴사 또는 계정 사용 종료 후 즉시 또는 내부 정책에 따른 기간 내 파기\n'
              '접속기록 및 보안기록: 최대 1년\n\n'
              '관계 법령에 따라 별도 보관이 필요한 경우 해당 법령에서 정한 기간 동안 보관할 수 있습니다.\n\n'
              '4. 개인정보의 제3자 제공\n\n'
              '회사는 원칙적으로 개인정보를 외부에 제공하지 않습니다.\n\n'
              '다만, 다음의 경우에는 예외로 할 수 있습니다.\n\n'
              '정보주체의 동의를 받은 경우\n'
              '법령에 특별한 규정이 있는 경우\n'
              '수사기관 등 관계기관의 적법한 요청이 있는 경우\n\n'
              '5. 개인정보 처리의 위탁\n\n'
              '회사는 서비스 운영을 위해 일부 업무를 외부 서비스 제공업체에 위탁할 수 있습니다.\n\n'
              '예시:\n\n'
              '클라우드 서버 및 데이터베이스 운영\n'
              '문자 또는 알림 발송 서비스\n'
              '로그 분석 및 보안 서비스\n\n'
              '회사는 위탁계약 체결 시 개인정보 보호 관련 법령에 따라 개인정보가 안전하게 처리되도록 필요한 사항을 규정하고 관리·감독합니다.\n\n'
              '6. 개인정보의 파기 절차 및 방법\n\n'
              '회사는 개인정보 보유기간 경과, 처리 목적 달성 등으로 개인정보가 불필요하게 되었을 때에는 지체 없이 해당 개인정보를 파기합니다.\n\n'
              '파기 방법은 다음과 같습니다.\n\n'
              '전자적 파일 형태: 복구 또는 재생이 불가능한 방법으로 영구 삭제\n'
              '종이 문서 형태: 분쇄 또는 소각\n\n'
              '7. 정보주체의 권리와 행사 방법\n\n'
              '정보주체는 회사에 대해 언제든지 다음 권리를 행사할 수 있습니다.\n\n'
              '개인정보 열람 요구\n'
              '개인정보 정정 요구\n'
              '개인정보 삭제 요구\n'
              '개인정보 처리정지 요구\n\n'
              '위 권리 행사는 회사의 개인정보 보호 담당자에게 요청할 수 있으며, 회사는 지체 없이 필요한 조치를 진행합니다.\n\n'
              '8. 개인정보의 안전성 확보조치\n\n'
              '회사는 개인정보의 안전성 확보를 위해 다음과 같은 조치를 취하고 있습니다.\n\n'
              '접근 권한의 차등 부여\n'
              '비밀번호 암호화 저장\n'
              '접속기록 보관 및 점검\n'
              '허용된 기기, 네트워크 또는 권한에 따른 접근 제한\n'
              '개인정보 접근 최소화 및 관리자 통제\n'
              '보안 업데이트 및 시스템 점검\n\n'
              '9. 개인정보 보호책임자 및 문의처\n\n'
              '회사는 개인정보 처리에 관한 업무를 총괄해서 책임지고, 개인정보 관련 문의 및 불만처리를 위해 아래와 같이 담당자를 지정합니다.\n\n'
              '회사명: 대산\n'
              '담당부서: 개인정보 보호 담당\n'
              '연락처: 010-8285-9126\n'
              '이메일: dnwls02060314@gmail.com\n\n'
              '10. 개인정보처리방침의 변경\n\n'
              '이 개인정보처리방침은 2026-04-19부터 적용됩니다.\n'
              '내용 추가, 삭제 또는 수정이 있는 경우 서비스 내 공지사항 또는 별도 안내를 통해 고지합니다.',
              style: TextStyle(height: 1.6),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('\uB2EB\uAE30'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                agreedTerms = true;
              });
              Navigator.pop(context);
            },
            child: const Text('\uB3D9\uC758'),
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
                  '\uB85C\uADF8\uC778',
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
                  '\uD68C\uC6D0\uAC00\uC785',
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
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 430, maxHeight: 720),
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

  Widget _mobileHero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        color: const Color(0xFF191B2A),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFC94C6E),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.phone_iphone_rounded,
              size: 24,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Pink Phone CRM',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            latestNotice?.title ?? '\uACF5\uC9C0\uC0AC\uD56D',
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: Color(0xFFD1D5DB),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            latestNotice?.content ?? '등록된 공지사항이 없습니다.',
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              height: 1.6,
              color: Color(0xFFA7ABBD),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
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
          '\uB85C\uADF8\uC778',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '\uB4F1\uB85D\uB41C \uACC4\uC815\uC73C\uB85C CRM\uC5D0 \uB85C\uADF8\uC778\uD558\uC138\uC694.',
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
            '\uC774\uBA54\uC77C',
            prefixIcon: Icons.mail_outline_rounded,
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: passwordController,
          obscureText: obscureLoginPassword,
          decoration: _inputDecoration(
            '\uBE44\uBC00\uBC88\uD638',
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
            child: Text(isLoading ? '\uCC98\uB9AC \uC911..' : '\uB85C\uADF8\uC778'),
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
          '\uD68C\uC6D0\uAC00\uC785',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: Color(0xFF111827),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '\uD68C\uC6D0\uAC00\uC785 \uD6C4 \uC774\uBA54\uC77C \uC778\uC99D\uACFC \uAD00\uB9AC\uC790 \uC2B9\uC778\uC774 \uD544\uC694\uD569\uB2C8\uB2E4.',
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
            '\uC774\uB984',
            prefixIcon: Icons.person_outline_rounded,
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: signupPhoneController,
          keyboardType: TextInputType.phone,
          inputFormatters: [LengthLimitingTextInputFormatter(13)],
          decoration: _inputDecoration('\uC804\uD654\uBC88\uD638', prefixIcon: Icons.call_outlined),
          onChanged: (value) {
            _applyPhoneFormat(signupPhoneController, value);
          },
        ),
        const SizedBox(height: 14),
        TextField(
          controller: signupEmailController,
          decoration: _inputDecoration(
            '\uC774\uBA54\uC77C',
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
            '\uAC00\uC785\uC644\uB8CC \uBC84\uD2BC\uC744 \uB204\uB974\uBA74 \uC785\uB825\uD55C \uC774\uBA54\uC77C\uB85C \uC778\uC99D \uBA54\uC77C\uC774 \uBC1C\uC1A1\uB429\uB2C8\uB2E4. \uC774\uBA54\uC77C \uC778\uC99D\uACFC \uAD00\uB9AC\uC790 \uD655\uC778\uC774 \uC644\uB8CC\uB41C \uB4A4 \uB85C\uADF8\uC778\uD560 \uC218 \uC788\uC2B5\uB2C8\uB2E4.',
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
            '\uBE44\uBC00\uBC88\uD638',
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
          decoration: _inputDecoration('\uC9C1\uAE09', prefixIcon: Icons.badge_outlined),
          items: const [
            DropdownMenuItem(value: roleOwner, child: Text(roleOwner)),
            DropdownMenuItem(value: roleDeveloper, child: Text(roleDeveloper)),
            DropdownMenuItem(value: roleManager, child: Text(roleManager)),
            DropdownMenuItem(value: roleStaff, child: Text(roleStaff)),
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
            '\uB9E4\uC7A5',
            prefixIcon: Icons.storefront_outlined,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color:
                agreedTerms ? const Color(0xFFF0FDF4) : const Color(0xFFF9FAFB),
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
                  '\uC11C\uBE44\uC2A4 \uC57D\uAD00\uC5D0 \uB3D9\uC758\uD569\uB2C8\uB2E4.',
                  style: TextStyle(
                    color: Color(0xFF374151),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton(
                onPressed: _showTermsDialog,
                child: const Text('\uB0B4\uC6A9 \uBCF4\uAE30'),
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
            child: Text(isLoading ? '\uCC98\uB9AC \uC911..' : '\uAC00\uC785 \uC644\uB8CC'),
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
            latestNotice?.title ?? '\uACF5\uC9C0\uC0AC\uD56D',
            style: const TextStyle(
              fontSize: 15,
              height: 1.8,
              color: Color(0xFFD1D5DB),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            latestNotice?.content ?? '\uB4F1\uB85D\uB41C \uACF5\uC9C0\uC0AC\uD56D\uC774 \uC5C6\uC2B5\uB2C8\uB2E4.',
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
                    '\uACC4\uC815 \uD655\uC778 \uC548\uB0B4',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    '\uD68C\uC6D0\uAC00\uC785 \uD6C4 \uC774\uBA54\uC77C \uC778\uC99D\uC774 \uB05D\uB098\uBA74 \uAD00\uB9AC\uC790 \uC2B9\uC778 \uB300\uAE30 \uC0C1\uD0DC\uAC00 \uB429\uB2C8\uB2E4.',
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
    final width = MediaQuery.of(context).size.width;
    final narrow = width < 900;
    final mobile = width < 600;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(mobile ? 12 : 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1240),
              child: mobile
                  ? Column(
                      children: [
                        _mobileHero(),
                        const SizedBox(height: 12),
                        _phoneFrame(child: _phoneScreen()),
                      ],
                    )
                  : narrow
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
