import 'package:flutter/material.dart';
import 'package:vault_core/vault_core.dart';

import '../../shared/sensitive_clipboard.dart';
import '../../shared/widgets.dart';

/// Abre o gerador de senhas. Com [selectable], retorna a senha escolhida.
Future<String?> showGeneratorSheet(BuildContext context, {bool selectable = false}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _GeneratorSheet(selectable: selectable),
  );
}

class _GeneratorSheet extends StatefulWidget {
  const _GeneratorSheet({required this.selectable});

  final bool selectable;

  @override
  State<_GeneratorSheet> createState() => _GeneratorSheetState();
}

class _GeneratorSheetState extends State<_GeneratorSheet> {
  final _generator = PasswordGenerator();
  PasswordGeneratorOptions _options = const PasswordGeneratorOptions();
  String _value = '';

  @override
  void initState() {
    super.initState();
    _value = _generator.generate(_options);
  }

  void _update(PasswordGeneratorOptions options) {
    // Impede desmarcar todos os conjuntos.
    if (options.characterSets.isEmpty) return;
    setState(() => _options = options);
    _regenerate();
  }

  void _regenerate() {
    final issues = _options.validate();
    setState(() => _value = issues.isEmpty ? _generator.generate(_options) : '');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Gerador de senhas', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  _value,
                  style: theme.textTheme.titleMedium?.copyWith(fontFamily: 'monospace'),
                ),
              ),
            ),
            Text('Entropia estimada: ${_options.entropyBits.round()} bits',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('Comprimento: ${_options.length}'),
                Expanded(
                  child: Slider(
                    value: _options.length.toDouble(),
                    min: PasswordGeneratorOptions.minLength.toDouble(),
                    max: 64,
                    divisions: 64 - PasswordGeneratorOptions.minLength,
                    onChanged: (v) => _update(_options.copyWith(length: v.round())),
                  ),
                ),
              ],
            ),
            _toggle('Minúsculas (a-z)', _options.lowercase,
                (v) => _update(_options.copyWith(lowercase: v))),
            _toggle('Maiúsculas (A-Z)', _options.uppercase,
                (v) => _update(_options.copyWith(uppercase: v))),
            _toggle('Números (0-9)', _options.digits, (v) => _update(_options.copyWith(digits: v))),
            _toggle('Símbolos (!@#…)', _options.symbols, (v) => _update(_options.copyWith(symbols: v))),
            _toggle('Evitar caracteres ambíguos (I l 1 O 0)', _options.excludeAmbiguous,
                (v) => _update(_options.copyWith(excludeAmbiguous: v))),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _regenerate,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Gerar outra'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: widget.selectable
                      ? FilledButton(
                          onPressed: _value.isEmpty ? null : () => Navigator.pop(context, _value),
                          child: const Text('Usar esta senha'),
                        )
                      : FilledButton.icon(
                          onPressed: _value.isEmpty
                              ? null
                              : () async {
                                  await SensitiveClipboard.copy(_value);
                                  if (context.mounted) showMessage(context, 'Senha copiada.');
                                },
                          icon: const Icon(Icons.copy),
                          label: const Text('Copiar'),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) => SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        value: value,
        onChanged: onChanged,
      );
}
