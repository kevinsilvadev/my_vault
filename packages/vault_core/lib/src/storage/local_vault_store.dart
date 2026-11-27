import 'stored_record.dart';

/// Chaves da tabela de metadados local.
abstract final class MetaKeys {
  /// Envelope da chave do cofre (JSON).
  static const String keyEnvelope = 'vault.keyEnvelope';

  /// Impressão digital da chave do cofre (detecção de substituição).
  static const String keyFingerprint = 'vault.keyFingerprint';

  /// Cursor de sincronização (última revisão recebida).
  static const String syncCursor = 'sync.cursor';

  /// Conta à qual o cofre local está vinculado.
  static const String boundAccountId = 'account.userId';
}

/// Porta de persistência local (SQLite no app; memória nos testes).
///
/// Implementações devem garantir atomicidade em [transaction]: ou todas as
/// escritas da ação são aplicadas, ou nenhuma.
abstract interface class LocalVaultStore {
  Future<T> transaction<T>(Future<T> Function(LocalVaultStore tx) action);

  Future<String?> readMeta(String key);

  /// `null` remove a chave.
  Future<void> writeMeta(String key, String? value);

  Future<StoredRecord?> findRecord(String id);

  Future<List<StoredRecord>> listRecords({bool includeDeleted = false});

  Future<List<StoredRecord>> pendingRecords();

  Future<void> upsertRecord(StoredRecord record);

  Future<List<SyncConflict>> listConflicts();

  Future<SyncConflict?> findConflict(String id);

  Future<void> saveConflict(SyncConflict conflict);

  Future<void> deleteConflict(String id);
}
