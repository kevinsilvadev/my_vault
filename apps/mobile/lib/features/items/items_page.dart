import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vault_core/vault_core.dart';

import '../../app/app_scope.dart';
import '../../shared/sensitive_clipboard.dart';
import '../../shared/widgets.dart';
import '../account/account_page.dart';
import '../conflicts/conflicts_page.dart';
import '../generator/generator_sheet.dart';
import '../settings/settings_page.dart';
import 'item_detail_page.dart';
import 'item_edit_page.dart';

/// Lista do cofre com busca, filtro por categoria e favoritos.
class ItemsPage extends StatefulWidget {
  const ItemsPage({super.key});

  @override
  State<ItemsPage> createState() => _ItemsPageState();
}

class _ItemsPageState extends State<ItemsPage> {
  final _search = TextEditingController();
  ItemFilter _filter = const ItemFilter();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _open(Widget page) {
    unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page)));
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final vault = scope.vault;
    final account = scope.account;

    return ListenableBuilder(
      listenable: Listenable.merge([vault, account]),
      builder: (context, _) {
        final items = _filter.apply(vault.items);
        final categories = vault.categories;
        return Scaffold(
          appBar: AppBar(
            title: const Text('MyVault'),
            actions: [
              if (account.isSignedIn)
                IconButton(
                  tooltip: account.lastError ?? 'Sincronizar',
                  onPressed: account.isSyncing ? null : () => unawaited(account.syncNow()),
                  icon: account.isSyncing
                      ? const SizedBox.square(
                          dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(account.lastError == null ? Icons.sync : Icons.sync_problem),
                ),
              if (vault.conflicts.isNotEmpty)
                IconButton(
                  tooltip: 'Conflitos de sincronização',
                  onPressed: () => _open(const ConflictsPage()),
                  icon: Badge(
                    label: Text('${vault.conflicts.length}'),
                    child: const Icon(Icons.call_split),
                  ),
                ),
              IconButton(
                tooltip: 'Bloquear',
                onPressed: vault.lock,
                icon: const Icon(Icons.lock),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'generator':
                      unawaited(showGeneratorSheet(context));
                    case 'account':
                      _open(const AccountPage());
                    case 'settings':
                      _open(const SettingsPage());
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'generator', child: Text('Gerador de senhas')),
                  PopupMenuItem(value: 'account', child: Text('Conta e sincronização')),
                  PopupMenuItem(value: 'settings', child: Text('Configurações')),
                ],
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            tooltip: 'Nova credencial',
            onPressed: () => _open(ItemEditPage(item: vault.draftItem(), isNew: true)),
            child: const Icon(Icons.add),
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: TextField(
                  controller: _search,
                  autocorrect: false,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Buscar por título, usuário ou URL',
                    border: const OutlineInputBorder(),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _search.clear();
                              setState(() => _filter = _filter.copyWith(query: ''));
                            },
                          ),
                  ),
                  onChanged: (value) => setState(() => _filter = _filter.copyWith(query: value)),
                ),
              ),
              SizedBox(
                height: 56,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  children: [
                    _chip('Todos', _filter.category == null && !_filter.favoritesOnly, () {
                      setState(() => _filter = _filter.copyWith(category: () => null, favoritesOnly: false));
                    }),
                    _chip('Favoritos', _filter.favoritesOnly, () {
                      setState(() => _filter = _filter.copyWith(favoritesOnly: !_filter.favoritesOnly));
                    }),
                    for (final category in categories)
                      _chip(category, _filter.category == category, () {
                        setState(() => _filter = _filter.copyWith(
                              category: () => _filter.category == category ? null : category,
                            ));
                      }),
                  ],
                ),
              ),
              if (vault.undecryptableCount > 0)
                Container(
                  width: double.infinity,
                  color: Theme.of(context).colorScheme.errorContainer,
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '${vault.undecryptableCount} registro(s) não puderam ser lidos e foram '
                    'ignorados. Podem estar corrompidos ou adulterados.',
                    style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
                  ),
                ),
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: Text(vault.items.isEmpty
                            ? 'Nenhuma credencial ainda. Toque em + para adicionar.'
                            : 'Nada encontrado.'),
                      )
                    : RefreshIndicator(
                        onRefresh: () async {
                          await account.syncNow();
                          await vault.reload();
                        },
                        child: ListView.builder(
                          itemCount: items.length,
                          itemBuilder: (context, index) => _ItemTile(
                            item: items[index],
                            onTap: () => _open(ItemDetailPage(itemId: items[index].id)),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: FilterChip(label: Text(label), selected: selected, onSelected: (_) => onTap()),
      );
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, required this.onTap});

  final VaultItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final initial = item.title.isEmpty ? '?' : item.title.characters.first.toUpperCase();
    return ListTile(
      leading: CircleAvatar(child: Text(initial)),
      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: item.username.isEmpty
          ? null
          : Text(item.username, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (item.favorite) const Icon(Icons.star, size: 18),
          if (item.password.isNotEmpty)
            IconButton(
              tooltip: 'Copiar senha',
              icon: const Icon(Icons.copy),
              onPressed: () async {
                await SensitiveClipboard.copy(item.password);
                if (context.mounted) {
                  showMessage(context, 'Senha copiada. Será apagada da área de transferência em 30 s.');
                }
              },
            ),
        ],
      ),
      onTap: onTap,
    );
  }
}
