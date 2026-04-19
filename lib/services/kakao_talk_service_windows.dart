import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

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
  static const _kakaoClassCandidates = [
    'EVA_Window_Dblclk',
    'EVA_Window',
  ];

  Future<void> ensureKakaoTalkRunning() async {
    if (!Platform.isWindows) {
      throw UnsupportedError('移댁뭅?ㅽ넚 諛쒖넚? Windows?먯꽌留??ъ슜?????덉뒿?덈떎.');
    }

    if (findKakaoMainWindow() != null) return;

    final localAppData = Platform.environment['LOCALAPPDATA'];
    final programFiles = Platform.environment['ProgramFiles'];
    final candidates = [
      if (localAppData != null)
        '$localAppData\\Kakao\\KakaoTalk\\KakaoTalk.exe',
      if (programFiles != null)
        '$programFiles\\Kakao\\KakaoTalk\\KakaoTalk.exe',
    ];

    for (final path in candidates) {
      if (File(path).existsSync()) {
        await Process.start(path, const []);
        await Future<void>.delayed(const Duration(seconds: 2));
        if (findKakaoMainWindow() != null) return;
      }
    }

    await Process.start('cmd', const ['/c', 'start', '', 'kakaotalk://']);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (findKakaoMainWindow() == null) {
      throw StateError('移댁뭅?ㅽ넚 PC ?ㅽ뻾 ?щ?瑜??뺤씤??二쇱꽭??');
    }
  }

  HWND? findKakaoMainWindow() {
    var hwnd = HWND(nullptr);
    while (true) {
      hwnd = FindWindowEx(HWND(nullptr), hwnd, null, null).value;
      if (hwnd.address == 0) return null;

      final className = _windowClassName(hwnd);
      final title = _windowTitle(hwnd);
      final isKakaoClass = _kakaoClassCandidates
          .any((candidate) => className.contains(candidate));
      final isKakaoTitle =
          title.contains('移댁뭅?ㅽ넚') || title.contains('KakaoTalk');
      if (isKakaoClass && isKakaoTitle && IsWindowVisible(hwnd)) return hwnd;
    }
  }

  Future<void> activateChat(String target, KakaoChatType chatType) async {
    await ensureKakaoTalkRunning();
    final mainWindow = findKakaoMainWindow();
    if (mainWindow == null) {
      throw StateError('移댁뭅?ㅽ넚 硫붿씤李쎌쓣 李얠? 紐삵뻽?듬땲??');
    }

    ShowWindow(mainWindow, SW_RESTORE);
    SetForegroundWindow(mainWindow);
    await Future<void>.delayed(const Duration(milliseconds: 250));

    final online = _findChildWindowByTitle(mainWindow, 'OnlineMainView');
    if (online == null) {
      throw StateError('移댁뭅?ㅽ넚 OnlineMainView瑜?李얠? 紐삵뻽?듬땲??');
    }

    final listViewName = switch (chatType) {
      KakaoChatType.friend => 'ContactListView',
      KakaoChatType.group || KakaoChatType.openChat => 'ChatRoomListView',
    };
    final listView = _findChildWindowByTitle(online, listViewName);
    if (listView == null) {
      throw StateError('移댁뭅?ㅽ넚 $listViewName ?곸뿭??李얠? 紐삵뻽?듬땲??');
    }

    final edit = _findDirectChildByClass(listView, 'Edit');
    if (edit == null) {
      throw StateError('移댁뭅?ㅽ넚 寃???낅젰李쎌쓣 李얠? 紐삵뻽?듬땲??');
    }

    if (chatType == KakaoChatType.openChat) {
      await _pressCtrlArrow(edit, VK_RIGHT);
    } else if (chatType == KakaoChatType.group) {
      await _pressCtrlArrow(edit, VK_LEFT);
    }

    _setWindowText(edit, target);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    _postEnter(edit);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _setWindowText(edit, '');

    await Future<void>.delayed(const Duration(milliseconds: 1400));
  }

  Future<HWND?> waitForChatWindow(
    String title, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final endAt = DateTime.now().add(timeout);
    final titlePtr = title.toNativeUtf16();
    try {
      while (DateTime.now().isBefore(endAt)) {
        final hwnd = FindWindow(null, PCWSTR(titlePtr)).value;
        if (hwnd.address != 0 && IsWindowVisible(hwnd)) return hwnd;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    } finally {
      malloc.free(titlePtr);
    }
    return _findTopLevelWindowByTitle(title);
  }

  Future<KakaoSendResult> sendMessage({
    required KakaoSendTarget target,
    required String message,
  }) async {
    try {
      if (Platform.isAndroid) {
        if (message.trim().isEmpty) {
          throw ArgumentError('발송 메시지가 비어 있습니다.');
        }
        final intent = AndroidIntent(
          action: 'android.intent.action.SEND',
          package: 'com.kakao.talk',
          type: 'text/plain',
          arguments: {'android.intent.extra.TEXT': message},
        );
        await intent.launch();
        return KakaoSendResult(
          target: target,
          message: message,
          success: true,
        );
      }
      if (target.searchName.trim().isEmpty) {
        throw ArgumentError('移댁뭅?ㅽ넚 寃???대쫫??鍮꾩뼱 ?덉뒿?덈떎.');
      }
      if (message.trim().isEmpty) {
        throw ArgumentError('諛쒖넚 硫붿떆吏媛 鍮꾩뼱 ?덉뒿?덈떎.');
      }

      await activateChat(target.searchName.trim(), target.chatType);
      final chatWindow = await waitForChatWindow(target.searchName.trim());
      if (chatWindow == null) {
        throw StateError('梨꾪똿李쎌쓣 李얠? 紐삵뻽?듬땲??');
      }

      final input = _findDirectChildByClass(chatWindow, 'RichEdit50W');
      if (input == null) {
        throw StateError('梨꾪똿李??낅젰李?RichEdit50W)??李얠? 紐삵뻽?듬땲??');
      }

      SetForegroundWindow(chatWindow);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      SetFocus(input);
      await Future<void>.delayed(const Duration(milliseconds: 150));

      _releaseCtrlIfNeeded();
      _setWindowText(input, '');
      await _pressShiftEnter();
      await _pressKey(VK_BACK);
      _setWindowText(input, message);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      _postEnter(chatWindow);

      return KakaoSendResult(
        target: target,
        message: message,
        success: true,
      );
    } catch (e) {
      return KakaoSendResult(
        target: target,
        message: message,
        success: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<List<KakaoSendResult>> sendBulkMessages({
    required List<KakaoSendTarget> targets,
    required String message,
    Duration delayBetweenMessages = const Duration(seconds: 2),
  }) async {
    final results = <KakaoSendResult>[];
    for (final target in targets) {
      results.add(await sendMessage(target: target, message: message));
      await Future<void>.delayed(delayBetweenMessages);
    }
    return results;
  }

  HWND? _findTopLevelWindowByTitle(String title) {
    var hwnd = HWND(nullptr);
    while (true) {
      hwnd = FindWindowEx(HWND(nullptr), hwnd, null, null).value;
      if (hwnd.address == 0) return null;
      if (IsWindowVisible(hwnd) && _windowTitle(hwnd).contains(title)) {
        return hwnd;
      }
    }
  }

  HWND? _findChildWindowByTitle(HWND parent, String titlePart) {
    var child = HWND(nullptr);
    while (true) {
      child = FindWindowEx(parent, child, null, null).value;
      if (child.address == 0) return null;

      if (_windowTitle(child).contains(titlePart)) return child;
      final nested = _findChildWindowByTitle(child, titlePart);
      if (nested != null) return nested;
    }
  }

  HWND? _findDirectChildByClass(HWND parent, String className) {
    final classPtr = className.toNativeUtf16();
    try {
      final child =
          FindWindowEx(parent, HWND(nullptr), PCWSTR(classPtr), null).value;
      return child.address == 0 ? null : child;
    } finally {
      malloc.free(classPtr);
    }
  }

  String _windowTitle(HWND hwnd) {
    final buffer = wsalloc(512);
    try {
      GetWindowText(hwnd, PWSTR(buffer), 512);
      return buffer.toDartString();
    } finally {
      malloc.free(buffer);
    }
  }

  String _windowClassName(HWND hwnd) {
    final buffer = wsalloc(256);
    try {
      GetClassName(hwnd, PWSTR(buffer), 256);
      return buffer.toDartString();
    } finally {
      malloc.free(buffer);
    }
  }

  void _setWindowText(HWND hwnd, String text) {
    final textPtr = text.toNativeUtf16();
    try {
      SendMessage(hwnd, WM_SETTEXT, WPARAM(0), LPARAM(textPtr.address));
    } finally {
      malloc.free(textPtr);
    }
  }

  void _postEnter(HWND hwnd) {
    PostMessage(hwnd, WM_KEYDOWN, WPARAM(VK_RETURN), LPARAM(0));
  }

  Future<void> _pressCtrlArrow(HWND hwnd, VIRTUAL_KEY arrowKey) async {
    SetForegroundWindow(hwnd);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _sendKey(VK_CONTROL, keyDown: true);
    _sendKey(arrowKey, keyDown: true);
    _sendKey(arrowKey, keyDown: false);
    _sendKey(VK_CONTROL, keyDown: false);
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  void _releaseCtrlIfNeeded() {
    if (GetKeyState(VK_CONTROL) < 0) {
      _sendKey(VK_CONTROL, keyDown: false);
    }
  }

  Future<void> _pressShiftEnter() async {
    _sendKey(VK_SHIFT, keyDown: true);
    _sendKey(VK_RETURN, keyDown: true);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    _sendKey(VK_SHIFT, keyDown: false);
    _sendKey(VK_RETURN, keyDown: false);
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }

  Future<void> _pressKey(VIRTUAL_KEY key) async {
    _sendKey(key, keyDown: true);
    _sendKey(key, keyDown: false);
    await Future<void>.delayed(const Duration(milliseconds: 120));
  }

  void _sendKey(VIRTUAL_KEY key, {required bool keyDown}) {
    final input = calloc<INPUT>();
    try {
      input.ref.type = INPUT_KEYBOARD;
      input.ref.ki.wVk = key;
      input.ref.ki.dwFlags = keyDown ? KEYBD_EVENT_FLAGS(0) : KEYEVENTF_KEYUP;
      SendInput(1, input, sizeOf<INPUT>());
    } finally {
      calloc.free(input);
    }
  }
}
