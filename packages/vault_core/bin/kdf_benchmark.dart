// Mede o tempo do Argon2id para calibrar KdfParams.recommended.
//
// Uso: dart run bin/kdf_benchmark.dart
// Rode no dispositivo mais lento suportado; mire em ~0,5–1 s por derivação.
// Para Android, execute o equivalente via teste de integração no aparelho.

import 'dart:io';

import 'package:vault_core/vault_core.dart';

Future<void> main() async {
  const candidates = [
    KdfParams.minimum,
    KdfParams(memoryKiB: 32 * 1024, iterations: 3, parallelism: 4),
    KdfParams.recommended,
    KdfParams(memoryKiB: 128 * 1024, iterations: 3, parallelism: 4),
  ];
  const kdf = KeyDerivation(runInIsolate: false);
  final salt = List<int>.filled(KeyDerivation.saltLength, 7);

  stdout.writeln('Argon2id — ${Platform.operatingSystem}');
  for (final params in candidates) {
    final watch = Stopwatch()..start();
    final key = await kdf.deriveKey(
      masterPassword: 'benchmark-password',
      salt: salt,
      params: params,
    );
    watch.stop();
    key.destroy();
    stdout.writeln('${params.toString().padRight(48)} ${watch.elapsedMilliseconds} ms');
  }
}
