import 'package:flutter/material.dart';

import '../account/sign_in_page.dart';
import 'create_vault_page.dart';

/// Primeira execução: criar um cofre novo ou conectar a uma conta existente.
class SetupPage extends StatelessWidget {
  const SetupPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Icon(Icons.lock_outline, size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text('MyVault', textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
              const SizedBox(height: 8),
              const Text(
                'Suas senhas são cifradas neste dispositivo antes de qualquer sincronização.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Criar um novo cofre'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const CreateVaultPage()),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.cloud_download_outlined),
                label: const Text('Conectar a uma conta existente'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SignInPage(allowRegistration: false),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
