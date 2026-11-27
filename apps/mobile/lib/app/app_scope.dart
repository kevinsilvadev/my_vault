import 'package:flutter/widgets.dart';

import '../features/account/account_controller.dart';
import '../features/vault/vault_controller.dart';

/// Injeção de dependências simples via árvore de widgets.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.vault,
    required this.account,
    required super.child,
  });

  final VaultController vault;
  final AccountController account;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope não encontrado na árvore de widgets.');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      vault != oldWidget.vault || account != oldWidget.account;
}
