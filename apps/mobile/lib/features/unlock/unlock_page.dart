import 'package:flutter/material.dart';
import 'package:vault_core/vault_core.dart';

import '../../app/app_scope.dart';
import '../../shared/widgets.dart';

class UnlockPage extends StatefulWidget {
  const UnlockPage({super.key});

  @override
  State<UnlockPage> createState() => _UnlockPageState();
}

class _UnlockPageState extends State<UnlockPage> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    if (_password.text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.of(context).vault.unlock(_password.text);
    } on VaultException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      _password.clear();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Icon(Icons.lock, size: 56, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text('Cofre bloqueado', textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 24),
              PasswordField(
                controller: _password,
                label: 'Senha mestre',
                autofocus: true,
                onSubmitted: (_) => _unlock(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _unlock,
                child: _busy
                    ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Desbloquear'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
