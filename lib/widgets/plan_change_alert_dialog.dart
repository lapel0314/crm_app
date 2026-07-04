import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:crm_app/services/plan_change_alert_service.dart';

class PlanChangeAlertDialog extends StatefulWidget {
  final PlanChangeAlertResult result;
  final Future<void> Function() onHideToday;
  final Future<void> Function() onExport;
  final bool canExport;

  const PlanChangeAlertDialog({
    super.key,
    required this.result,
    required this.onHideToday,
    required this.onExport,
    required this.canExport,
  });

  @override
  State<PlanChangeAlertDialog> createState() => _PlanChangeAlertDialogState();
}

class _PlanChangeAlertDialogState extends State<PlanChangeAlertDialog> {
  bool isExporting = false;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final compact = screenSize.width < 900;
    final dateText = DateFormat('yyyy-MM-dd').format(widget.result.date);
    final customerCount = widget.result.uniqueCustomers.length;

    return AlertDialog(
      backgroundColor: Colors.white,
      insetPadding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 32,
        vertical: compact ? 18 : 32,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 10),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      title: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFC94C6E).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.event_available_rounded,
              color: Color(0xFFC94C6E),
              size: 19,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '오늘의 요금제/부가서비스 알림',
                  style: TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$dateText · 고객 $customerCount명 · 항목 ${widget.result.totalEntries}건',
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: compact ? screenSize.width - 56 : 760,
        height: compact ? screenSize.height * 0.62 : 560,
        child: widget.result.entries.isEmpty
            ? const _EmptyAlert()
            : ListView(
                children: [
                  for (final carrier in PlanChangeAlertService.carrierOrder)
                    if (widget.result.grouped.containsKey(carrier))
                      _CarrierSection(
                        carrier: carrier,
                        groups: widget.result.grouped[carrier]!,
                      ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await widget.onHideToday();
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('오늘 하루 그만보기'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('닫기'),
        ),
        if (widget.canExport)
          ElevatedButton.icon(
            onPressed:
                widget.result.entries.isEmpty || isExporting ? null : _export,
            icon: isExporting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.table_view_rounded, size: 17),
            label: Text(isExporting ? '출력 중' : '엑셀 출력'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC94C6E),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
      ],
    );
  }

  Future<void> _export() async {
    setState(() => isExporting = true);
    try {
      await widget.onExport();
    } finally {
      if (mounted) setState(() => isExporting = false);
    }
  }
}

class _EmptyAlert extends StatelessWidget {
  const _EmptyAlert();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.check_circle_outline_rounded,
              color: Color(0xFF6B7280),
              size: 28,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            '오늘 대상 고객이 없습니다.',
            style: TextStyle(
              color: Color(0xFF111827),
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _CarrierSection extends StatelessWidget {
  final String carrier;
  final Map<PlanChangeAlertType, List<PlanChangeAlertEntry>> groups;

  const _CarrierSection({
    required this.carrier,
    required this.groups,
  });

  @override
  Widget build(BuildContext context) {
    final total = groups.values.fold<int>(0, (sum, rows) => sum + rows.length);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _CarrierBadge(carrier: carrier),
              const SizedBox(width: 8),
              Text(
                '$total건',
                style: const TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final type in PlanChangeAlertService.typeOrder)
            if (groups.containsKey(type))
              _TypeGroup(type: type, entries: groups[type]!),
        ],
      ),
    );
  }
}

class _TypeGroup extends StatelessWidget {
  final PlanChangeAlertType type;
  final List<PlanChangeAlertEntry> entries;

  const _TypeGroup({
    required this.type,
    required this.entries,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    type.label,
                    style: const TextStyle(
                      color: Color(0xFF111827),
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  '${entries.length}명',
                  style: const TextStyle(
                    color: Color(0xFFC94C6E),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 7),
          for (final entry in entries) _CustomerRow(entry: entry),
        ],
      ),
    );
  }
}

class _CustomerRow extends StatelessWidget {
  final PlanChangeAlertEntry entry;

  const _CustomerRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE8E9EF)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final details = [
            _detail('가입일', entry.joinDateLabel),
            _detail('매장', entry.store),
            _detail('담당자', entry.staff),
            _detail('요금제', entry.plan),
            _detail('부가', entry.addService),
            _detail('공시/선약', entry.contractType),
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.customerName.isEmpty ? '-' : entry.customerName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    entry.phone.isEmpty ? '-' : entry.phone,
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Wrap(
                spacing: compact ? 6 : 10,
                runSpacing: 5,
                children: details,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _detail(String label, String value) {
    return Text(
      '$label ${value.isEmpty ? '-' : value}',
      style: const TextStyle(
        color: Color(0xFF6B7280),
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _CarrierBadge extends StatelessWidget {
  final String carrier;

  const _CarrierBadge({required this.carrier});

  @override
  Widget build(BuildContext context) {
    final color = switch (carrier) {
      'SK' => const Color(0xFF2563EB),
      'KT' => const Color(0xFFEF4444),
      'LG' => const Color(0xFFC94C6E),
      _ => const Color(0xFF6B7280),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        carrier,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
