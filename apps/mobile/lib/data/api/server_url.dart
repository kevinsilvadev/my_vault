/// Validação do endereço do servidor.
///
/// HTTPS é obrigatório. HTTP só é aceito para endereços de desenvolvimento
/// local (incluindo 10.0.2.2, o host visto pelo emulador Android).
abstract final class ServerUrl {
  static const Set<String> _localHosts = {'localhost', '127.0.0.1', '::1', '10.0.2.2'};

  /// Normaliza e valida. Lança [FormatException] com mensagem amigável.
  static Uri parse(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const FormatException('Informe um endereço completo, ex.: https://cofre.exemplo.com');
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'http' && !_localHosts.contains(uri.host.toLowerCase())) {
      throw const FormatException('Use HTTPS. HTTP só é permitido para servidores locais.');
    }
    if (scheme != 'https' && scheme != 'http') {
      throw const FormatException('Endereço deve começar com https://');
    }
    if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      throw const FormatException('O endereço não deve conter usuário, parâmetros ou fragmentos.');
    }
    final path = uri.path.endsWith('/') ? uri.path.substring(0, uri.path.length - 1) : uri.path;
    return uri.replace(scheme: scheme, path: path);
  }
}
