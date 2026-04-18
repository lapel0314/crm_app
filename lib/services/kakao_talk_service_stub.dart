enum KakaoChatType {
  friend,
  group,
  openChat;

  static KakaoChatType fromText(dynamic value) {
    return switch (value?.toString()) {
      'group' => KakaoChatType.group,
      'openChat' => KakaoChatType.openChat,
      _ => KakaoChatType.friend,
    };
  }
}

class KakaoSendTarget {
  final String id;
  final String customerName;
  final String searchName;
  final KakaoChatType chatType;

  const KakaoSendTarget({
    required this.id,
    required this.customerName,
    required this.searchName,
    this.chatType = KakaoChatType.friend,
  });
}

class KakaoSendResult {
  final KakaoSendTarget target;
  final String message;
  final bool success;
  final String? errorMessage;

  const KakaoSendResult({
    required this.target,
    required this.message,
    required this.success,
    this.errorMessage,
  });
}

class KakaoTalkService {
  Future<List<KakaoSendResult>> sendBulkMessages({
    required List<KakaoSendTarget> targets,
    required String message,
    Duration delayBetweenMessages = const Duration(seconds: 2),
  }) async {
    return targets
        .map(
          (target) => KakaoSendResult(
            target: target,
            message: message,
            success: false,
            errorMessage: '카카오톡 발송은 Windows 앱에서만 사용할 수 있습니다.',
          ),
        )
        .toList();
  }
}
