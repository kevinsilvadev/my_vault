import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../vault/vault_controller.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  static String _label(Duration duration) =>
      duration.inMinutes == 1 ? '1 minuto' : '${duration.inMinutes} minutos';

  @override
  Widget build(BuildContext context) {
    final vault = AppScope.of(context).vault;
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: ListenableBuilder(
        listenable: vault,
        builder: (context, _) => ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Bloqueio automático'),
              subtitle: const Text('Bloqueia o cofre após este tempo sem interação.'),
              trailing: DropdownButton<Duration>(
                value: VaultController.autoLockOptions.contains(vault.autoLockAfter)
                    ? vault.autoLockAfter
                    : null,
                items: [
                  for (final option in VaultController.autoLockOptions)
                    DropdownMenuItem(value: option, child: Text(_label(option))),
                ],
                onChanged: (value) {
                  if (value != null) unawaited(vault.setAutoLock(value));
                },
              ),
            ),
            const ListTile(
              leading: Icon(Icons.phone_android),
              title: Text('Ao ir para segundo plano'),
              subtitle: Text('No Android, o cofre é bloqueado imediatamente.'),
            ),
            const ListTile(
              leading: Icon(Icons.fingerprint),
              title: Text('Desbloqueio por biometria'),
              subtitle: Text('Planejado para a fase 6 (ver docs/security.md).'),
              enabled: false,
            ),
          ],
        ),
      ),
    );
  }
}
