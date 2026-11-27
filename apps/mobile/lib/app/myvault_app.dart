import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/account/account_controller.dart';
import '../features/items/items_page.dart';
import '../features/setup/setup_page.dart';
import '../features/unlock/unlock_page.dart';
import '../features/vault/vault_controller.dart';
import 'app_scope.dart';

class MyVaultApp extends StatefulWidget {
  const MyVaultApp({super.key, required this.vault, required this.account});

  final VaultController vault;
  final AccountController account;

  @override
  State<MyVaultApp> createState() => _MyVaultAppState();
}

class _MyVaultAppState extends State<MyVaultApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final AppLifecycleListener _lifecycle;
  VaultStatus? _lastStatus;

  @override
  void initState() {
    super.initState();
    // Ao ir para segundo plano no Android, bloqueia imediatamente.
    _lifecycle = AppLifecycleListener(onPause: widget.vault.lock);
    HardwareKeyboard.instance.addHandler(_onKey);
    widget.vault.addListener(_onVaultChanged);
  }

  @override
  void dispose() {
    widget.vault.removeListener(_onVaultChanged);
    HardwareKeyboard.instance.removeHandler(_onKey);
    _lifecycle.dispose();
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    widget.vault.registerActivity();
    return false;
  }

  /// Ao bloquear, descarta todas as telas abertas (que podem exibir dados).
  void _onVaultChanged() {
    final status = widget.vault.status;
    if (status != _lastStatus) {
      _lastStatus = status;
      _navigatorKey.currentState?.popUntil((route) => route.isFirst);
      if (status == VaultStatus.unlocked) unawaited(widget.account.syncNow());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      vault: widget.vault,
      account: widget.account,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => widget.vault.registerActivity(),
        onPointerSignal: (_) => widget.vault.registerActivity(),
        child: MaterialApp(
          title: 'MyVault',
          navigatorKey: _navigatorKey,
          debugShowCheckedModeBanner: false,
          theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
          darkTheme: ThemeData(
            colorSchemeSeed: Colors.indigo,
            brightness: Brightness.dark,
            useMaterial3: true,
          ),
          home: ListenableBuilder(
            listenable: widget.vault,
            builder: (context, _) => switch (widget.vault.status) {
              VaultStatus.loading =>
                const Scaffold(body: Center(child: CircularProgressIndicator())),
              VaultStatus.noVault => const SetupPage(),
              VaultStatus.locked => const UnlockPage(),
              VaultStatus.unlocked => const ItemsPage(),
            },
          ),
        ),
      ),
    );
  }
}
