import 'package:flutter/material.dart';
import 'package:vault_core/vault_core.dart';

import '../../app/app_scope.dart';
import '../../shared/widgets.dart';
import '../generator/generator_sheet.dart';

class ItemEditPage extends StatefulWidget {
  const ItemEditPage({super.key, required this.item, this.isNew = false});

  final VaultItem item;
  final bool isNew;

  @override
  State<ItemEditPage> createState() => _ItemEditPageState();
}

class _ItemEditPageState extends State<ItemEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.item.title);
  late final _username = TextEditingController(text: widget.item.username);
  late final _password = TextEditingController(text: widget.item.password);
  late final _url = TextEditingController(text: widget.item.url);
  late final _notes = TextEditingController(text: widget.item.notes);
  late final _category = TextEditingController(text: widget.item.category);
  late bool _favorite = widget.item.favorite;
  bool _busy = false;

  @override
  void dispose() {
    for (final controller in [_title, _username, _password, _url, _notes, _category]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _generate() async {
    final generated = await showGeneratorSheet(context, selectable: true);
    if (generated != null) _password.text = generated;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    final vault = AppScope.of(context).vault;
    final navigator = Navigator.of(context);
    try {
      await vault.save(widget.item.copyWith(
        title: _title.text,
        username: _username.text,
        password: _password.text,
        url: _url.text,
        notes: _notes.text,
        category: _category.text,
        favorite: _favorite,
      ));
      navigator.pop();
    } on ItemValidationException catch (error) {
      if (mounted) showMessage(context, error.issues.join(' '));
    } on VaultException catch (error) {
      if (mounted) showMessage(context, error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = AppScope.of(context).vault.categories;
    const gap = SizedBox(height: 16);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? 'Nova credencial' : 'Editar credencial'),
        actions: [
          TextButton(onPressed: _busy ? null : _save, child: const Text('Salvar')),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _title,
              autofocus: widget.isNew,
              decoration: const InputDecoration(labelText: 'Título *', border: OutlineInputBorder()),
              maxLength: VaultItemValidator.maxTitle,
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'O título é obrigatório.' : null,
            ),
            TextFormField(
              controller: _username,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                  labelText: 'Nome de usuário ou e-mail', border: OutlineInputBorder()),
            ),
            gap,
            PasswordField(
              controller: _password,
              label: 'Senha',
              suffix: IconButton(
                tooltip: 'Gerar senha',
                icon: const Icon(Icons.casino_outlined),
                onPressed: _generate,
              ),
            ),
            gap,
            TextFormField(
              controller: _url,
              autocorrect: false,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'URL', border: OutlineInputBorder()),
            ),
            gap,
            Autocomplete<String>(
              initialValue: TextEditingValue(text: _category.text),
              optionsBuilder: (value) => categories.where(
                  (c) => c.toLowerCase().contains(value.text.toLowerCase())),
              onSelected: (value) => _category.text = value,
              fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                return TextFormField(
                  controller: controller,
                  focusNode: focusNode,
                  onChanged: (value) => _category.text = value,
                  decoration: const InputDecoration(
                      labelText: 'Categoria', border: OutlineInputBorder()),
                );
              },
            ),
            gap,
            TextFormField(
              controller: _notes,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(labelText: 'Observações', border: OutlineInputBorder()),
            ),
            SwitchListTile(
              value: _favorite,
              onChanged: (value) => setState(() => _favorite = value),
              title: const Text('Favorito'),
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }
}
