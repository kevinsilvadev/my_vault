import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:http/http.dart' as http;
import 'package:vault_core/vault_core.dart';

import 'account_session_store.dart';
import 'api_exception.dart';

const Duration _timeout = Duration(seconds: 20);

/// Resposta de cadastro/login/refresh.
final class AuthTokens {
  const AuthTokens({
    required this.userId,
    required this.deviceId,
    required this.accessToken,
    required this.accessTokenExpiresIn,
    required this.refreshToken,
  });

  factory AuthTokens.fromJson(JsonReader json) => AuthTokens(
        userId: json.string('userId'),
        deviceId: json.string('deviceId'),
        accessToken: json.string('accessToken'),
        accessTokenExpiresIn: json.integer('accessTokenExpiresIn'),
        refreshToken: json.string('refreshToken'),
      );

  final String userId;
  final String deviceId;
  final String accessToken;
  final int accessTokenExpiresIn;
  final String refreshToken;
}

final class DeviceInfo {
  const DeviceInfo({
    required this.id,
    required this.name,
    required this.platform,
    required this.lastSeenAt,
    required this.current,
  });

  factory DeviceInfo.fromJson(JsonReader json) => DeviceInfo(
        id: json.string('id'),
        name: json.string('name'),
        platform: json.string('platform'),
        lastSeenAt: json.dateTime('lastSeenAt'),
        current: json.boolean('current'),
      );

  final String id;
  final String name;
  final String platform;
  final DateTime lastSeenAt;
  final bool current;
}

final class RemoteEnvelope {
  const RemoteEnvelope({required this.envelope, required this.version});

  final VaultKeyEnvelope envelope;
  final int version;
}

String currentPlatform() {
  if (Platform.isAndroid) return 'android';
  if (Platform.isWindows) return 'windows';
  return 'other';
}

/// Transporte JSON com tratamento uniforme de erros.
final class _JsonTransport {
  _JsonTransport(this._client);

  final http.Client _client;

  Future<JsonReader?> send(
    String method,
    Uri uri, {
    Object? body,
    String? accessToken,
  }) async {
    final request = http.Request(method, uri)
      ..headers['Accept'] = 'application/json';
    if (accessToken != null) {
      request.headers['Authorization'] = 'Bearer $accessToken';
    }
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(request).timeout(_timeout),
      ).timeout(_timeout);
    } on TimeoutException {
      throw const ApiException.network();
    } on http.ClientException {
      throw const ApiException.network();
    } on Object catch (error) {
      if (error is ApiException) rethrow;
      throw const ApiException.network();
    }

    if (response.statusCode == 204) return null;
    JsonReader? json;
    try {
      json = decodeJsonObject(utf8.decode(response.bodyBytes));
    } on FormatException {
      json = null;
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (json == null) {
        throw ApiException(
            statusCode: response.statusCode, code: 'INVALID_RESPONSE', message: 'Resposta inválida do servidor.');
      }
      return json;
    }
    final error = json?.json['error'];
    if (error is Map<String, Object?>) {
      throw ApiException(
        statusCode: response.statusCode,
        code: error['code'] as String? ?? 'ERROR',
        message: error['message'] as String? ?? 'Erro no servidor.',
      );
    }
    throw ApiException(
        statusCode: response.statusCode, code: 'HTTP_${response.statusCode}', message: 'Erro no servidor.');
  }
}

/// Chamadas públicas de autenticação (sem token).
final class AuthApi {
  AuthApi({required this.baseUrl, http.Client? client})
      : _transport = _JsonTransport(client ?? http.Client());

  final Uri baseUrl;
  final _JsonTransport _transport;

  Uri _uri(String path) => baseUrl.replace(path: '${baseUrl.path}/api/v1$path');

  Future<AuthTokens> register({
    required String email,
    required String password,
    required String deviceName,
  }) async =>
      AuthTokens.fromJson((await _transport.send('POST', _uri('/auth/register'), body: {
        'email': email,
        'password': password,
        'device': {'name': deviceName, 'platform': currentPlatform()},
      }))!);

  Future<AuthTokens> login({
    required String email,
    required String password,
    required String deviceName,
    String? deviceId,
  }) async =>
      AuthTokens.fromJson((await _transport.send('POST', _uri('/auth/login'), body: {
        'email': email,
        'password': password,
        'device': {
          'name': deviceName,
          'platform': currentPlatform(),
          if (deviceId != null) 'id': deviceId,
        },
      }))!);

  Future<AuthTokens> refresh(String refreshToken) async => AuthTokens.fromJson(
      (await _transport.send('POST', _uri('/auth/refresh'), body: {'refreshToken': refreshToken}))!);
}

/// Cliente autenticado: renova o token de acesso sob demanda e implementa a
/// porta [RemoteSyncApi] do `vault_core`.
final class MyVaultApi implements RemoteSyncApi {
  MyVaultApi({
    required AccountSession session,
    required AccountSessionStore sessionStore,
    http.Client? client,
    String? initialAccessToken,
  })  : _session = session,
        _sessionStore = sessionStore,
        _accessToken = initialAccessToken,
        _transport = _JsonTransport(client ?? http.Client()),
        _auth = AuthApi(baseUrl: session.serverUrl, client: client);

  AccountSession _session;
  final AccountSessionStore _sessionStore;
  final _JsonTransport _transport;
  final AuthApi _auth;
  String? _accessToken;
  Future<void>? _refreshing;

  AccountSession get session => _session;

  Uri _uri(String path, [Map<String, String>? query]) => _session.serverUrl.replace(
        path: '${_session.serverUrl.path}/api/v1$path',
        queryParameters: query,
      );

  Future<RemoteEnvelope?> getKeyEnvelope() async {
    try {
      final json = (await _authorized('GET', _uri('/vault/key-envelope')))!;
      return RemoteEnvelope(
        envelope: VaultKeyEnvelope.fromJson(json.object('envelope').json),
        version: json.integer('version'),
      );
    } on ApiException catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<int> putKeyEnvelope(VaultKeyEnvelope envelope, {required int baseVersion}) async {
    final json = (await _authorized('PUT', _uri('/vault/key-envelope'),
        body: {'envelope': envelope.toJson(), 'baseVersion': baseVersion}))!;
    return json.integer('version');
  }

  Future<List<DeviceInfo>> listDevices() async {
    final json = (await _authorized('GET', _uri('/devices')))!;
    return [for (final d in json.objectList('devices')) DeviceInfo.fromJson(d)];
  }

  Future<void> revokeDevice(String deviceId) async {
    await _authorized('DELETE', _uri('/devices/$deviceId'));
  }

  Future<void> logout() async {
    await _authorized('POST', _uri('/auth/logout'));
  }

  @override
  Future<List<PushResult>> push(List<PushChange> changes) async {
    final json = (await _authorized('POST', _uri('/sync/push'),
        body: {'changes': [for (final c in changes) c.toJson()]}))!;
    return [for (final r in json.objectList('results')) PushResult.fromJson(r)];
  }

  @override
  Future<PullPage> pull({required int since, required int limit}) async {
    final json = (await _authorized(
        'GET', _uri('/sync/pull', {'since': '$since', 'limit': '$limit'})))!;
    return PullPage.fromJson(json);
  }

  Future<JsonReader?> _authorized(String method, Uri uri, {Object? body}) async {
    if (_accessToken == null) await _refreshAccessToken();
    try {
      return await _transport.send(method, uri, body: body, accessToken: _accessToken);
    } on ApiException catch (error) {
      if (!error.isUnauthorized) rethrow;
      await _refreshAccessToken();
      return _transport.send(method, uri, body: body, accessToken: _accessToken);
    }
  }

  /// Renovações concorrentes compartilham a mesma requisição: reapresentar
  /// um refresh token já usado faria o servidor revogar a sessão.
  Future<void> _refreshAccessToken() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<void> _doRefresh() async {
    try {
      final tokens = await _auth.refresh(_session.refreshToken);
      _session = _session.withRefreshToken(tokens.refreshToken);
      await _sessionStore.write(_session);
      _accessToken = tokens.accessToken;
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        _accessToken = null;
        throw const SessionExpiredException();
      }
      rethrow;
    }
  }
}
