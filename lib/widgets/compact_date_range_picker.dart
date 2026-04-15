import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

Future<DateTimeRange?> showCompactDateRangePicker({
  required BuildContext context,
  required DateTimeRange initialDateRange,
  required DateTime firstDate,
  required DateTime lastDate,
  required String title,
}) {
  return showDialog<DateTimeRange>(
    context: context,
    builder: (_) => _CompactDateRangePickerDialog(
      initialDateRange: initialDateRange,
      firstDate: firstDate,
      lastDate: lastDate,
      title: title,
    ),
  );
}

class _CompactDateRangePickerDialog extends StatefulWidget {
  final DateTimeRange initialDateRange;
  final DateTime firstDate;
  final DateTime lastDate;
  final String title;

  const _CompactDateRangePickerDialog({
    required this.initialDateRange,
    required this.firstDate,
    required this.lastDate,
    required this.title,
  });

  @override
  State<_CompactDateRangePickerDialog> createState() =>
      _CompactDateRangePickerDialogState();
}

class _CompactDateRangePickerDialogState
    extends State<_CompactDateRangePickerDialog> {
  late DateTime visibleMonth;
  DateTime? startDate;
  DateTime? endDate;
  final formatter = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    startDate = _dateOnly(widget.initialDateRange.start);
    endDate = _dateOnly(widget.initialDateRange.end);
    visibleMonth = DateTime(startDate!.year, startDate!.month);
  }

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  DateTime _monthOnly(DateTime date) => DateTime(date.year, date.month);

  bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _sameMonth(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;

  bool _isDisabled(DateTime date) =>
      date.isBefore(_dateOnly(widget.firstDate)) ||
      date.isAfter(_dateOnly(widget.lastDate));

  bool _isInRange(DateTime date) {
    if (startDate == null || endDate == null) return false;
    return !date.isBefore(startDate!) && !date.isAfter(endDate!);
  }

  bool _canMovePrevious() {
    final previous = DateTime(visibleMonth.year, visibleMonth.month - 1);
    return !previous.isBefore(_monthOnly(widget.firstDate));
  }

  bool _canMoveNext() {
    final rightMonth = DateTime(visibleMonth.year, visibleMonth.month + 1);
    final nextRightMonth = DateTime(rightMonth.year, rightMonth.month + 1);
    return !nextRightMonth.isAfter(
      DateTime(widget.lastDate.year, widget.lastDate.month + 1),
    );
  }

  void _moveMonth(int delta) {
    setState(() {
      visibleMonth = DateTime(visibleMonth.year, visibleMonth.month + delta);
    });
  }

  void _selectDate(DateTime date) {
    if (_isDisabled(date)) return;

    setState(() {
      if (startDate == null || endDate != null) {
        startDate = date;
        endDate = null;
        return;
      }

      if (date.isBefore(startDate!)) {
        endDate = startDate;
        startDate = date;
      } else {
        endDate = date;
      }
    });
  }

  DateTimeRange get _selectedRange {
    final start = startDate ?? _dateOnly(DateTime.now());
    final end = endDate ?? start;
    return start.isAfter(end)
        ? DateTimeRange(start: end, end: start)
        : DateTimeRange(start: start, end: end);
  }

  String get _selectedLabel {
    final range = _selectedRange;
    final start = formatter.format(range.start);
    final end = formatter.format(range.end);
    return start == end ? start : '$start ~ $end';
  }

  @override
  Widget build(BuildContext context) {
    final rightMonth = DateTime(visibleMonth.year, visibleMonth.month + 1);

    return AlertDialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      contentPadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      content: SizedBox(
        width: 640,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            color: Color(0xFF111827),
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _selectedLabel,
                          style: const TextStyle(
                            color: Color(0xFFC94C6E),
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _navButton(
                    tooltip: '이전 달',
                    icon: Icons.chevron_left_rounded,
                    onPressed: _canMovePrevious() ? () => _moveMonth(-1) : null,
                  ),
                  const SizedBox(width: 6),
                  _navButton(
                    tooltip: '다음 달',
                    icon: Icons.chevron_right_rounded,
                    onPressed: _canMoveNext() ? () => _moveMonth(1) : null,
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFF3F4F6)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _month(visibleMonth)),
                  const SizedBox(width: 14),
                  Expanded(child: _month(rightMonth)),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFF3F4F6)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Row(
                children: [
                  const Text(
                    '시작일과 종료일을 차례대로 선택하세요',
                    style: TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('취소'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(_selectedRange),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFC94C6E),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('선택'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: 34,
      height: 34,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        style: IconButton.styleFrom(
          backgroundColor: const Color(0xFFF9FAFB),
          foregroundColor: const Color(0xFF374151),
          disabledForegroundColor: const Color(0xFFD1D5DB),
          side: const BorderSide(color: Color(0xFFE8E9EF)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        padding: EdgeInsets.zero,
      ),
    );
  }

  Widget _month(DateTime month) {
    final monthStart = DateTime(month.year, month.month);
    final firstGridDay =
        monthStart.subtract(Duration(days: monthStart.weekday % 7));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          DateFormat('yyyy년 M월', 'ko_KR').format(month),
          style: const TextStyle(
            color: Color(0xFF111827),
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: const [
            _WeekdayLabel('일', color: Color(0xFFEF4444)),
            _WeekdayLabel('월'),
            _WeekdayLabel('화'),
            _WeekdayLabel('수'),
            _WeekdayLabel('목'),
            _WeekdayLabel('금'),
            _WeekdayLabel('토', color: Color(0xFF2563EB)),
          ],
        ),
        const SizedBox(height: 6),
        for (var week = 0; week < 6; week++)
          Row(
            children: [
              for (var day = 0; day < 7; day++)
                Expanded(
                  child: _dayCell(
                    firstGridDay.add(Duration(days: week * 7 + day)),
                    month,
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _dayCell(DateTime date, DateTime visibleMonthForCell) {
    final inCurrentMonth = _sameMonth(date, visibleMonthForCell);
    final disabled = _isDisabled(date);
    final selectedStart = startDate != null && _sameDate(date, startDate!);
    final selectedEnd = endDate != null && _sameDate(date, endDate!);
    final selected = selectedStart || selectedEnd;
    final inRange = _isInRange(date);
    final today = _sameDate(date, DateTime.now());
    final weekday = date.weekday % 7;
    final baseColor = weekday == 0
        ? const Color(0xFFEF4444)
        : weekday == 6
            ? const Color(0xFF2563EB)
            : const Color(0xFF111827);

    return Padding(
      padding: const EdgeInsets.all(2),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: disabled ? null : () => _selectDate(date),
        child: Container(
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFFC94C6E)
                : inRange
                    ? const Color(0xFFFFEEF4)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: today && !selected
                ? Border.all(color: const Color(0xFFC94C6E))
                : null,
          ),
          child: Text(
            '${date.day}',
            style: TextStyle(
              color: disabled
                  ? const Color(0xFFD1D5DB)
                  : selected
                      ? Colors.white
                      : inCurrentMonth
                          ? baseColor
                          : const Color(0xFFD1D5DB),
              fontSize: 12,
              fontWeight: selected || today ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _WeekdayLabel extends StatelessWidget {
  final String text;
  final Color color;

  const _WeekdayLabel(
    this.text, {
    this.color = const Color(0xFF6B7280),
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
