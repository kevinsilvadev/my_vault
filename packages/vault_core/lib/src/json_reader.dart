import 'dart:convert';
import 'dart:typed_data';

/// Leitura tipada e estrita de mapas JSON.
///
/// Toda inconsistência vira [FormatException] com o nome do campo — nunca com
/// o valor, que pode ser sensível.
extension type const JsonReader(Map<String, Object?> json) {
  String string(String key) {
    final value = json[key];
    if (value is String) return value;
    throw FormatException('Campo "$key" ausente ou não é texto.');
  }

  String? nullableString(String key) {
    final value = json[key];
    if (value == null || value is String) return value as String?;
    throw FormatException('Campo "$key" não é texto.');
  }

  int integer(String key) {
    final value = json[key];
    if (value is int) return value;
    throw FormatException('Campo "$key" ausente ou não é inteiro.');
  }

  bool boolean(String key) {
    final value = json[key];
    if (value is bool) return value;
    throw FormatException('Campo "$key" ausente ou não é booleano.');
  }

  DateTime dateTime(String key) {
    final parsed = DateTime.tryParse(string(key));
    if (parsed == null) {
      throw FormatException('Campo "$key" não é uma data ISO-8601.');
    }
    return parsed.toUtc();
  }

  Uint8List base64Bytes(String key) {
    try {
      return base64Decode(string(key));
    } on FormatException {
      throw FormatException('Campo "$key" não é base64 válido.');
    }
  }

  JsonReader object(String key) {
    final value = json[key];
    if (value is Map<String, Object?>) return JsonReader(value);
    throw FormatException('Campo "$key" ausente ou não é objeto.');
  }

  List<JsonReader> objectList(String key) {
    final value = json[key];
    if (value is! List<Object?>) {
      throw FormatException('Campo "$key" ausente ou não é lista.');
    }
    return [
      for (final entry in value)
        if (entry is Map<String, Object?>)
          JsonReader(entry)
        else
          throw FormatException('Lista "$key" contém item inválido.'),
    ];
  }
}

/// Decodifica um objeto JSON de nível superior.
JsonReader decodeJsonObject(String source) {
  final decoded = jsonDecode(source);
  if (decoded is Map<String, Object?>) return JsonReader(decoded);
  throw const FormatException('JSON de nível superior não é objeto.');
}
