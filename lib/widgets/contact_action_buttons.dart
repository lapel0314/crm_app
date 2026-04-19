import 'package:flutter/material.dart';

import 'package:crm_app/constants/message_templates.dart';
import 'package:crm_app/services/contact_action_service.dart';
import 'package:crm_app/utils/phone_utils.dart';

class ContactActionButtons extends StatelessWidget {
  final String customerName;
  final String phone;
  final String messageTemplate;
  final ValueChanged<String> onMessage;
  final bool dense;

  const ContactActionButtons({
    super.key,
    required this.customerName,
    required this.phone,
    required this.onMessage,
    this.messageTemplate = defaultContactMessageTemplate,
    this.dense = false,
  });

  Future<void> _handle(
    BuildContext context,
    Future<ContactActionResult> Function(ContactActionService service) action,
  ) async {
    final result = await action(const ContactActionService());
    if (!context.mounted) return;
    if (!result.success && result.message != null) {
      onMessage(result.message!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final normalized = normalizePhoneNumber(phone);
    final message = buildContactMessage(
      customerName: customerName,
      template: messageTemplate,
    );
    final iconSize = dense ? 14.0 : 18.0;
    final minimumSize = dense ? const Size(30, 30) : const Size(42, 38);

    Widget button({
      required IconData icon,
      required String tooltip,
      required VoidCallback? onPressed,
    }) {
      return IconButton.filledTonal(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(icon, size: iconSize),
        style: IconButton.styleFrom(
          minimumSize: minimumSize,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }

    return Wrap(
      spacing: dense ? 4 : 6,
      runSpacing: 4,
      children: [
        button(
          icon: Icons.call_rounded,
          tooltip: '전화',
          onPressed: normalized.isEmpty
              ? () => onMessage('사용 가능한 전화번호가 없습니다.')
              : () => _handle(context, (service) => service.call(phone)),
        ),
        button(
          icon: Icons.sms_rounded,
          tooltip: '문자',
          onPressed: normalized.isEmpty
              ? () => onMessage('사용 가능한 전화번호가 없습니다.')
              : () =>
                  _handle(context, (service) => service.sms(phone, message)),
        ),
        button(
          icon: Icons.chat_bubble_rounded,
          tooltip: '카카오톡',
          onPressed: () =>
              _handle(context, (service) => service.kakao(message)),
        ),
      ],
    );
  }
}
