import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DesktopAuthSessionService {
  static const String _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String _legacySupabasePersistSessionKey =
      'SUPABASE_PERSIST_SESSION_KEY';
  static const String _gotrueStorageKey = 'supabase.auth.token';
  static const String _gotrueCodeVerifierKey =
      'supabase.auth.token-code-verifier';

  const DesktopAuthSessionService._();

  static bool get requiresFreshLoginOnLaunch {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  static FlutterAuthClientOptions get authOptions {
    if (!requiresFreshLoginOnLaunch) {
      return const FlutterAuthClientOptions();
    }

    return const FlutterAuthClientOptions(
      localStorage: EmptyLocalStorage(),
    );
  }

  static Future<void> clearPersistedSession() async {
    if (!requiresFreshLoginOnLaunch) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final authStorageKeys = prefs.getKeys().where(_isAuthStorageKey).toList();

      for (final key in authStorageKeys) {
        await prefs.remove(key);
      }
    } catch (error) {
      debugPrint('desktop persisted auth cleanup failed: $error');
    }
  }

  static Future<void> signOutAndClear(SupabaseClient client) async {
    try {
      await client.auth.signOut().timeout(const Duration(seconds: 3));
    } catch (error) {
      debugPrint('desktop signOut failed: $error');
    } finally {
      await clearPersistedSession();
    }
  }

  static bool _isAuthStorageKey(String key) {
    return key == _persistSessionKey ||
        key == _legacySupabasePersistSessionKey ||
        key == _gotrueStorageKey ||
        key == _gotrueCodeVerifierKey ||
        (key.startsWith('sb-') && key.endsWith('-auth-token'));
  }

  static String get _persistSessionKey {
    if (_supabaseUrl.isEmpty) return '';
    return 'sb-${Uri.parse(_supabaseUrl).host.split('.').first}-auth-token';
  }
}
