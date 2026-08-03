import 'package:flutter/material.dart';

/// 디자인 토큰 + 앱 전역 테마.
/// 색상은 여기 상수만 참조한다 (신규 코드 기준). 기존 하드코딩은 점진 치환.
class AppTheme {
  // 브랜드 마크(로고) 전용 — UI 액션색으로 쓰지 않는다.
  static const Color brandPink = Color(0xFFC94C6E);

  // Primary (핑크) — 주요 액션/선택/포커스. (틸 시안 후 사용자 결정으로 핑크 유지)
  static const Color primary = Color(0xFFC94C6E); // 흰배경 대비 ~4.6:1
  static const Color primaryDark = Color(0xFFA83A59);
  static const Color primaryTint = Color(0xFFFFEEF4); // 연한 배경
  static const Color primaryTintStrong = Color(0xFFFFD6E1);
  static const Color primaryBright = Color(0xFFEC4899); // 다크 배경용

  // 통신사 배지 색 — 테마와 무관하게 고정 (LG 핑크 / SK 파랑 / KT 빨강).
  static const Color carrierLg = Color(0xFFC94C6E);
  static const Color carrierSk = Color(0xFF2563EB);
  static const Color carrierKt = Color(0xFFEF4444);

  // 배경/면/테두리 (기존 실사용 값 그대로).
  static const Color background = Color(0xFFF4F5F8);
  static const Color surface = Colors.white;
  static const Color surfaceSubtle = Color(0xFFF9FAFB);
  static const Color border = Color(0xFFE8E9EF);
  static const Color borderSubtle = Color(0xFFF3F4F6);

  // 텍스트 위계.
  static const Color textPrimary = Color(0xFF111827); // 제목
  static const Color textBody = Color(0xFF374151); // 본문
  static const Color textSecondary = Color(0xFF6B7280); // 보조
  static const Color textDisabled = Color(0xFF9CA3AF); // 비활성

  // Semantic.
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFD97706); // 텍스트용 (F59E0B는 대비 부족)
  static const Color warningBadge = Color(0xFFF59E0B); // 배지 배경용
  static const Color danger = Color(0xFFDC2626);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Pretendard',
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        surface: surface,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: textPrimary,
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
