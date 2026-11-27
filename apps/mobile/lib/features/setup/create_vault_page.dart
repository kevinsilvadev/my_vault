import 'package:flutter/material.dart';
import 'package:vault_core/vault_core.dart';

import '../../app/app_scope.dart';
import '../../shared/widgets.dart';

class CreateVaultPage extends StatefulWidget {
  const CreateVaultPage({super.key});

  @override
  State<CreateVaultPage> createState() => _CreateVaultPageState();
}

class _CreateVaultPageState extends State<CreateVaultPage> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _acknowledged = false;
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_acknowledged) {
      showMessage(context, 'Confirme que entendeu que a senha mestre não pode ser recuperada.');
      return;
    }
    setState(() => _busy = true);
    final vault = AppScope.of(context).vault;
    final navigator = Navigator.of(context);
    try {
      await vault.createVault(_password.text);
      _password.clear();
      _confirmation.clear();
      navigator.popUntil((route) => route.isFirst);
    } on VaultException catch (error) {
      if (mounted) showMessage(context, error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Novo cofre')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Text(
                  'Escolha uma senha mestre longa — uma frase com várias palavras é fácil '
                  'de lembrar e difícil de adivinhar. Ela nunca sai deste dispositivo.',
                ),
                const SizedBox(height: 24),
                PasswordField(
                  controller: _password,
                  label: 'Senha mestre',
                  autofocus: true,
                  validator: (value) {
                    final issues = MasterPasswordPolicy.validate(value ?? '');
                    return issues.isEmpty ? null : issues.join(' ');
                  },
                ),
                const SizedBox(height: 16),
                PasswordField(
                  controller: _confirmation,
                  label: 'Confirme a senha mestre',
                  validator: (value) => value == _password.text ? null : 'As senhas não coincidem.',
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  value: _acknowledged,
                  onChanged: (value) => setState(() => _acknowledged = value ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Entendo que, se eu esquecer a senha mestre, o cofre não poderá ser '
                    'recuperado por ninguém — nem pelo servidor.',
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Criar cofre'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
