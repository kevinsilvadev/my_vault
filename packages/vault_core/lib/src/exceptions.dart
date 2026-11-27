/// Exceções do domínio do cofre.
///
/// As mensagens são genéricas de propósito: nunca incluem senhas, chaves,
/// conteúdo do cofre ou detalhes que ajudem um atacante (por exemplo, qual
/// etapa da validação criptográfica falhou).
sealed class VaultException implements Exception {
  const VaultException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// A senha mestre não abriu o envelope da chave do cofre.
///
/// É lançada antes de qualquer registro ser lido, portanto não revela se um
/// registro específico existe.
final class InvalidMasterPasswordException extends VaultException {
  const InvalidMasterPasswordException() : super('Senha mestre incorreta.');
}

/// Falha de autenticação ou de formato ao descriptografar um conteúdo
/// (ciphertext, tag, nonce ou dados associados adulterados).
final class DecryptionFailedException extends VaultException {
  const DecryptionFailedException()
      : super('Não foi possível descriptografar o conteúdo.');
}

final class UnsupportedFormatException extends VaultException {
  const UnsupportedFormatException(
      [super.message = 'Formato criptográfico não suportado.']);
}

final class InsecureKdfParametersException extends VaultException {
  const InsecureKdfParametersException()
      : super('Parâmetros de derivação de chave fora dos limites aceitos.');
}

/// O envelope abriu, mas a chave obtida difere da registrada neste
/// dispositivo — possível substituição do envelope por terceiros.
final class VaultKeyMismatchException extends VaultException {
  const VaultKeyMismatchException()
      : super('A chave do cofre não corresponde à registrada neste dispositivo.');
}

final class VaultLockedException extends VaultException {
  const VaultLockedException() : super('O cofre está bloqueado.');
}

final class VaultNotFoundException extends VaultException {
  const VaultNotFoundException()
      : super('Nenhum cofre configurado neste dispositivo.');
}

final class VaultAlreadyExistsException extends VaultException {
  const VaultAlreadyExistsException()
      : super('Já existe um cofre neste dispositivo.');
}

final class WeakMasterPasswordException extends VaultException {
  const WeakMasterPasswordException(this.issues)
      : super('A senha mestre não atende aos requisitos mínimos.');

  final List<String> issues;
}

final class ItemValidationException extends VaultException {
  const ItemValidationException(this.issues) : super('Dados do item inválidos.');

  final List<String> issues;
}

final class ConflictNotFoundException extends VaultException {
  const ConflictNotFoundException() : super('Conflito não encontrado.');
}
