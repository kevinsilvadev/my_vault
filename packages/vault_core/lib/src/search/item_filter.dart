import 'package:meta/meta.dart';

import '../models/vault_item.dart';

/// Filtro de itens: busca por título, usuário ou URL; categoria; favoritos.
///
/// Opera sobre itens já descriptografados em memória — o servidor e o banco
/// local nunca veem os termos de busca.
@immutable
final class ItemFilter {
  const ItemFilter({
    this.query = '',
    this.category,
    this.favoritesOnly = false,
  });

  final String query;

  /// `null` = todas as categorias.
  final String? category;
  final bool favoritesOnly;

  bool matches(VaultItem item) {
    if (favoritesOnly && !item.favorite) return false;
    if (category != null && item.category != category) return false;
    final term = query.trim().toLowerCase();
    if (term.isEmpty) return true;
    return item.title.toLowerCase().contains(term) ||
        item.username.toLowerCase().contains(term) ||
        item.url.toLowerCase().contains(term);
  }

  /// Aplica o filtro e ordena: favoritos primeiro, depois por título.
  List<VaultItem> apply(Iterable<VaultItem> items) {
    final result = items.where(matches).toList()
      ..sort((a, b) {
        if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });
    return result;
  }

  ItemFilter copyWith({
    String? query,
    String? Function()? category,
    bool? favoritesOnly,
  }) =>
      ItemFilter(
        query: query ?? this.query,
        category: category != null ? category() : this.category,
        favoritesOnly: favoritesOnly ?? this.favoritesOnly,
      );
}

/// Categorias distintas e não vazias, em ordem alfabética.
List<String> categoriesOf(Iterable<VaultItem> items) {
  final set = <String>{
    for (final item in items)
      if (item.category.trim().isNotEmpty) item.category.trim(),
  };
  return set.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
}
