/// Erro retornado pela API ou pela camada de rede.
///
/// A mensagem é segura para exibição: vem do servidor (que não inclui dados
/// sensíveis) ou é uma mensagem genérica local.
final class ApiException implements Exception {
  const ApiException({required this.statusCode, required this.code, required this.message});

  const ApiException.network()
      : statusCode = 0,
        code = 'NETWORK_ERROR',
        message = 'Não foi possível conectar ao servidor.';

  /// 0 quando não houve resposta HTTP.
  final int statusCode;
  final String code;
  final String message;

  bool get isUnauthorized => statusCode == 401;
  bool get isNetworkError => statusCode == 0;

  @override
  String toString() => 'ApiException($statusCode, $code)';
}

/// A sessão expirou ou foi revogada; é preciso entrar novamente.
final class SessionExpiredException implements Exception {
  const SessionExpiredException();

  String get message => 'Sua sessão expirou. Entre novamente na conta.';
}
