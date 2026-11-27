import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../crypto/aes_gcm_cipher.dart';
import '../crypto/bytes.dart';
import '../crypto/sensitive_key.dart';
import '../exceptions.dart';
import '../models/vault_item.dart';

/// Formato criptográfico dos registros do cofre.
///
/// v1: AES-256-GCM, nonce aleatório de 96 bits, AAD = `myvault/item/v1/<id>`
/// (vincula o ciphertext ao identificador e impede troca de registros),
/// conteúdo = JSON UTF-8 de [VaultItem.toJson].
abstract final class ItemCryptoFormat {
  static const int v1 = 1;
  static const int current = v1;

  static List<int> associatedData(String itemId) =>
      utf8.encode('myvault/item/v1/$itemId');
}

/// Cofre desbloqueado: detém a chave do cofre em memória.
///
/// Deve ser fechado com [close] ao bloquear; depois disso, qualquer operação
/// lança [VaultLockedException].
final class VaultSession {
  VaultSession(SensitiveKey vaultKey, {AesGcmCipher? cipher})
      : _key = vaultKey,
        _cipher = cipher ?? AesGcmCipher();

  final SensitiveKey _key;
  final AesGcmCipher _cipher;

  bool get isClosed => _key.isDestroyed;

  Future<EncryptedPayload> encryptItem(VaultItem item) async {
    _ensureOpen();
    final plaintext = Uint8List.fromList(utf8.encode(jsonEncode(item.toJson())));
    try {
      return await _cipher.encrypt(
        plaintext,
        _key,
        associatedData: ItemCryptoFormat.associatedData(item.id),
      );
    } finally {
      wipeBytes(plaintext);
    }
  }

  /// Descriptografa e valida um registro. A tag GCM é verificada antes de
  /// qualquer interpretação do conteúdo.
  Future<VaultItem> decryptItem({
    required String itemId,
    required EncryptedPayload payload,
    required int cryptoVersion,
  }) async {
    _ensureOpen();
    if (cryptoVersion != ItemCryptoFormat.v1) {
      throw const UnsupportedFormatException();
    }
    final clear = await _cipher.decrypt(
      payload,
      _key,
      associatedData: ItemCryptoFormat.associatedData(itemId),
    );
    try {
      final decoded = jsonDecode(utf8.decode(clear));
      if (decoded is! Map<String, Object?>) {
        throw const DecryptionFailedException();
      }
      final item = VaultItem.fromJson(decoded);
      if (item.id != itemId) throw const DecryptionFailedException();
      return item;
    } on FormatException {
      throw const DecryptionFailedException();
    } finally {
      wipeBytes(clear);
    }
  }

  /// Identificador estável da chave do cofre (HMAC-SHA256 com rótulo fixo).
  ///
  /// Não permite recuperar a chave. É guardado localmente para detectar
  /// substituição do envelope por um servidor malicioso.
  Future<String> keyFingerprint() async {
    _ensureOpen();
    final mac = await Hmac.sha256().calculateMac(
      utf8.encode('myvault/key-fingerprint/v1'),
      secretKey: SecretKeyData(_key.bytes),
    );
    return base64Encode(mac.bytes);
  }

  /// Zera a chave do cofre. Idempotente.
  void close() => _key.destroy();

  void _ensureOpen() {
    if (_key.isDestroyed) throw const VaultLockedException();
  }
}
