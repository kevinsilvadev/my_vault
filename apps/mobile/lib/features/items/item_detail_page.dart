import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vault_core/vault_core.dart';

import '../../app/app_scope.dart';
import '../../shared/sensitive_clipboard.dart';
import '../../shared/widgets.dart';
import 'item_edit_page.dart';

class ItemDetailPage extends StatefulWidget {
  const ItemDetailPage({super.key, required this.itemId});

  final String itemId;

  @override
  State<ItemDetailPage> createState() => _ItemDetailPageState();
}

class _ItemDetailPageState extends State<ItemDetailPage> {
  bool _showPassword = false;

  Future<void> _copy(String label, String value) async {
    await SensitiveClipboard.copy(value);
    if (mounted) showMessage(context, '$label copiado. Será apagado da área de transferência em 30 s.');
  }

  Future<void> _delete(VaultItem item) async {
    final vault = AppScope.of(context).vault;
    final navigator = Navigator.of(context);
    final confirmed = await confirmAction(
      context,
      title: 'Excluir credencial?',
      message: '"${item.title}" será excluída de todos os dispositivos sincronizados.',
      confirmLabel: 'Excluir',
      destructive: true,
    );
    if (!confirmed) return;
    await vault.delete(item.id);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final vault = AppScope.of(context).vault;
    return ListenableBuilder(
      listenable: vault,
      builder: (context, _) {
        final item = vault.items.where((i) => i.id == widget.itemId).firstOrNull;
        if (item == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Credencial não encontrada.')),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(item.title),
            actions: [
              IconButton(
                tooltip: 'Editar',
                icon: const Icon(Icons.edit),
                onPressed: () => unawaited(Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => ItemEditPage(item: item)),
                )),
              ),
              IconButton(
                tooltip: 'Excluir',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(item),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              if (item.username.isNotEmpty)
                _Field(
                  label: 'Usuário',
                  value: item.username,
                  onCopy: () => _copy('Usuário', item.username),
                ),
              if (item.password.isNotEmpty)
                _Field(
                  label: 'Senha',
                  value: _showPassword ? item.password : '•' * 12,
                  monospace: _showPassword,
                  onCopy: () => _copy('Senha', item.password),
                  extra: IconButton(
                    tooltip: _showPassword ? 'Ocultar' : 'Mostrar',
                    icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _showPassword = !_showPassword),
                  ),
                ),
              if (item.url.isNotEmpty)
                _Field(label: 'URL', value: item.url, onCopy: () => _copy('URL', item.url)),
              if (item.category.isNotEmpty) _Field(label: 'Categoria', value: item.category),
              if (item.notes.isNotEmpty) _Field(label: 'Observações', value: item.notes),
              ListTile(
                leading: Icon(item.favorite ? Icons.star : Icons.star_border),
                title: Text(item.favorite ? 'Favorito' : 'Não é favorito'),
              ),
              ListTile(
                dense: true,
                title: Text('Criado em ${_formatDate(item.createdAt)}'),
                subtitle: Text('Atualizado em ${_formatDate(item.updatedAt)}'),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _formatDate(DateTime date) {
    final local = date.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.value,
    this.onCopy,
    this.extra,
    this.monospace = false,
  });

  final String label;
  final String value;
  final VoidCallback? onCopy;
  final Widget? extra;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label, style: Theme.of(context).textTheme.labelMedium),
      subtitle: SelectableText(
        value,
        style: monospace ? const TextStyle(fontFamily: 'monospace') : null,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (extra != null) extra!,
          if (onCopy != null)
            IconButton(tooltip: 'Copiar', icon: const Icon(Icons.copy), onPressed: onCopy),
        ],
      ),
    );
  }
}
