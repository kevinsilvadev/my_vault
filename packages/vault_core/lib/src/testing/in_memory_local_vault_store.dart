import 'dart:async';

import '../storage/local_vault_store.dart';
import '../storage/stored_record.dart';

/// [LocalVaultStore] em memória, para testes.
///
/// Transações são serializadas e revertidas em caso de erro, imitando o
/// comportamento do SQLite.
final class InMemoryLocalVaultStore implements LocalVaultStore {
  final Map<String, String> _meta = {};
  final Map<String, StoredRecord> _records = {};
  final Map<String, SyncConflict> _conflicts = {};

  static final Object _zoneKey = Object();
  Future<void> _tail = Future.value();

  /// Cópia dos registros, para inspeção em testes.
  Map<String, StoredRecord> get records => Map.unmodifiable(_records);

  @override
  Future<T> transaction<T>(Future<T> Function(LocalVaultStore tx) action) async {
    if (identical(Zone.current[_zoneKey], this)) return action(this);

    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    await previous;

    final metaBackup = Map.of(_meta);
    final recordsBackup = Map.of(_records);
    final conflictsBackup = Map.of(_conflicts);
    try {
      return await runZoned(() => action(this), zoneValues: {_zoneKey: this});
    } on Object {
      _meta
        ..clear()
        ..addAll(metaBackup);
      _records
        ..clear()
        ..addAll(recordsBackup);
      _conflicts
        ..clear()
        ..addAll(conflictsBackup);
      rethrow;
    } finally {
      done.complete();
    }
  }

  @override
  Future<String?> readMeta(String key) async => _meta[key];

  @override
  Future<void> writeMeta(String key, String? value) async {
    if (value == null) {
      _meta.remove(key);
    } else {
      _meta[key] = value;
    }
  }

  @override
  Future<StoredRecord?> findRecord(String id) async => _records[id];

  @override
  Future<List<StoredRecord>> listRecords({bool includeDeleted = false}) async =>
      _records.values.where((r) => includeDeleted || !r.deleted).toList();

  @override
  Future<List<StoredRecord>> pendingRecords() async =>
      _records.values.where((r) => r.hasPendingChange).toList();

  @override
  Future<void> upsertRecord(StoredRecord record) async {
    _records[record.id] = record;
  }

  @override
  Future<List<SyncConflict>> listConflicts() async => _conflicts.values.toList();

  @override
  Future<SyncConflict?> findConflict(String id) async => _conflicts[id];

  @override
  Future<void> saveConflict(SyncConflict conflict) async {
    _conflicts[conflict.id] = conflict;
  }

  @override
  Future<void> deleteConflict(String id) async {
    _conflicts.remove(id);
  }
}
