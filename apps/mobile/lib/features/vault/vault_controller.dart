import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:vault_core/vault_core.dart';

enum VaultStatus { loading, noVault, locked, unlocked }

/// Estado do cofre para a interface: bloqueio, itens descriptografados,
/// conflitos e bloqueio automático por inatividade.
class VaultController extends ChangeNotifier {
  VaultController({
    required VaultService service,
    required LocalVaultStore store,
    KdfParams kdfParams = KdfParams.recommended,
  })  : _service = service,
        _store = store,
        _kdfParams = kdfParams;

  static const String _autoLockKey = 'settings.autoLockSeconds';
  static const Duration defaultAutoLock = Duration(minutes: 5);
  static const List<Duration> autoLockOptions = [
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(minutes: 30),
  ];

  final VaultService _service;
  final LocalVaultStore _store;
  final KdfParams _kdfParams;
  final StreamController<void> _localChanges = StreamController.broadcast();

  VaultStatus _status = VaultStatus.loading;
  List<VaultItem> _items = const [];
  int _undecryptableCount = 0;
  List<ConflictView> _conflicts = const [];
  Duration _autoLockAfter = defaultAutoLock;
  Timer? _autoLockTimer;
  DateTime _lastActivity = DateTime.now();

  VaultStatus get status => _status;
  List<VaultItem> get items => _items;
  int get undecryptableCount => _undecryptableCount;
  List<ConflictView> get conflicts => _conflicts;
  Duration get autoLockAfter => _autoLockAfter;
  List<String> get categories => categoriesOf(_items);

  /// Emite após cada alteração local (usado para agendar sincronização).
  Stream<void> get localChanges => _localChanges.stream;

  Future<void> initialize() async {
    final seconds = int.tryParse(await _store.readMeta(_autoLockKey) ?? '');
    if (seconds != null) _autoLockAfter = Duration(seconds: seconds);
    await refreshStatus();
  }

  /// Reavalia se há cofre local (ex.: após adotar o envelope do servidor).
  Future<void> refreshStatus() async {
    final hasVault = await _service.hasVault();
    _setStatus(!hasVault
        ? VaultStatus.noVault
        : _service.isUnlocked
            ? VaultStatus.unlocked
            : VaultStatus.locked);
  }

  Future<void> createVault(String masterPassword) async {
    await _service.createVault(masterPassword, params: _kdfParams);
    await _onUnlocked();
  }

  /// Lança [InvalidMasterPasswordException] se a senha estiver errada.
  Future<void> unlock(String masterPassword) async {
    await _service.unlock(masterPassword);
    await _onUnlocked();
  }

  void lock() {
    _autoLockTimer?.cancel();
    _service.lock();
    // Remove referências ao conteúdo descriptografado.
    _items = const [];
    _conflicts = const [];
    _undecryptableCount = 0;
    _setStatus(VaultStatus.locked);
  }

  Future<void> reload() async {
    if (!_service.isUnlocked) return;
    final snapshot = await _service.loadItems();
    _items = snapshot.items;
    _undecryptableCount = snapshot.undecryptableIds.length;
    _conflicts = await _service.loadConflicts();
    notifyListeners();
  }

  VaultItem draftItem() => _service.draftItem();

  Future<VaultItem> save(VaultItem item) async {
    final saved = await _service.saveItem(item);
    await reload();
    _localChanges.add(null);
    return saved;
  }

  Future<void> delete(String id) async {
    await _service.deleteItem(id);
    await reload();
    _localChanges.add(null);
  }

  Future<void> resolveConflict(String conflictId, ConflictResolution resolution) async {
    await _service.resolveConflict(conflictId, resolution);
    await reload();
    _localChanges.add(null);
  }

  Future<void> setAutoLock(Duration duration) async {
    _autoLockAfter = duration;
    await _store.writeMeta(_autoLockKey, '${duration.inSeconds}');
    _restartAutoLockTimer();
    notifyListeners();
  }

  /// Chamado a cada interação do usuário. Limitado a 1×/s para não recriar
  /// o temporizador a cada evento de ponteiro.
  void registerActivity() {
    if (_status != VaultStatus.unlocked) return;
    final now = DateTime.now();
    if (now.difference(_lastActivity) < const Duration(seconds: 1)) return;
    _lastActivity = now;
    _restartAutoLockTimer();
  }

  Future<void> _onUnlocked() async {
    _setStatus(VaultStatus.unlocked);
    _lastActivity = DateTime.now();
    _restartAutoLockTimer();
    await reload();
  }

  void _restartAutoLockTimer() {
    _autoLockTimer?.cancel();
    if (_status != VaultStatus.unlocked) return;
    _autoLockTimer = Timer(_autoLockAfter, lock);
  }

  void _setStatus(VaultStatus status) {
    _status = status;
    notifyListeners();
  }

  @override
  void dispose() {
    _autoLockTimer?.cancel();
    _service.lock();
    unawaited(_localChanges.close());
    super.dispose();
  }
}
