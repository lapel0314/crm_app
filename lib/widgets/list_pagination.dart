import 'package:flutter/material.dart';
import 'package:crm_app/theme/app_theme.dart';

/// 고객DB/가망고객/유선회원 목록 하단 페이지네이션 바.
/// (세 페이지에 동일하게 복붙돼 있던 _pagination을 공용으로 승격,
/// 처음/끝 페이지 이동 버튼을 함께 추가)
Widget listPagination({
  required int totalItems,
  required int safePage,
  required int totalPages,
  required ValueChanged<int> onPageChanged,
  int pageSize = 20,
}) {
  final start = totalItems == 0 ? 0 : safePage * pageSize + 1;
  var end = (safePage + 1) * pageSize;
  if (end > totalItems) end = totalItems;

  final atFirst = safePage <= 0;
  final atLast = safePage >= totalPages - 1;

  return Container(
    height: 46,
    padding: const EdgeInsets.symmetric(horizontal: 18),
    decoration: const BoxDecoration(
      border: Border(
        top: BorderSide(color: Color(0xFFF3F4F6)),
      ),
    ),
    child: Row(
      children: [
        Text(
          '$start-$end / 총 $totalItems건',
          style: const TextStyle(
            color: Color(0xFF9CA3AF),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        IconButton(
          tooltip: '처음',
          onPressed: atFirst ? null : () => onPageChanged(0),
          icon: const Icon(Icons.first_page, size: 20),
        ),
        IconButton(
          tooltip: '이전',
          onPressed: atFirst ? null : () => onPageChanged(safePage - 1),
          icon: const Icon(Icons.chevron_left, size: 20),
        ),
        Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '${safePage + 1} / $totalPages',
            style: const TextStyle(
              color: AppTheme.primary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        IconButton(
          tooltip: '다음',
          onPressed: atLast ? null : () => onPageChanged(safePage + 1),
          icon: const Icon(Icons.chevron_right, size: 20),
        ),
        IconButton(
          tooltip: '끝',
          onPressed: atLast ? null : () => onPageChanged(totalPages - 1),
          icon: const Icon(Icons.last_page, size: 20),
        ),
      ],
    ),
  );
}
