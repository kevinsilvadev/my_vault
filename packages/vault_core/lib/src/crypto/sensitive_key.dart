import 'dart:typed_data';

import 'bytes.dart';

/// Material de chave que pode ser destruído explicitamente.
///
/// Assume a posse do buffer recebido: quem cria não deve reutilizá-lo.
final class SensitiveKey {
  SensitiveKey(Uint8List bytes) : _bytes = bytes;

  Uint8List? _bytes;

  bool get isDestroyed => _bytes == null;

  /// Acesso ao buffer interno. Lança [StateError] após [destroy].
  Uint8List get bytes {
    final value = _bytes;
    if (value == null) {
      throw StateError('Chave já destruída.');
    }
    return value;
  }

  /// Zera e descarta a chave. Idempotente.
  void destroy() {
    final value = _bytes;
    if (value != null) {
      wipeBytes(value);
      _bytes = null;
    }
  }

  @override
  String toString() => 'SensitiveKey(<redacted>)';
}
