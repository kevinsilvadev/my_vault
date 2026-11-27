import 'dart:math';
import 'dart:typed_data';

/// Gerador criptograficamente seguro fornecido pelo sistema operacional.
final Random _secureRandom = Random.secure();

/// Retorna [length] bytes aleatórios de um CSPRNG.
Uint8List secureRandomBytes(int length) {
  if (length <= 0) {
    throw ArgumentError.value(length, 'length', 'deve ser positivo');
  }
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = _secureRandom.nextInt(256);
  }
  return bytes;
}

/// Sobrescreve [bytes] com zeros (melhor esforço).
///
/// O Dart possui coletor de lixo e pode ter copiado o buffer; isto reduz, mas
/// não elimina, a permanência de material sensível em memória.
void wipeBytes(Uint8List bytes) {
  bytes.fillRange(0, bytes.length, 0);
}

/// Comparação em tempo constante em relação ao conteúdo.
bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
