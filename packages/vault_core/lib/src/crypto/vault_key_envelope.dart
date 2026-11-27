import 'dart:convert';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../exceptions.dart';
import '../json_reader.dart';
import 'aes_gcm_cipher.dart';
import 'bytes.dart';
import 'kdf_params.dart';

/// Envelope da chave do cofre: a chave aleatória de 256 bits, cifrada com a
/// chave derivada da senha mestre, mais os parâmetros necessários para
/// derivá-la novamente.
///
/// Não contém nenhum segredo em claro e pode ser armazenado no servidor.
@immutable
final class VaultKeyEnvelope {
  const VaultKeyEnvelope({
    required this.formatVersion,
    required this.kdfParams,
    required this.salt,
    required this.wrappedKey,
    required this.createdAt,
  });

  static const int currentFormatVersion = 1;

  factory VaultKeyEnvelope.fromJson(Map<String, Object?> json) {
    try {
      final reader = JsonReader(json);
      final formatVersion = reader.integer('formatVersion');
      if (formatVersion != currentFormatVersion) {
        throw const UnsupportedFormatException();
      }
      final kdf = reader.object('kdf');
      if (kdf.string('algorithm') != KdfParams.algorithm) {
        throw const UnsupportedFormatException();
      }
      final wrapped = reader.object('wrappedKey');
      return VaultKeyEnvelope(
        formatVersion: formatVersion,
        kdfParams: KdfParams(
          memoryKiB: kdf.integer('memoryKiB'),
          iterations: kdf.integer('iterations'),
          parallelism: kdf.integer('parallelism'),
        ),
        salt: kdf.base64Bytes('salt'),
        wrappedKey: EncryptedPayload(
          nonce: wrapped.base64Bytes('nonce'),
          ciphertext: wrapped.base64Bytes('ciphertext'),
        ),
        createdAt: reader.dateTime('createdAt'),
      );
    } on FormatException {
      throw const UnsupportedFormatException('Envelope do cofre inválido.');
    }
  }

  factory VaultKeyEnvelope.decode(String source) {
    try {
      return VaultKeyEnvelope.fromJson(decodeJsonObject(source).json);
    } on FormatException {
      throw const UnsupportedFormatException('Envelope do cofre inválido.');
    }
  }

  final int formatVersion;
  final KdfParams kdfParams;
  final Uint8List salt;
  final EncryptedPayload wrappedKey;
  final DateTime createdAt;

  /// Dados associados do AES-GCM que protege a chave do cofre. Vinculam o
  /// envelope à sua versão e parâmetros: qualquer alteração invalida a tag.
  List<int> get associatedData => associatedDataFor(
        formatVersion: formatVersion,
        kdfParams: kdfParams,
        salt: salt,
      );

  static List<int> associatedDataFor({
    required int formatVersion,
    required KdfParams kdfParams,
    required List<int> salt,
  }) =>
      utf8.encode(
        'myvault/vault-key/v$formatVersion'
        '|${KdfParams.algorithm}'
        '|m=${kdfParams.memoryKiB}'
        '|t=${kdfParams.iterations}'
        '|p=${kdfParams.parallelism}'
        '|salt=${base64Encode(salt)}',
      );

  Map<String, Object?> toJson() => {
        'formatVersion': formatVersion,
        'kdf': {
          'algorithm': KdfParams.algorithm,
          'memoryKiB': kdfParams.memoryKiB,
          'iterations': kdfParams.iterations,
          'parallelism': kdfParams.parallelism,
          'salt': base64Encode(salt),
        },
        'wrappedKey': {
          'nonce': wrappedKey.nonceBase64,
          'ciphertext': wrappedKey.ciphertextBase64,
        },
        'createdAt': createdAt.toUtc().toIso8601String(),
      };

  String encode() => jsonEncode(toJson());

  /// Igualdade criptográfica (ignora [createdAt] e a ordem das chaves JSON,
  /// que o PostgreSQL `jsonb` não preserva).
  bool matches(VaultKeyEnvelope other) =>
      formatVersion == other.formatVersion &&
      kdfParams == other.kdfParams &&
      constantTimeEquals(salt, other.salt) &&
      constantTimeEquals(wrappedKey.nonce, other.wrappedKey.nonce) &&
      constantTimeEquals(wrappedKey.ciphertext, other.wrappedKey.ciphertext);
}
