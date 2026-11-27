import 'package:meta/meta.dart';

/// Parâmetros do Argon2id.
///
/// Os valores são gravados no envelope da chave do cofre, permitindo que
/// cada cofre evolua seus parâmetros (ver docs/security.md, "Política de
/// atualização de parâmetros").
@immutable
final class KdfParams {
  const KdfParams({
    required this.memoryKiB,
    required this.iterations,
    required this.parallelism,
  });

  static const String algorithm = 'argon2id';

  /// Padrão para novos cofres: m=64 MiB, t=3, p=4.
  ///
  /// Deve ser recalibrado com `dart run bin/kdf_benchmark.dart` nos
  /// dispositivos-alvo; o objetivo é ~0,5–1 s no aparelho mais lento.
  static const KdfParams recommended =
      KdfParams(memoryKiB: 64 * 1024, iterations: 3, parallelism: 4);

  /// Piso aceito: recomendação mínima da OWASP (m=19 MiB, t=2, p=1).
  static const KdfParams minimum =
      KdfParams(memoryKiB: 19 * 1024, iterations: 2, parallelism: 1);

  /// Teto aceito: impede negação de serviço por envelope adulterado com
  /// custo absurdo.
  static const KdfParams maximum =
      KdfParams(memoryKiB: 1024 * 1024, iterations: 20, parallelism: 16);

  final int memoryKiB;
  final int iterations;
  final int parallelism;

  /// Verifica limites e a restrição do Argon2 (memória >= 8 × paralelismo).
  bool isWithin({required KdfParams floor, required KdfParams ceiling}) =>
      memoryKiB >= floor.memoryKiB &&
      iterations >= floor.iterations &&
      parallelism >= floor.parallelism &&
      memoryKiB <= ceiling.memoryKiB &&
      iterations <= ceiling.iterations &&
      parallelism <= ceiling.parallelism &&
      memoryKiB >= 8 * parallelism;

  @override
  bool operator ==(Object other) =>
      other is KdfParams &&
      other.memoryKiB == memoryKiB &&
      other.iterations == iterations &&
      other.parallelism == parallelism;

  @override
  int get hashCode => Object.hash(memoryKiB, iterations, parallelism);

  @override
  String toString() =>
      'KdfParams(argon2id, m=${memoryKiB}KiB, t=$iterations, p=$parallelism)';
}
