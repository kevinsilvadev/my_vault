import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Dados persistidos da sessão da conta (não do cofre).
final class AccountSession {
  const AccountSession({
    required this.serverUrl,
    required this.email,
    required this.userId,
    required this.deviceId,
    required this.refreshToken,
  });

  final Uri serverUrl;
  final String email;
  final String userId;
  final String deviceId;
  final String refreshToken;

  AccountSession withRefreshToken(String token) => AccountSession(
        serverUrl: serverUrl,
        email: email,
        userId: userId,
        deviceId: deviceId,
        refreshToken: token,
      );

  Map<String, Object?> toJson() => {
        'serverUrl': serverUrl.toString(),
        'email': email,
        'userId': userId,
        'deviceId': deviceId,
        'refreshToken': refreshToken,
      };

  static AccountSession? tryParse(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, Object?>) return null;
      return AccountSession(
        serverUrl: Uri.parse(json['serverUrl']! as String),
        email: json['email']! as String,
        userId: json['userId']! as String,
        deviceId: json['deviceId']! as String,
        refreshToken: json['refreshToken']! as String,
      );
    } on Object {
      return null;
    }
  }
}

/// Persiste a sessão no armazenamento seguro do sistema operacional
/// (Android Keystore / Windows DPAPI). O token de acesso fica só em memória.
class AccountSessionStore {
  AccountSessionStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const String _key = 'myvault.accountSession';
  final FlutterSecureStorage _storage;

  Future<AccountSession?> read() async {
    final raw = await _storage.read(key: _key);
    return raw == null ? null : AccountSession.tryParse(raw);
  }

  Future<void> write(AccountSession session) =>
      _storage.write(key: _key, value: jsonEncode(session.toJson()));

  Future<void> clear() => _storage.delete(key: _key);
}
