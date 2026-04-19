import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:crm_app/utils/phone_utils.dart';

class ContactActionResult {
  final bool success;
  final String? message;

  const ContactActionResult.success()
      : success = true,
        message = null;
  const ContactActionResult.failure(this.message) : success = false;
}

class ContactActionService {
  const ContactActionService();

  Future<ContactActionResult> call(String phone) async {
    final normalized = normalizePhoneNumber(phone);
    if (normalized.isEmpty) {
      return const ContactActionResult.failure('사용 가능한 전화번호가 없습니다.');
    }
    return _launch(Uri(scheme: 'tel', path: normalized), '전화 앱을 열 수 없습니다.');
  }

  Future<ContactActionResult> sms(String phone, String message) async {
    final normalized = normalizePhoneNumber(phone);
    if (normalized.isEmpty) {
      return const ContactActionResult.failure('사용 가능한 전화번호가 없습니다.');
    }
    final uri = Uri(
      scheme: 'sms',
      path: normalized,
      queryParameters: {'body': message},
    );
    return _launch(uri, '문자 앱을 열 수 없습니다.');
  }

  Future<ContactActionResult> smsBulk(
      List<String> phones, String message) async {
    final numbers =
        phones.map(normalizePhoneNumber).where((e) => e.isNotEmpty).toList();
    if (numbers.isEmpty) {
      return const ContactActionResult.failure('사용 가능한 전화번호가 없습니다.');
    }
    final uri = Uri(
      scheme: 'sms',
      path: numbers.join(','),
      queryParameters: {'body': message},
    );
    return _launch(uri, '문자 앱을 열 수 없습니다.');
  }

  Future<ContactActionResult> kakao(String message) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final intent = AndroidIntent(
          action: 'android.intent.action.SEND',
          package: 'com.kakao.talk',
          type: 'text/plain',
          arguments: {'android.intent.extra.TEXT': message},
        );
        await intent.launch();
        return const ContactActionResult.success();
      } catch (_) {
        final marketUri = Uri.parse('market://details?id=com.kakao.talk');
        final webUri = Uri.parse(
            'https://play.google.com/store/apps/details?id=com.kakao.talk');
        if (await launchUrl(marketUri, mode: LaunchMode.externalApplication)) {
          return const ContactActionResult.failure('카카오톡 설치 후 다시 시도해주세요.');
        }
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
        return const ContactActionResult.failure('카카오톡 설치 후 다시 시도해주세요.');
      }
    }

    return const ContactActionResult.failure('카카오톡 전송은 Android에서 사용할 수 있습니다.');
  }

  Future<ContactActionResult> _launch(Uri uri, String failureMessage) async {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) return ContactActionResult.failure(failureMessage);
    return const ContactActionResult.success();
  }
}
