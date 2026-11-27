import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../data/api/api_exception.dart';
import '../../data/api/myvault_api.dart';
import '../../shared/widgets.dart';
import 'sign_in_page.dart';

/// Conta, sincronização e dispositivos autorizados.
class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  Future<List<DeviceInfo>>? _devices;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _devices ??= _loadDevices();
  }

  Future<List<DeviceInfo>>? _loadDevices() {
    final account = AppScope.of(context).account;
    return account.isSignedIn ? account.devices() : null;
  }

  Future<void> _revoke(DeviceInfo device) async {
    final account = AppScope.of(context).account;
    final confirmed = await confirmAction(
      context,
      title: 'Revogar "${device.name}"?',
      message: 'O dispositivo perderá o acesso à sincronização imediatamente. '
          'Use isto se ele foi perdido ou roubado.',
      confirmLabel: 'Revogar',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await account.revokeDevice(device.id);
      if (mounted) setState(() => _devices = _loadDevices());
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message);
    }
  }

  Future<void> _logout() async {
    final account = AppScope.of(context).account;
    final confirmed = await confirmAction(
      context,
      title: 'Sair da conta?',
      message: 'O cofre local continua neste dispositivo, mas deixa de sincronizar. '
          'Alterações pendentes serão enviadas quando você entrar novamente.',
      confirmLabel: 'Sair',
    );
    if (confirmed) await account.logout();
  }

  @override
  Widget build(BuildContext context) {
    final account = AppScope.of(context).account;
    return Scaffold(
      appBar: AppBar(title: const Text('Conta e sincronização')),
      body: ListenableBuilder(
        listenable: account,
        builder: (context, _) {
          if (!account.isSignedIn) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Sem conta conectada. O cofre funciona apenas neste dispositivo.',
                      textAlign: TextAlign.center,
                    ),
                    if (account.lastError != null) ...[
                      const SizedBox(height: 8),
                      Text(account.lastError!, textAlign: TextAlign.center),
                    ],
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(builder: (_) => const SignInPage()),
                        );
                        if (mounted) setState(() => _devices = _loadDevices());
                      },
                      child: const Text('Conectar conta'),
                    ),
                  ],
                ),
              ),
            );
          }
          final lastSync = account.lastSyncAt;
          return ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.account_circle_outlined),
                title: Text(account.email ?? ''),
                subtitle: Text(account.serverUrl?.toString() ?? ''),
              ),
              ListTile(
                leading: Icon(account.lastError == null ? Icons.cloud_done_outlined : Icons.sync_problem),
                title: Text(lastSync == null
                    ? 'Ainda não sincronizado nesta sessão'
                    : 'Última sincronização: ${TimeOfDay.fromDateTime(lastSync).format(context)}'),
                subtitle: account.lastError == null ? null : Text(account.lastError!),
                trailing: FilledButton.tonal(
                  onPressed: account.isSyncing ? null : () => unawaited(account.syncNow()),
                  child: Text(account.isSyncing ? 'Sincronizando…' : 'Sincronizar'),
                ),
              ),
              const Divider(),
              const ListTile(title: Text('Dispositivos autorizados')),
              FutureBuilder<List<DeviceInfo>>(
                future: _devices,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const ListTile(title: Text('Não foi possível carregar os dispositivos.'));
                  }
                  final devices = snapshot.data;
                  if (devices == null) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return Column(
                    children: [
                      for (final device in devices)
                        ListTile(
                          leading: Icon(device.platform == 'android'
                              ? Icons.phone_android
                              : Icons.desktop_windows_outlined),
                          title: Text(device.current ? '${device.name} (este)' : device.name),
                          subtitle: Text(
                              'Visto em ${device.lastSeenAt.toLocal().toString().substring(0, 16)}'),
                          trailing: device.current
                              ? null
                              : IconButton(
                                  tooltip: 'Revogar',
                                  icon: const Icon(Icons.block),
                                  onPressed: () => _revoke(device),
                                ),
                        ),
                    ],
                  );
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Sair da conta'),
                onTap: _logout,
              ),
            ],
          );
        },
      ),
    );
  }
}
