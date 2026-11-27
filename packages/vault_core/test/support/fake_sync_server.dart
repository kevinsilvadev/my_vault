import 'package:vault_core/vault_core.dart';

/// Servidor de sincronização em memória com a mesma semântica da API
/// (server/src/sync/sync.service.ts): concorrência otimista por `version`,
/// revisão monotônica por usuário, tombstones e idempotência por `changeId`.
final class FakeSyncServer {
  final Map<String, RemoteRecord> _items = {};
  final Map<String, PushResult> _applied = {};
  int _revision = 0;

  /// Quando `true`, a próxima chamada de push é aplicada mas a resposta é
  /// "perdida" (simula queda de rede após o commit no servidor).
  bool dropNextPushResponse = false;

  /// Quando `true`, toda chamada falha antes de chegar ao servidor.
  bool offline = false;

  /// Executado durante o push, antes de responder (simula edição concorrente).
  Future<void> Function()? onPush;

  Map<String, RemoteRecord> get items => Map.unmodifiable(_items);

  FakeSyncApi clientFor() => FakeSyncApi(this);

  /// Simula restauração de um backup antigo.
  ({Map<String, RemoteRecord> items, int revision}) snapshot() =>
      (items: Map.of(_items), revision: _revision);

  void restore(({Map<String, RemoteRecord> items, int revision}) backup) {
    _items
      ..clear()
      ..addAll(backup.items);
    _revision = backup.revision;
    _applied.clear();
  }

  PushResult _apply(PushChange change) {
    final replay = _applied[change.changeId];
    if (replay != null) {
      if (replay.itemId != change.itemId) {
        return PushResult(
          changeId: change.changeId,
          itemId: change.itemId,
          status: PushStatus.rejected,
          reason: PushRejection.changeIdReused,
        );
      }
      return replay;
    }

    final current = _items[change.itemId];
    if (current == null && change.baseVersion > 0) {
      return PushResult(
        changeId: change.changeId,
        itemId: change.itemId,
        status: PushStatus.rejected,
        reason: PushRejection.baseVersionNotFound,
      );
    }
    final currentVersion = current?.version ?? 0;
    if (currentVersion != change.baseVersion) {
      return PushResult(
        changeId: change.changeId,
        itemId: change.itemId,
        status: PushStatus.conflict,
        serverItem: current,
      );
    }

    final revision = ++_revision;
    final version = currentVersion + 1;
    final isDelete = change.operation == PendingOperation.delete;
    _items[change.itemId] = RemoteRecord(
      id: change.itemId,
      encryptedData: isDelete ? null : change.encryptedData,
      nonce: isDelete ? null : change.nonce,
      cryptoVersion: change.cryptoVersion ?? current?.cryptoVersion ?? 1,
      version: version,
      revision: revision,
      deleted: isDelete,
      updatedAt: DateTime.now().toUtc(),
    );
    final result = PushResult(
      changeId: change.changeId,
      itemId: change.itemId,
      status: PushStatus.applied,
      version: version,
      revision: revision,
    );
    _applied[change.changeId] = result;
    return result;
  }

  PullPage _pull(int since, int limit) {
    final changed = _items.values.where((i) => i.revision > since).toList()
      ..sort((a, b) => a.revision.compareTo(b.revision));
    final page = changed.take(limit).toList();
    return PullPage(
      items: page,
      cursor: page.isEmpty ? since : page.last.revision,
      hasMore: changed.length > limit,
      latestRevision: _revision,
    );
  }
}

final class OfflineException implements Exception {}

final class FakeSyncApi implements RemoteSyncApi {
  FakeSyncApi(this._server);

  final FakeSyncServer _server;
  int pushCalls = 0;

  @override
  Future<List<PushResult>> push(List<PushChange> changes) async {
    pushCalls++;
    if (_server.offline) throw OfflineException();
    final results = [for (final c in changes) _server._apply(c)];
    final hook = _server.onPush;
    if (hook != null) {
      _server.onPush = null;
      await hook();
    }
    if (_server.dropNextPushResponse) {
      _server.dropNextPushResponse = false;
      throw OfflineException();
    }
    return results;
  }

  @override
  Future<PullPage> pull({required int since, required int limit}) async {
    if (_server.offline) throw OfflineException();
    return _server._pull(since, limit);
  }
}
