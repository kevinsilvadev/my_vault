import 'dart:math';

import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

import '../storage/local_vault_store.dart';
import '../storage/stored_record.dart';
import 'sync_models.dart';

@immutable
final class SyncReport {
  const SyncReport({
    this.pushed = 0,
    this.pulled = 0,
    this.conflicts = 0,
    this.rejected = 0,
  });

  /// Alterações locais aceitas pelo servidor.
  final int pushed;

  /// Registros remotos aplicados localmente.
  final int pulled;

  /// Novos conflitos preservados para decisão do usuário.
  final int conflicts;

  /// Alterações rejeitadas que serão reenviadas na próxima sincronização.
  final int rejected;

  SyncReport operator +(SyncReport other) => SyncReport(
        pushed: pushed + other.pushed,
        pulled: pulled + other.pulled,
        conflicts: conflicts + other.conflicts,
        rejected: rejected + other.rejected,
      );
}

/// Sincroniza a fila local com o servidor. Opera apenas sobre ciphertext:
/// não precisa do cofre desbloqueado.
///
/// Garantias:
/// * **Offline-first:** alterações ficam na fila local até serem aceitas.
/// * **Idempotência:** cada alteração tem um `changeId` estável entre
///   tentativas; reenviar após falha de rede não duplica a operação. Uma
///   nova edição do mesmo item recebe um novo `changeId`.
/// * **Sem perda silenciosa:** em conflito, a versão local é preservada em
///   [SyncConflict] e o usuário decide (ver `VaultService.resolveConflict`).
/// * **Tombstones:** exclusões são sincronizadas como registros `deleted`.
/// * **Recuperação:** se o servidor voltar de um backup mais antigo, o
///   cliente detecta pelo `latestRevision`, ressincroniza e reenvia o que o
///   servidor perdeu.
final class SyncEngine {
  SyncEngine({
    required LocalVaultStore store,
    required RemoteSyncApi api,
    this.pushBatchSize = 100,
    this.pullPageSize = 200,
    DateTime Function()? clock,
    Uuid? uuid,
  })  : _store = store,
        _api = api,
        _clock = clock ?? DateTime.now,
        _uuid = uuid ?? const Uuid();

  final LocalVaultStore _store;
  final RemoteSyncApi _api;
  final int pushBatchSize;
  final int pullPageSize;
  final DateTime Function() _clock;
  final Uuid _uuid;

  Future<SyncReport>? _running;

  /// Envia pendências e depois recebe novidades. Chamadas concorrentes
  /// compartilham a mesma execução.
  Future<SyncReport> synchronize() {
    final running = _running;
    if (running != null) return running;
    final future = _run();
    _running = future;
    return future.whenComplete(() => _running = null);
  }

  Future<SyncReport> _run() async {
    final pushReport = await _push();
    final pullReport = await _pull();
    return pushReport + pullReport;
  }

  Future<SyncReport> _push() async {
    var report = const SyncReport();
    final pending = await _store.pendingRecords();
    for (var start = 0; start < pending.length; start += pushBatchSize) {
      final end = min(start + pushBatchSize, pending.length);
      final changes = [for (final r in pending.sublist(start, end)) _toChange(r)];
      final results = await _api.push(changes);
      final byChangeId = {for (final r in results) r.changeId: r};

      report += await _store.transaction((tx) async {
        var batch = const SyncReport();
        for (final change in changes) {
          final result = byChangeId[change.changeId];
          // Sem resposta para esta alteração: permanece na fila.
          if (result == null) continue;
          batch += await _applyPushResult(tx, change, result);
        }
        return batch;
      });
    }
    return report;
  }

  Future<SyncReport> _applyPushResult(
    LocalVaultStore tx,
    PushChange change,
    PushResult result,
  ) async {
    final current = await tx.findRecord(change.itemId);
    if (current == null) return const SyncReport();
    // O usuário pode ter editado o item durante o envio.
    final unchanged = current.pendingChangeId == change.changeId;

    switch (result.status) {
      case PushStatus.applied:
        final version = result.version ?? current.serverVersion;
        await tx.upsertRecord(
          unchanged
              ? current.copyWith(serverVersion: version).withoutPending()
              // A nova edição passa a ter como base a versão recém-aceita.
              : current.copyWith(serverVersion: version),
        );
        return const SyncReport(pushed: 1);

      case PushStatus.conflict:
        final server = result.serverItem;
        if (server == null) return const SyncReport(rejected: 1);
        await tx.saveConflict(
          SyncConflict.fromLocal(current, id: _uuid.v4(), detectedAt: _clock().toUtc()),
        );
        await tx.upsertRecord(StoredRecord.fromRemote(server));
        return const SyncReport(conflicts: 1);

      case PushStatus.rejected:
        final retry = current.copyWith(pendingChangeId: _uuid.v4());
        await tx.upsertRecord(
          result.reason == PushRejection.baseVersionNotFound
              ? retry.copyWith(serverVersion: 0)
              : retry,
        );
        return const SyncReport(rejected: 1);
    }
  }

  Future<SyncReport> _pull() async {
    var pulled = 0;
    var cursor = int.tryParse(await _store.readMeta(MetaKeys.syncCursor) ?? '') ?? 0;
    var restarted = false;

    while (true) {
      final page = await _api.pull(since: cursor, limit: pullPageSize);

      if (cursor > page.latestRevision && !restarted) {
        // Servidor restaurado de backup: recomeça do zero (uma única vez).
        restarted = true;
        cursor = 0;
        continue;
      }

      pulled += await _store.transaction((tx) async {
        var applied = 0;
        for (final remote in page.items) {
          if (await _applyRemote(tx, remote)) applied++;
        }
        await tx.writeMeta(MetaKeys.syncCursor, '${page.cursor}');
        return applied;
      });

      if (!page.hasMore || page.items.isEmpty || page.cursor <= cursor) break;
      cursor = page.cursor;
    }
    return SyncReport(pulled: pulled);
  }

  /// Retorna `true` se o registro remoto foi aplicado.
  Future<bool> _applyRemote(LocalVaultStore tx, RemoteRecord remote) async {
    final local = await tx.findRecord(remote.id);

    // Alteração local pendente: o próximo envio detectará o conflito no
    // servidor, que devolverá a versão atual. Nada é sobrescrito aqui.
    if (local != null && local.hasPendingChange) return false;

    if (local != null && local.serverVersion > remote.version) {
      // O servidor tem uma versão mais antiga que a nossa (restauração de
      // backup): reenvia a versão local sobre a do servidor.
      await tx.upsertRecord(local.copyWith(
        serverVersion: remote.version,
        pendingChangeId: _uuid.v4(),
        pendingOperation:
            local.deleted ? PendingOperation.delete : PendingOperation.upsert,
      ));
      return false;
    }

    await tx.upsertRecord(StoredRecord.fromRemote(remote));
    return true;
  }

  PushChange _toChange(StoredRecord record) {
    final operation = record.pendingOperation ??
        (record.deleted ? PendingOperation.delete : PendingOperation.upsert);
    return PushChange(
      changeId: record.pendingChangeId!,
      itemId: record.id,
      operation: operation,
      baseVersion: record.serverVersion,
      encryptedData: operation == PendingOperation.upsert ? record.encryptedData : null,
      nonce: operation == PendingOperation.upsert ? record.nonce : null,
      cryptoVersion: operation == PendingOperation.upsert ? record.cryptoVersion : null,
    );
  }
}
