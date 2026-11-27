import 'package:meta/meta.dart';

import '../sync/sync_models.dart';

const Object _keep = Object();

/// Registro persistido localmente: somente ciphertext e metadados.
///
/// A fila de alterações pendentes é representada pelos registros com
/// [pendingChangeId] preenchido: o conteúdo a enviar é sempre o estado atual
/// do registro, e [serverVersion] é a `baseVersion` do envio.
@immutable
final class StoredRecord {
  const StoredRecord({
    required this.id,
    required this.encryptedData,
    required this.nonce,
    required this.cryptoVersion,
    required this.serverVersion,
    required this.deleted,
    required this.updatedAt,
    this.pendingChangeId,
    this.pendingOperation,
  });

  factory StoredRecord.fromRemote(RemoteRecord remote) => StoredRecord(
        id: remote.id,
        encryptedData: remote.encryptedData,
        nonce: remote.nonce,
        cryptoVersion: remote.cryptoVersion,
        serverVersion: remote.version,
        deleted: remote.deleted,
        updatedAt: remote.updatedAt,
      );

  final String id;
  final String? encryptedData;
  final String? nonce;
  final int cryptoVersion;

  /// Última versão do servidor conhecida (0 = nunca sincronizado).
  final int serverVersion;
  final bool deleted;
  final DateTime updatedAt;
  final String? pendingChangeId;
  final PendingOperation? pendingOperation;

  bool get hasPendingChange => pendingChangeId != null;

  StoredRecord copyWith({
    Object? encryptedData = _keep,
    Object? nonce = _keep,
    int? cryptoVersion,
    int? serverVersion,
    bool? deleted,
    DateTime? updatedAt,
    Object? pendingChangeId = _keep,
    Object? pendingOperation = _keep,
  }) =>
      StoredRecord(
        id: id,
        encryptedData: identical(encryptedData, _keep)
            ? this.encryptedData
            : encryptedData as String?,
        nonce: identical(nonce, _keep) ? this.nonce : nonce as String?,
        cryptoVersion: cryptoVersion ?? this.cryptoVersion,
        serverVersion: serverVersion ?? this.serverVersion,
        deleted: deleted ?? this.deleted,
        updatedAt: updatedAt ?? this.updatedAt,
        pendingChangeId: identical(pendingChangeId, _keep)
            ? this.pendingChangeId
            : pendingChangeId as String?,
        pendingOperation: identical(pendingOperation, _keep)
            ? this.pendingOperation
            : pendingOperation as PendingOperation?,
      );

  StoredRecord withoutPending() =>
      copyWith(pendingChangeId: null, pendingOperation: null);
}

/// Versão local preservada quando o servidor rejeita uma alteração por
/// conflito. O lado remoto é o estado atual do [StoredRecord] do item.
@immutable
final class SyncConflict {
  const SyncConflict({
    required this.id,
    required this.itemId,
    required this.localEncryptedData,
    required this.localNonce,
    required this.localCryptoVersion,
    required this.localDeleted,
    required this.detectedAt,
  });

  factory SyncConflict.fromLocal(
    StoredRecord local, {
    required String id,
    required DateTime detectedAt,
  }) =>
      SyncConflict(
        id: id,
        itemId: local.id,
        localEncryptedData: local.encryptedData,
        localNonce: local.nonce,
        localCryptoVersion: local.cryptoVersion,
        localDeleted: local.deleted,
        detectedAt: detectedAt,
      );

  final String id;
  final String itemId;
  final String? localEncryptedData;
  final String? localNonce;
  final int localCryptoVersion;
  final bool localDeleted;
  final DateTime detectedAt;
}

/// Como resolver um conflito. Toda resolução exige ação explícita do usuário.
enum ConflictResolution {
  /// Reenvia a versão local sobre a versão atual do servidor.
  keepLocal,

  /// Descarta a versão local.
  keepRemote,

  /// Mantém a versão do servidor e salva a local como um novo item.
  keepBoth,
}
