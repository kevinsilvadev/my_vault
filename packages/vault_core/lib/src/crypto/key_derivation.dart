import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../exceptions.dart';
import 'bytes.dart';
import 'kdf_params.dart';
import 'sensitive_key.dart';

/// Deriva a chave de proteção (KEK) a partir da senha mestre com Argon2id.
final class KeyDerivation {
  const KeyDerivation({
    this.floor = KdfParams.minimum,
    this.ceiling = KdfParams.maximum,
    this.runInIsolate = true,
  });

  static const int saltLength = 16;
  static const int keyLength = 32;

  /// Parâmetros abaixo deste piso são rejeitados.
  final KdfParams floor;

  /// Parâmetros acima deste teto são rejeitados.
  final KdfParams ceiling;

  /// Executa o Argon2id em outro isolate para não travar a interface.
  final bool runInIsolate;

  Future<SensitiveKey> deriveKey({
    required String masterPassword,
    required List<int> salt,
    required KdfParams params,
  }) async {
    if (!params.isWithin(floor: floor, ceiling: ceiling)) {
      throw const InsecureKdfParametersException();
    }
    if (salt.length < saltLength) {
      throw const UnsupportedFormatException('Salt inválido.');
    }

    final request = _Argon2Request(
      password: Uint8List.fromList(utf8.encode(masterPassword)),
      salt: Uint8List.fromList(salt),
      params: params,
    );
    try {
      final bytes = runInIsolate
          ? await Isolate.run(() => _deriveArgon2id(request))
          : await _deriveArgon2id(request);
      return SensitiveKey(bytes);
    } finally {
      wipeBytes(request.password);
    }
  }
}

final class _Argon2Request {
  const _Argon2Request({
    required this.password,
    required this.salt,
    required this.params,
  });

  final Uint8List password;
  final Uint8List salt;
  final KdfParams params;
}

Future<Uint8List> _deriveArgon2id(_Argon2Request request) async {
  final algorithm = Argon2id(
    parallelism: request.params.parallelism,
    memory: request.params.memoryKiB,
    iterations: request.params.iterations,
    hashLength: KeyDerivation.keyLength,
  );
  final key = await algorithm.deriveKey(
    secretKey: SecretKeyData(request.password),
    nonce: request.salt,
  );
  return Uint8List.fromList(await key.extractBytes());
}
