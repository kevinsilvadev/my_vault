import 'package:vault_core/testing.dart';
import 'package:vault_core/vault_core.dart';

import 'fake_sync_server.dart';

/// Parâmetros fracos, SOMENTE para testes rápidos. Nunca usar em produção.
const KdfParams testParams =
    KdfParams(memoryKiB: 256, iterations: 1, parallelism: 1);

const KeyDerivation testKdf = KeyDerivation(
  floor: KdfParams(memoryKiB: 8, iterations: 1, parallelism: 1),
  runInIsolate: false,
);

const String masterPassword = 'correct horse battery staple';

VaultService newVaultService(LocalVaultStore store) => VaultService(
      store: store,
      keyring: VaultKeyring(keyDerivation: testKdf),
    );

/// Um "dispositivo": armazenamento local + serviço do cofre + sincronização.
final class TestDevice {
  TestDevice(FakeSyncServer server)
      : store = InMemoryLocalVaultStore(),
        api = server.clientFor() {
    vault = newVaultService(store);
    sync = SyncEngine(store: store, api: api);
  }

  final InMemoryLocalVaultStore store;
  final FakeSyncApi api;
  late final VaultService vault;
  late final SyncEngine sync;

  /// Cria o cofre neste dispositivo.
  Future<void> createVault() =>
      vault.createVault(masterPassword, params: testParams);

  /// Conecta este dispositivo ao cofre criado em [origin].
  Future<void> joinVaultOf(TestDevice origin) async {
    await vault.adoptEnvelope((await origin.vault.readEnvelope())!);
    await vault.unlock(masterPassword);
  }

  Future<VaultItem> addItem(String title, {String password = 's3cret'}) =>
      vault.saveItem(vault.draftItem().copyWith(title: title, password: password));

  Future<List<VaultItem>> items() async => (await vault.loadItems()).items;

  Future<VaultItem> itemTitled(String title) async =>
      (await items()).singleWhere((i) => i.title == title);
}
