import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show databaseFactoryFfi, sqfliteFfiInit;
import 'package:vault_core/vault_core.dart';

import 'app/myvault_app.dart';
import 'data/api/account_session_store.dart';
import 'data/local_database.dart';
import 'data/sqlite_vault_store.dart';
import 'features/account/account_controller.dart';
import 'features/vault/vault_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final DatabaseFactory factory;
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    factory = databaseFactoryFfi;
  } else {
    factory = databaseFactory;
  }
  final directory = await getApplicationSupportDirectory();
  final db = await LocalDatabase.open(factory, p.join(directory.path, 'myvault.db'));

  final store = SqliteVaultStore(db);
  final service = VaultService(store: store);
  final vault = VaultController(service: service, store: store);
  final account = AccountController(
    vault: service,
    store: store,
    sessionStore: AccountSessionStore(),
  );

  await Future.wait([vault.initialize(), account.initialize()]);

  // Alterações locais disparam sincronização; novidades remotas recarregam a lista.
  vault.localChanges.listen((_) => account.scheduleSync());
  account.onVaultChanged = () => unawaited(vault.refreshStatus().then((_) => vault.reload()));

  runApp(MyVaultApp(vault: vault, account: account));
}
