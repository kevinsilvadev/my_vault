import 'package:meta/meta.dart';

import '../json_reader.dart';

/// Credencial do cofre em texto puro.
///
/// Só existe em memória enquanto o cofre está desbloqueado. Fora disso,
/// trafega e é persistida apenas cifrada (ver `VaultSession`).
@immutable
final class VaultItem {
  const VaultItem({
    required this.id,
    required this.title,
    this.username = '',
    this.password = '',
    this.url = '',
    this.notes = '',
    this.category = '',
    this.favorite = false,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Versão do esquema do conteúdo cifrado (dentro do ciphertext).
  static const int schemaVersion = 1;

  factory VaultItem.fromJson(Map<String, Object?> json) {
    final reader = JsonReader(json);
    final version = reader.integer('schemaVersion');
    if (version != schemaVersion) {
      throw const FormatException('Versão de esquema do item não suportada.');
    }
    return VaultItem(
      id: reader.string('id'),
      title: reader.string('title'),
      username: reader.string('username'),
      password: reader.string('password'),
      url: reader.string('url'),
      notes: reader.string('notes'),
      category: reader.string('category'),
      favorite: reader.boolean('favorite'),
      createdAt: reader.dateTime('createdAt'),
      updatedAt: reader.dateTime('updatedAt'),
    );
  }

  final String id;
  final String title;
  final String username;
  final String password;
  final String url;
  final String notes;

  /// Categoria livre; vazio significa "sem categoria".
  final String category;
  final bool favorite;
  final DateTime createdAt;
  final DateTime updatedAt;

  VaultItem copyWith({
    String? title,
    String? username,
    String? password,
    String? url,
    String? notes,
    String? category,
    bool? favorite,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      VaultItem(
        id: id,
        title: title ?? this.title,
        username: username ?? this.username,
        password: password ?? this.password,
        url: url ?? this.url,
        notes: notes ?? this.notes,
        category: category ?? this.category,
        favorite: favorite ?? this.favorite,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  /// Cópia com novo identificador (usado em "manter ambas" de conflitos).
  VaultItem duplicateAs({
    required String id,
    required DateTime now,
    String titleSuffix = '',
  }) =>
      VaultItem(
        id: id,
        title: '$title$titleSuffix',
        username: username,
        password: password,
        url: url,
        notes: notes,
        category: category,
        favorite: favorite,
        createdAt: now,
        updatedAt: now,
      );

  Map<String, Object?> toJson() => {
        'schemaVersion': schemaVersion,
        'id': id,
        'title': title,
        'username': username,
        'password': password,
        'url': url,
        'notes': notes,
        'category': category,
        'favorite': favorite,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  @override
  bool operator ==(Object other) =>
      other is VaultItem &&
      other.id == id &&
      other.title == title &&
      other.username == username &&
      other.password == password &&
      other.url == url &&
      other.notes == notes &&
      other.category == category &&
      other.favorite == favorite &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(id, title, username, password, url, notes,
      category, favorite, createdAt, updatedAt);

  /// Nunca inclui campos sensíveis, para que o item possa aparecer em logs
  /// ou mensagens de erro sem vazamento.
  @override
  String toString() => 'VaultItem(id: $id, <campos omitidos>)';
}

/// Regras de validação de itens.
abstract final class VaultItemValidator {
  static const int maxTitle = 200;
  static const int maxUsername = 500;
  static const int maxPassword = 1000;
  static const int maxUrl = 2048;
  static const int maxNotes = 10000;
  static const int maxCategory = 100;

  static List<String> validate(VaultItem item) {
    final issues = <String>[];
    if (item.title.trim().isEmpty) issues.add('O título é obrigatório.');
    void checkLength(String value, int max, String field) {
      if (value.length > max) {
        issues.add('$field excede $max caracteres.');
      }
    }

    checkLength(item.title, maxTitle, 'Título');
    checkLength(item.username, maxUsername, 'Usuário');
    checkLength(item.password, maxPassword, 'Senha');
    checkLength(item.url, maxUrl, 'URL');
    checkLength(item.notes, maxNotes, 'Observações');
    checkLength(item.category, maxCategory, 'Categoria');
    return issues;
  }
}
