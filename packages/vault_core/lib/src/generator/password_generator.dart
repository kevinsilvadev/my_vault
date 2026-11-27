import 'dart:math';

import 'package:meta/meta.dart';

/// Configuração do gerador de senhas.
@immutable
final class PasswordGeneratorOptions {
  const PasswordGeneratorOptions({
    this.length = 20,
    this.lowercase = true,
    this.uppercase = true,
    this.digits = true,
    this.symbols = true,
    this.excludeAmbiguous = false,
  });

  static const int minLength = 8;
  static const int maxLength = 128;

  static const String _lower = 'abcdefghijklmnopqrstuvwxyz';
  static const String _upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const String _digits = '0123456789';
  static const String _symbols = r'!@#$%^&*()-_=+[]{};:,.?/~';
  static const String _ambiguous = 'Il1O0o';

  final int length;
  final bool lowercase;
  final bool uppercase;
  final bool digits;
  final bool symbols;

  /// Remove caracteres facilmente confundíveis (I, l, 1, O, 0, o).
  final bool excludeAmbiguous;

  /// Conjuntos de caracteres habilitados, já sem ambíguos se aplicável.
  List<String> get characterSets {
    String clean(String set) => excludeAmbiguous
        ? set.split('').where((c) => !_ambiguous.contains(c)).join()
        : set;
    return [
      if (lowercase) clean(_lower),
      if (uppercase) clean(_upper),
      if (digits) clean(_digits),
      if (symbols) _symbols,
    ];
  }

  /// Entropia aproximada em bits, para exibição.
  double get entropyBits {
    final pool = characterSets.fold<int>(0, (sum, set) => sum + set.length);
    if (pool == 0) return 0;
    return length * (log(pool) / ln2);
  }

  List<String> validate() {
    final issues = <String>[];
    if (length < minLength || length > maxLength) {
      issues.add('O comprimento deve estar entre $minLength e $maxLength.');
    }
    final sets = characterSets;
    if (sets.isEmpty) {
      issues.add('Selecione ao menos um conjunto de caracteres.');
    } else if (length < sets.length) {
      issues.add('Comprimento insuficiente para os conjuntos selecionados.');
    }
    return issues;
  }

  PasswordGeneratorOptions copyWith({
    int? length,
    bool? lowercase,
    bool? uppercase,
    bool? digits,
    bool? symbols,
    bool? excludeAmbiguous,
  }) =>
      PasswordGeneratorOptions(
        length: length ?? this.length,
        lowercase: lowercase ?? this.lowercase,
        uppercase: uppercase ?? this.uppercase,
        digits: digits ?? this.digits,
        symbols: symbols ?? this.symbols,
        excludeAmbiguous: excludeAmbiguous ?? this.excludeAmbiguous,
      );
}

/// Gerador de senhas baseado em CSPRNG.
///
/// Garante ao menos um caractere de cada conjunto selecionado e embaralha o
/// resultado com Fisher–Yates. `Random.nextInt` é uniforme (sem viés de
/// módulo).
final class PasswordGenerator {
  PasswordGenerator({Random? random}) : _random = random ?? Random.secure();

  final Random _random;

  String generate([
    PasswordGeneratorOptions options = const PasswordGeneratorOptions(),
  ]) {
    final issues = options.validate();
    if (issues.isNotEmpty) {
      throw ArgumentError(issues.join(' '));
    }
    final sets = options.characterSets;
    final pool = sets.join();
    final chars = <String>[
      for (final set in sets) set[_random.nextInt(set.length)],
    ];
    while (chars.length < options.length) {
      chars.add(pool[_random.nextInt(pool.length)]);
    }
    for (var i = chars.length - 1; i > 0; i--) {
      final j = _random.nextInt(i + 1);
      final tmp = chars[i];
      chars[i] = chars[j];
      chars[j] = tmp;
    }
    return chars.join();
  }
}
