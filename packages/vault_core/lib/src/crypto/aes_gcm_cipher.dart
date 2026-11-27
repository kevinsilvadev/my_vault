import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:meta/meta.dart';

import '../exceptions.dart';
import 'bytes.dart';
import 'sensitive_key.dart';

/// Resultado de uma cifragem AES-256-GCM: nonce + (ciphertext || tag).
@immutable
final class EncryptedPayload {
  const EncryptedPayload({required this.nonce, required this.ciphertext});

  /// Lança [DecryptionFailedException] se o base64 for inválido, sem expor
  /// detalhes do conteúdo.
  factory EncryptedPayload.fromBase64({
    required String nonce,
    required String ciphertext,
  }) {
    try {
      return EncryptedPayload(
        nonce: base64Decode(nonce),
        ciphertext: base64Decode(ciphertext),
      );
    } on FormatException {
      throw const DecryptionFailedException();
    }
  }

  final Uint8List nonce;

  /// Ciphertext seguido da tag de autenticação de 16 bytes.
  final Uint8List ciphertext;

  String get nonceBase64 => base64Encode(nonce);
  String get ciphertextBase64 => base64Encode(ciphertext);
}

/// AES-256-GCM com nonce aleatório de 96 bits por operação.
///
/// Cada chamada a [encrypt] gera um nonce novo a partir do CSPRNG; não há
/// API para fornecer nonce externo, eliminando o risco de reutilização
/// acidental. O limite seguro com nonces aleatórios é ~2^32 cifragens por
/// chave — ordens de grandeza acima do uso de um cofre pessoal.
final class AesGcmCipher {
  AesGcmCipher() : _algorithm = AesGcm.with256bits();

  static const int nonceLength = 12;
  static const int tagLength = 16;
  static const int keyLength = 32;

  final AesGcm _algorithm;

  Future<EncryptedPayload> encrypt(
    List<int> plaintext,
    SensitiveKey key, {
    required List<int> associatedData,
  }) async {
    final secretKey = _secretKeyOf(key);
    final nonce = secureRandomBytes(nonceLength);
    final box = await _algorithm.encrypt(
      plaintext,
      secretKey: secretKey,
      nonce: nonce,
      aad: associatedData,
    );
    final cipherText = box.cipherText;
    final combined = Uint8List(cipherText.length + tagLength)
      ..setAll(0, cipherText)
      ..setAll(cipherText.length, box.mac.bytes);
    return EncryptedPayload(nonce: nonce, ciphertext: combined);
  }

  /// Valida a tag antes de devolver qualquer byte. Qualquer falha
  /// (tag, nonce, tamanho, dados associados) vira
  /// [DecryptionFailedException], sem detalhes.
  Future<Uint8List> decrypt(
    EncryptedPayload payload,
    SensitiveKey key, {
    required List<int> associatedData,
  }) async {
    final secretKey = _secretKeyOf(key);
    if (payload.nonce.length != nonceLength ||
        payload.ciphertext.length < tagLength) {
      throw const DecryptionFailedException();
    }
    final split = payload.ciphertext.length - tagLength;
    final box = SecretBox(
      payload.ciphertext.sublist(0, split),
      nonce: payload.nonce,
      mac: Mac(payload.ciphertext.sublist(split)),
    );
    try {
      final clear = await _algorithm.decrypt(
        box,
        secretKey: secretKey,
        aad: associatedData,
      );
      return Uint8List.fromList(clear);
    } on Object {
      throw const DecryptionFailedException();
    }
  }

  SecretKey _secretKeyOf(SensitiveKey key) {
    final bytes = key.bytes; // lança StateError se destruída
    if (bytes.length != keyLength) {
      throw ArgumentError('Chave AES-256 deve ter $keyLength bytes.');
    }
    return SecretKeyData(bytes);
  }
}
