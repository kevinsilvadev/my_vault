/// Política mínima de senha mestre.
///
/// Segue a orientação do NIST SP 800-63B: privilegia comprimento e não impõe
/// regras de composição. A força real vem do comprimento + Argon2id.
abstract final class MasterPasswordPolicy {
  static const int minLength = 12;
  static const int maxLength = 1024;

  static List<String> validate(String password) {
    final issues = <String>[];
    final length = password.runes.length;
    if (password.trim().isEmpty) {
      issues.add('A senha mestre não pode ficar em branco.');
    } else if (length < minLength) {
      issues.add('Use pelo menos $minLength caracteres.');
    }
    if (length > maxLength) {
      issues.add('Use no máximo $maxLength caracteres.');
    }
    return issues;
  }
}
