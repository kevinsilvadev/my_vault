import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:vault_core/vault_core.dart';

import '../../data/api/account_session_store.dart';
import '../../data/api/api_exception.dart';
import '../../data/api/myvault_api.dart';
import '../../data/api/server_url.dart';

/// O cofre local e o da conta são cofres diferentes.
final class AccountVaultMismatchException implements Exception {
  const AccountVaultMismatchException(this.message);

  final String message;
}

/// Conta, sessão e sincronização.
///
/// A conta autoriza a sincronização; não desbloqueia o cofre. A senha da conta
/// é diferente da senha mestre e nunca é armazenada.
class AccountController extends ChangeNotifier {
  AccountController({
    required VaultService vault,
    required LocalVaultStore store,
    required AccountSessionStore sessionStore,
    this.autoSyncInterval = const Duration(minutes: 5),
  })  : _vault = vault,
        _store = store,
        _sessionStore = sessionStore;

  final VaultService _vault;
  final LocalVaultStore _store;
  final AccountSessionStore _sessionStore;
  final Duration autoSyncInterval;

  MyVaultApi? _api;
  SyncEngine? _engine;
  bool _syncing = false;
  DateTime? _lastSyncAt;
  String? _lastError;
  Timer? _periodic;
  Timer? _debounce;

  bool get isSignedIn => _api != null;
  bool get isSyncing => _syncing;
  DateTime? get lastSyncAt => _lastSyncAt;
  String? get lastError => _lastError;
  String? get email => _api?.session.email;
  Uri? get serverUrl => _api?.session.serverUrl;

  /// Disparado após uma sincronização que trouxe ou gerou mudanças.
  VoidCallback? onVaultChanged;

  Future<void> initialize() async {
    final session = await _sessionStore.read();
    if (session != null) _attach(session);
    notifyListeners();
  }

  Future<void> register({
    required String serverUrl,
    required String email,
    required String password,
    required String deviceName,
  }) async {
    final url = ServerUrl.parse(serverUrl);
    final tokens = await AuthApi(baseUrl: url).register(
      email: email.trim(),
      password: password,
      deviceName: deviceName,
    );
    await _completeSignIn(url, email.trim().toLowerCase(), tokens);
  }

  Future<void> login({
    required String serverUrl,
    required String email,
    required String password,
    required String deviceName,
  }) async {
    final url = ServerUrl.parse(serverUrl);
    final previous = await _sessionStore.read();
    final tokens = await AuthApi(baseUrl: url).login(
      email: email.trim(),
      password: password,
      deviceName: deviceName,
      deviceId: previous?.deviceId,
    );
    await _completeSignIn(url, email.trim().toLowerCase(), tokens);
  }

  Future<void> logout() async {
    final api = _api;
    if (api != null) {
      try {
        await api.logout();
      } on Object {
        // Mesmo offline, a sessão local é descartada.
      }
    }
    await _sessionStore.clear();
    _detach();
    notifyListeners();
  }

  Future<List<DeviceInfo>> devices() => _requireApi().listDevices();

  Future<void> revokeDevice(String deviceId) => _requireApi().revokeDevice(deviceId);

  /// Agenda uma sincronização em breve (agrupa alterações em sequência).
  void scheduleSync() {
    if (!isSignedIn) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () => unawaited(syncNow()));
  }

  /// Sincroniza agora. Erros ficam em [lastError]; não são relançados.
  Future<SyncReport?> syncNow() async {
    final engine = _engine;
    final api = _api;
    if (engine == null || api == null || _syncing) return null;
    _syncing = true;
    _lastError = null;
    notifyListeners();
    try {
      await _reconcileEnvelope(api);
      final report = await engine.synchronize();
      _lastSyncAt = DateTime.now();
      if (report.pulled > 0 || report.conflicts > 0) onVaultChanged?.call();
      return report;
    } on SessionExpiredException catch (error) {
      _lastError = error.message;
      await _sessionStore.clear();
      _detach();
      return null;
    } on ApiException catch (error) {
      _lastError = error.message;
      return null;
    } on AccountVaultMismatchException catch (error) {
      _lastError = error.message;
      return null;
    } on VaultException catch (error) {
      _lastError = error.message;
      return null;
    } on FormatException {
      _lastError = 'Resposta inesperada do servidor.';
      return null;
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  Future<void> _completeSignIn(Uri url, String email, AuthTokens tokens) async {
    final bound = await _store.readMeta(MetaKeys.boundAccountId);
    if (bound != null && bound != tokens.userId) {
      throw const AccountVaultMismatchException(
          'O cofre deste dispositivo pertence a outra conta.');
    }
    final session = AccountSession(
      serverUrl: url,
      email: email,
      userId: tokens.userId,
      deviceId: tokens.deviceId,
      refreshToken: tokens.refreshToken,
    );
    final api = MyVaultApi(
      session: session,
      sessionStore: _sessionStore,
      initialAccessToken: tokens.accessToken,
    );
    // Verifica a compatibilidade antes de persistir qualquer coisa.
    await _reconcileEnvelope(api);
    await _sessionStore.write(session);
    if (bound == null) {
      await _store.writeMeta(MetaKeys.boundAccountId, tokens.userId);
      await _store.writeMeta(MetaKeys.syncCursor, null);
    }
    _attach(session, api: api);
    notifyListeners();
    unawaited(syncNow());
  }

  /// Garante que o cofre local e o da conta são o mesmo:
  /// - conta sem envelope → envia o local;
  /// - dispositivo sem cofre → adota o da conta;
  /// - ambos e diferentes → recusa.
  Future<void> _reconcileEnvelope(MyVaultApi api) async {
    final remote = await api.getKeyEnvelope();
    final local = await _vault.readEnvelope();
    if (remote == null) {
      if (local != null) await api.putKeyEnvelope(local, baseVersion: 0);
      return;
    }
    if (local == null) {
      await _vault.adoptEnvelope(remote.envelope);
      onVaultChanged?.call();
      return;
    }
    if (!local.matches(remote.envelope)) {
      throw const AccountVaultMismatchException(
          'Este dispositivo já possui um cofre diferente do cofre da conta.');
    }
  }

  void _attach(AccountSession session, {MyVaultApi? api}) {
    final client = api ?? MyVaultApi(session: session, sessionStore: _sessionStore);
    _api = client;
    _engine = SyncEngine(store: _store, api: client);
    _periodic?.cancel();
    _periodic = Timer.periodic(autoSyncInterval, (_) => unawaited(syncNow()));
  }

  void _detach() {
    _periodic?.cancel();
    _debounce?.cancel();
    _api = null;
    _engine = null;
  }

  MyVaultApi _requireApi() {
    final api = _api;
    if (api == null) throw const SessionExpiredException();
    return api;
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }
}
