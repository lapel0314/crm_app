import 'package:flutter/material.dart';

/// 고객DB/유선회원 툴바에서 공용으로 쓰는 문자·카카오 발송 버튼 요소.
/// (customer_page의 private 헬퍼를 두 페이지에서 재사용하기 위해 승격)
Widget kakaoTalkMark({bool busy = false}) {
  if (busy) {
    return const SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: Color(0xFF111827),
      ),
    );
  }

  return Image.asset(
    'assets/images/kakaotalk_logo.png',
    width: 22,
    height: 22,
    fit: BoxFit.contain,
  );
}

const Color kakaoButtonBackground = Color(0xFFFFF9C7);
const Color kakaoButtonBorder = Color(0xFFE6CF00);

Widget toolbarIconButton({
  required String tooltip,
  required VoidCallback? onPressed,
  required Widget icon,
  Color backgroundColor = Colors.white,
  Color borderColor = const Color(0xFFE8E9EF),
}) {
  return Tooltip(
    message: tooltip,
    waitDuration: const Duration(milliseconds: 350),
    child: SizedBox(
      width: 38,
      height: 38,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: backgroundColor,
          disabledBackgroundColor: const Color(0xFFF3F4F6),
          minimumSize: const Size(38, 38),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          side: BorderSide(color: borderColor),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: icon,
      ),
    ),
  );
}
