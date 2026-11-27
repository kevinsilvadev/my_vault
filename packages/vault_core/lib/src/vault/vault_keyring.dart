import '../crypto/aes_gcm_cipher.dart';
import '../crypto/bytes.dart';
import '../crypto/kdf_params.dart';
import '../crypto/key_derivation.dart';
import '../crypto/sensitive_key.dart';
import '../crypto/vault_key_envelope.dart';
import '../exceptions.dart';
import 'vault_session.dart';

/// Criação e abertura do envelope da chave do cofre.
///
/// Fluxo de criação (docs/security.md):
/// 1. salt aleatório de 128 bits;
/// 2. KEK = Argon2id(senha mestre, salt, parâmetros);
/// 3. chave do cofre = 256 bits aleatórios;
/// 4. envelope = AES-256-GCM(KEK, chave do cofre, AAD = versão+parâmetros).
///
/// A senha mestre e a KEK nunca são persistidas; a KEK é zerada logo após o
/// uso.
final class VaultKeyring {
  VaultKeyring({KeyDerivation? keyDerivation, AesGcmCipher? cipher})
      : _kdf = keyDerivation ?? const KeyDerivation(),
        _cipher = cipher ?? AesGcmCipher();

  final KeyDerivation _kdf;
  final AesGcmCipher _cipher;

  Future<(VaultKeyEnvelope, VaultSession)> create(
    String masterPassword, {
    KdfParams params = KdfParams.recommended,
    DateTime? now,
  }) async {
    final salt = secureRandomBytes(KeyDerivation.saltLength);
    final createdAt = (now ?? DateTime.now()).toUtc();
    const formatVersion = VaultKeyEnvelope.currentFormatVersion;

    final kek = await _kdf.deriveKey(
      masterPassword: masterPassword,
      salt: salt,
      params: params,
    );
    final vaultKey = SensitiveKey(secureRandomBytes(AesGcmCipher.keyLength));
    try {
      final wrapped = await _cipher.encrypt(
        vaultKey.bytes,
        kek,
        associatedData: VaultKeyEnvelope.associatedDataFor(
          formatVersion: formatVersion,
          kdfParams: params,
          salt: salt,
        ),
      );
      final envelope = VaultKeyEnvelope(
        formatVersion: formatVersion,
        kdfParams: params,
        salt: salt,
        wrappedKey: wrapped,
        createdAt: createdAt,
      );
      return (envelope, VaultSession(vaultKey, cipher: _cipher));
    } on Object {
      vaultKey.destroy();
      rethrow;
    } finally {
      kek.destroy();
    }
  }

  /// Abre o envelope. Senha errada ou envelope adulterado resultam em
  /// [InvalidMasterPasswordException] — sem distinguir os casos.
  Future<VaultSession> open(
    VaultKeyEnvelope envelope,
    String masterPassword,
  ) async {
    if (envelope.formatVersion != VaultKeyEnvelope.currentFormatVersion) {
      throw const UnsupportedFormatException();
    }
    final kek = await _kdf.deriveKey(
      masterPassword: masterPassword,
      salt: envelope.salt,
      params: envelope.kdfParams,
    );
    try {
      final keyBytes = await _cipher.decrypt(
        envelope.wrappedKey,
        kek,
        associatedData: envelope.associatedData,
      );
      if (keyBytes.length != AesGcmCipher.keyLength) {
        wipeBytes(keyBytes);
        throw const InvalidMasterPasswordException();
      }
      return VaultSession(SensitiveKey(keyBytes), cipher: _cipher);
    } on DecryptionFailedException {
      throw const InvalidMasterPasswordException();
    } finally {
      kek.destroy();
    }
  }
}
