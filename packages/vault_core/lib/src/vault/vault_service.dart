import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

import '../crypto/aes_gcm_cipher.dart';
import '../crypto/bytes.dart';
import '../crypto/kdf_params.dart';
import '../crypto/vault_key_envelope.dart';
import '../exceptions.dart';
import '../models/vault_item.dart';
import '../storage/local_vault_store.dart';
import '../storage/stored_record.dart';
import '../sync/sync_models.dart';
import 'master_password_policy.dart';
import 'vault_keyring.dart';
import 'vault_session.dart';

/// Itens descriptografados do cofre.
@immutable
final class VaultSnapshot {
  const VaultSnapshot({required this.items, required this.undecryptableIds});

  final List<VaultItem> items;

  /// Registros que falharam na autenticação criptográfica (corrompidos ou
  /// adulterados). São ignorados, nunca exibidos parcialmente.
  final List<String> undecryptableIds;
}

/// Conflito pronto para exibição.
@immutable
final class ConflictView {
  const ConflictView({
    required this.conflictId,
    required this.itemId,
    required this.local,
    required this.remote,
    required this.localDeleted,
    required this.remoteDeleted,
    required this.detectedAt,
  });

  final String conflictId;
  final String itemId;

  /// `null` se excluído ou ilegível.
  final VaultItem? local;
  final VaultItem? remote;
  final bool localDeleted;
  final bool remoteDeleted;
  final DateTime detectedAt;
}

/// Casos de uso do cofre: criação, desbloqueio, bloqueio, CRUD e conflitos.
///
/// Toda escrita local cifra o conteúdo antes de persistir e coloca o registro
/// na fila de sincronização.
final class VaultService {
  VaultService({
    required LocalVaultStore store,
    VaultKeyring? keyring,
    DateTime Function()? clock,
    Uuid? uuid,
  })  : _store = store,
        _keyring = keyring ?? VaultKeyring(),
        _clock = clock ?? DateTime.now,
        _uuid = uuid ?? const Uuid();

  static const String conflictCopySuffix = ' (cópia de conflito)';

  final LocalVaultStore _store;
  final VaultKeyring _keyring;
  final DateTime Function() _clock;
  final Uuid _uuid;
  VaultSession? _session;

  bool get isUnlocked => _session != null && !_session!.isClosed;

  Future<bool> hasVault() async =>
      (await _store.readMeta(MetaKeys.keyEnvelope)) != null;

  Future<VaultKeyEnvelope?> readEnvelope() async {
    final raw = await _store.readMeta(MetaKeys.keyEnvelope);
    return raw == null ? null : VaultKeyEnvelope.decode(raw);
  }

  /// Cria um cofre novo e o deixa desbloqueado.
  Future<void> createVault(
    String masterPassword, {
    KdfParams params = KdfParams.recommended,
  }) async {
    if (await hasVault()) throw const VaultAlreadyExistsException();
    final issues = MasterPasswordPolicy.validate(masterPassword);
    if (issues.isNotEmpty) throw WeakMasterPasswordException(issues);

    final (envelope, session) =
        await _keyring.create(masterPassword, params: params, now: _clock());
    try {
      final fingerprint = await session.keyFingerprint();
      await _store.transaction((tx) async {
        await tx.writeMeta(MetaKeys.keyEnvelope, envelope.encode());
        await tx.writeMeta(MetaKeys.keyFingerprint, fingerprint);
      });
    } on Object {
      session.close();
      rethrow;
    }
    _replaceSession(session);
  }

  /// Adota o envelope de um cofre existente (vindo do servidor) em um
  /// dispositivo sem cofre local. O desbloqueio ainda exige a senha mestre.
  Future<void> adoptEnvelope(VaultKeyEnvelope envelope) async {
    final current = await readEnvelope();
    if (current != null) {
      if (current.matches(envelope)) return;
      throw const VaultAlreadyExistsException();
    }
    await _store.writeMeta(MetaKeys.keyEnvelope, envelope.encode());
  }

  /// Desbloqueia com a senha mestre.
  ///
  /// Lança [InvalidMasterPasswordException] antes de ler qualquer registro,
  /// portanto o erro não revela a existência de itens específicos.
  Future<void> unlock(String masterPassword) async {
    final envelope = await readEnvelope();
    if (envelope == null) throw const VaultNotFoundException();
    final session = await _keyring.open(envelope, masterPassword);
    try {
      final fingerprint = await session.keyFingerprint();
      final known = await _store.readMeta(MetaKeys.keyFingerprint);
      if (known == null) {
        await _store.writeMeta(MetaKeys.keyFingerprint, fingerprint);
      } else if (!constantTimeEquals(utf8.encode(known), utf8.encode(fingerprint))) {
        throw const VaultKeyMismatchException();
      }
    } on Object {
      session.close();
      rethrow;
    }
    _replaceSession(session);
  }

  /// Bloqueia e zera a chave do cofre em memória.
  void lock() {
    _session?.close();
    _session = null;
  }

  /// Novo item com identificador e datas preenchidos (ainda não salvo).
  VaultItem draftItem() {
    final now = _clock().toUtc();
    return VaultItem(id: _uuid.v4(), title: '', createdAt: now, updatedAt: now);
  }

  Future<VaultSnapshot> loadItems() async {
    final session = _requireSession();
    final records = await _store.listRecords();
    final items = <VaultItem>[];
    final failed = <String>[];
    for (final record in records) {
      final item = await _tryDecrypt(session, record);
      if (item == null) {
        failed.add(record.id);
      } else {
        items.add(item);
      }
    }
    return VaultSnapshot(items: items, undecryptableIds: failed);
  }

  /// Cria ou atualiza um item. Retorna o item como foi salvo.
  Future<VaultItem> saveItem(VaultItem item) async {
    final session = _requireSession();
    final normalized = item.copyWith(
      title: item.title.trim(),
      category: item.category.trim(),
      url: item.url.trim(),
      updatedAt: _clock().toUtc(),
    );
    final issues = VaultItemValidator.validate(normalized);
    if (issues.isNotEmpty) throw ItemValidationException(issues);

    final payload = await session.encryptItem(normalized);
    await _store.transaction((tx) async {
      final existing = await tx.findRecord(normalized.id);
      await tx.upsertRecord(_pendingRecord(
        id: normalized.id,
        payload: payload,
        serverVersion: existing?.serverVersion ?? 0,
        updatedAt: normalized.updatedAt,
      ));
    });
    return normalized;
  }

  /// Exclui um item, gerando um tombstone que será sincronizado.
  Future<void> deleteItem(String id) async {
    _requireSession();
    await _store.transaction((tx) async {
      final existing = await tx.findRecord(id);
      if (existing == null || existing.deleted) return;
      await tx.upsertRecord(existing.copyWith(
        encryptedData: null,
        nonce: null,
        deleted: true,
        updatedAt: _clock().toUtc(),
        pendingChangeId: _uuid.v4(),
        pendingOperation: PendingOperation.delete,
      ));
    });
  }

  Future<int> pendingChangeCount() async =>
      (await _store.pendingRecords()).length;

  Future<List<ConflictView>> loadConflicts() async {
    final session = _requireSession();
    final conflicts = await _store.listConflicts();
    final views = <ConflictView>[];
    for (final conflict in conflicts) {
      final remote = await _store.findRecord(conflict.itemId);
      VaultItem? local;
      if (!conflict.localDeleted &&
          conflict.localEncryptedData != null &&
          conflict.localNonce != null) {
        local = await _tryDecryptRaw(
          session,
          itemId: conflict.itemId,
          encryptedData: conflict.localEncryptedData!,
          nonce: conflict.localNonce!,
          cryptoVersion: conflict.localCryptoVersion,
        );
      }
      views.add(ConflictView(
        conflictId: conflict.id,
        itemId: conflict.itemId,
        local: local,
        remote: remote == null ? null : await _tryDecrypt(session, remote),
        localDeleted: conflict.localDeleted,
        remoteDeleted: remote?.deleted ?? true,
        detectedAt: conflict.detectedAt,
      ));
    }
    views.sort((a, b) => a.detectedAt.compareTo(b.detectedAt));
    return views;
  }

  Future<void> resolveConflict(
    String conflictId,
    ConflictResolution resolution,
  ) async {
    final session = _requireSession();
    await _store.transaction((tx) async {
      final conflict = await tx.findConflict(conflictId);
      if (conflict == null) throw const ConflictNotFoundException();
      final current = await tx.findRecord(conflict.itemId);
      final now = _clock().toUtc();

      switch (resolution) {
        case ConflictResolution.keepRemote:
          break;

        case ConflictResolution.keepLocal:
          // O ciphertext local continua válido: o AAD depende só do id.
          await tx.upsertRecord(StoredRecord(
            id: conflict.itemId,
            encryptedData: conflict.localDeleted ? null : conflict.localEncryptedData,
            nonce: conflict.localDeleted ? null : conflict.localNonce,
            cryptoVersion: conflict.localCryptoVersion,
            serverVersion: current?.serverVersion ?? 0,
            deleted: conflict.localDeleted,
            updatedAt: now,
            pendingChangeId: _uuid.v4(),
            pendingOperation: conflict.localDeleted
                ? PendingOperation.delete
                : PendingOperation.upsert,
          ));

        case ConflictResolution.keepBoth:
          final data = conflict.localEncryptedData;
          final nonce = conflict.localNonce;
          if (conflict.localDeleted || data == null || nonce == null) break;
          final local = await session.decryptItem(
            itemId: conflict.itemId,
            payload: EncryptedPayload.fromBase64(nonce: nonce, ciphertext: data),
            cryptoVersion: conflict.localCryptoVersion,
          );
          final copy = local.duplicateAs(
            id: _uuid.v4(),
            now: now,
            titleSuffix: conflictCopySuffix,
          );
          final payload = await session.encryptItem(copy);
          await tx.upsertRecord(_pendingRecord(
            id: copy.id,
            payload: payload,
            serverVersion: 0,
            updatedAt: now,
          ));
      }
      await tx.deleteConflict(conflict.id);
    });
  }

  StoredRecord _pendingRecord({
    required String id,
    required EncryptedPayload payload,
    required int serverVersion,
    required DateTime updatedAt,
  }) =>
      StoredRecord(
        id: id,
        encryptedData: payload.ciphertextBase64,
        nonce: payload.nonceBase64,
        cryptoVersion: ItemCryptoFormat.current,
        serverVersion: serverVersion,
        deleted: false,
        updatedAt: updatedAt,
        pendingChangeId: _uuid.v4(),
        pendingOperation: PendingOperation.upsert,
      );

  Future<VaultItem?> _tryDecrypt(VaultSession session, StoredRecord record) {
    final data = record.encryptedData;
    final nonce = record.nonce;
    if (record.deleted || data == null || nonce == null) {
      return Future.value();
    }
    return _tryDecryptRaw(
      session,
      itemId: record.id,
      encryptedData: data,
      nonce: nonce,
      cryptoVersion: record.cryptoVersion,
    );
  }

  Future<VaultItem?> _tryDecryptRaw(
    VaultSession session, {
    required String itemId,
    required String encryptedData,
    required String nonce,
    required int cryptoVersion,
  }) async {
    try {
      return await session.decryptItem(
        itemId: itemId,
        payload: EncryptedPayload.fromBase64(nonce: nonce, ciphertext: encryptedData),
        cryptoVersion: cryptoVersion,
      );
    } on DecryptionFailedException {
      return null;
    } on UnsupportedFormatException {
      return null;
    }
  }

  VaultSession _requireSession() {
    final session = _session;
    if (session == null || session.isClosed) throw const VaultLockedException();
    return session;
  }

  void _replaceSession(VaultSession session) {
    _session?.close();
    _session = session;
  }
}
