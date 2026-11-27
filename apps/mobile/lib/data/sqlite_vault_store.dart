import 'package:sqflite/sqflite.dart';
import 'package:vault_core/vault_core.dart';

/// [LocalVaultStore] sobre SQLite.
final class SqliteVaultStore implements LocalVaultStore {
  SqliteVaultStore(Database db) : _executor = db;

  SqliteVaultStore._transaction(Transaction txn) : _executor = txn;

  final DatabaseExecutor _executor;

  @override
  Future<T> transaction<T>(Future<T> Function(LocalVaultStore tx) action) {
    final executor = _executor;
    if (executor is Database) {
      return executor.transaction((txn) => action(SqliteVaultStore._transaction(txn)));
    }
    // Já dentro de uma transação.
    return action(this);
  }

  @override
  Future<String?> readMeta(String key) async {
    final rows = await _executor.query('meta',
        columns: ['value'], where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  @override
  Future<void> writeMeta(String key, String? value) async {
    if (value == null) {
      await _executor.delete('meta', where: 'key = ?', whereArgs: [key]);
    } else {
      await _executor.insert('meta', {'key': key, 'value': value},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  @override
  Future<StoredRecord?> findRecord(String id) async {
    final rows =
        await _executor.query('records', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : _recordFromRow(rows.first);
  }

  @override
  Future<List<StoredRecord>> listRecords({bool includeDeleted = false}) async {
    final rows = await _executor.query('records',
        where: includeDeleted ? null : 'deleted = 0');
    return rows.map(_recordFromRow).toList();
  }

  @override
  Future<List<StoredRecord>> pendingRecords() async {
    final rows =
        await _executor.query('records', where: 'pending_change_id IS NOT NULL');
    return rows.map(_recordFromRow).toList();
  }

  @override
  Future<void> upsertRecord(StoredRecord record) async {
    await _executor.insert(
      'records',
      {
        'id': record.id,
        'encrypted_data': record.encryptedData,
        'nonce': record.nonce,
        'crypto_version': record.cryptoVersion,
        'server_version': record.serverVersion,
        'deleted': record.deleted ? 1 : 0,
        'updated_at': record.updatedAt.toUtc().toIso8601String(),
        'pending_change_id': record.pendingChangeId,
        'pending_operation': record.pendingOperation?.name,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<SyncConflict>> listConflicts() async {
    final rows = await _executor.query('conflicts', orderBy: 'detected_at');
    return rows.map(_conflictFromRow).toList();
  }

  @override
  Future<SyncConflict?> findConflict(String id) async {
    final rows =
        await _executor.query('conflicts', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : _conflictFromRow(rows.first);
  }

  @override
  Future<void> saveConflict(SyncConflict conflict) async {
    await _executor.insert(
      'conflicts',
      {
        'id': conflict.id,
        'item_id': conflict.itemId,
        'local_encrypted_data': conflict.localEncryptedData,
        'local_nonce': conflict.localNonce,
        'local_crypto_version': conflict.localCryptoVersion,
        'local_deleted': conflict.localDeleted ? 1 : 0,
        'detected_at': conflict.detectedAt.toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> deleteConflict(String id) async {
    await _executor.delete('conflicts', where: 'id = ?', whereArgs: [id]);
  }

  static StoredRecord _recordFromRow(Map<String, Object?> row) {
    final pending = row['pending_operation'] as String?;
    return StoredRecord(
      id: row['id']! as String,
      encryptedData: row['encrypted_data'] as String?,
      nonce: row['nonce'] as String?,
      cryptoVersion: row['crypto_version']! as int,
      serverVersion: row['server_version']! as int,
      deleted: row['deleted'] == 1,
      updatedAt: DateTime.parse(row['updated_at']! as String),
      pendingChangeId: row['pending_change_id'] as String?,
      pendingOperation: pending == null ? null : PendingOperation.parse(pending),
    );
  }

  static SyncConflict _conflictFromRow(Map<String, Object?> row) => SyncConflict(
        id: row['id']! as String,
        itemId: row['item_id']! as String,
        localEncryptedData: row['local_encrypted_data'] as String?,
        localNonce: row['local_nonce'] as String?,
        localCryptoVersion: row['local_crypto_version']! as int,
        localDeleted: row['local_deleted'] == 1,
        detectedAt: DateTime.parse(row['detected_at']! as String),
      );
}
