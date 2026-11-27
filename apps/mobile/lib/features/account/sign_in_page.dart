import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:vault_core/vault_core.dart';

import '../../app/app_scope.dart';
import '../../data/api/api_exception.dart';
import '../../shared/widgets.dart';
import 'account_controller.dart';

/// Entrar ou criar conta de sincronização.
///
/// A senha da CONTA autentica o dispositivo no servidor. Ela é diferente da
/// senha mestre, que nunca sai do dispositivo.
class SignInPage extends StatefulWidget {
  const SignInPage({super.key, this.allowRegistration = true});

  final bool allowRegistration;

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _formKey = GlobalKey<FormState>();
  final _server = TextEditingController(text: 'https://');
  final _email = TextEditingController();
  final _password = TextEditingController();
  late final _deviceName = TextEditingController(text: _defaultDeviceName());
  bool _register = false;
  bool _busy = false;

  static String _defaultDeviceName() {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isWindows) return 'Windows — ${Platform.localHostname}';
    return Platform.localHostname;
  }

  @override
  void dispose() {
    for (final c in [_server, _email, _password, _deviceName]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    final scope = AppScope.of(context);
    final navigator = Navigator.of(context);
    try {
      if (_register) {
        await scope.account.register(
          serverUrl: _server.text,
          email: _email.text,
          password: _password.text,
          deviceName: _deviceName.text.trim(),
        );
      } else {
        await scope.account.login(
          serverUrl: _server.text,
          email: _email.text,
          password: _password.text,
          deviceName: _deviceName.text.trim(),
        );
      }
      _password.clear();
      await scope.vault.refreshStatus();
      navigator.pop();
    } on FormatException catch (error) {
      _fail(error.message);
    } on ApiException catch (error) {
      _fail(error.message);
    } on AccountVaultMismatchException catch (error) {
      _fail(error.message);
    } on VaultException catch (error) {
      _fail(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _fail(String message) {
    if (mounted) showMessage(context, message);
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 16);
    return Scaffold(
      appBar: AppBar(title: Text(_register ? 'Criar conta' : 'Entrar na conta')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Text(
                  'A conta serve apenas para sincronizar o cofre cifrado entre seus '
                  'dispositivos. Use uma senha diferente da senha mestre.',
                ),
                gap,
                TextFormField(
                  controller: _server,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                      labelText: 'Endereço do servidor', border: OutlineInputBorder()),
                  validator: (v) => (v ?? '').trim().length < 10 ? 'Informe o endereço.' : null,
                ),
                gap,
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'E-mail', border: OutlineInputBorder()),
                  validator: (v) => (v ?? '').contains('@') ? null : 'E-mail inválido.',
                ),
                gap,
                PasswordField(
                  controller: _password,
                  label: 'Senha da conta',
                  validator: (v) => _register && (v ?? '').length < 12
                      ? 'Use pelo menos 12 caracteres.'
                      : (v ?? '').isEmpty
                          ? 'Informe a senha.'
                          : null,
                ),
                gap,
                TextFormField(
                  controller: _deviceName,
                  decoration: const InputDecoration(
                      labelText: 'Nome deste dispositivo', border: OutlineInputBorder()),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Informe um nome.' : null,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox.square(
                          dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_register ? 'Criar conta' : 'Entrar'),
                ),
                if (widget.allowRegistration)
                  TextButton(
                    onPressed: _busy ? null : () => setState(() => _register = !_register),
                    child: Text(_register ? 'Já tenho conta' : 'Criar uma conta nova'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
