import 'package:flutter_test/flutter_test.dart';
import 'package:myvault/features/vault/vault_controller.dart';
import 'package:vault_core/testing.dart';
import 'package:vault_core/vault_core.dart';

// Parâmetros fracos SOMENTE para testes.
const _testParams = KdfParams(memoryKiB: 256, iterations: 1, parallelism: 1);
const _testKdf = KeyDerivation(
  floor: KdfParams(memoryKiB: 8, iterations: 1, parallelism: 1),
  runInIsolate: false,
);
const _password = 'uma senha mestre longa';

VaultController _controller(InMemoryLocalVaultStore store) => VaultController(
      service: VaultService(store: store, keyring: VaultKeyring(keyDerivation: _testKdf)),
      store: store,
      kdfParams: _testParams,
    );

void main() {
  test('fluxo de criação, bloqueio e desbloqueio', () async {
    final store = InMemoryLocalVaultStore();
    final controller = _controller(store);
    await controller.initialize();
    expect(controller.status, VaultStatus.noVault);

    await controller.createVault(_password);
    expect(controller.status, VaultStatus.unlocked);

    await controller.save(controller.draftItem().copyWith(title: 'Banco', password: 'x'));
    expect(controller.items.single.title, 'Banco');

    controller.lock();
    expect(controller.status, VaultStatus.locked);
    expect(controller.items, isEmpty, reason: 'dados descriptografados descartados');

    await expectLater(controller.unlock('senha errada qualquer'),
        throwsA(isA<InvalidMasterPasswordException>()));
    expect(controller.status, VaultStatus.locked);

    await controller.unlock(_password);
    expect(controller.items.single.title, 'Banco');
    controller.dispose();
  });

  test('alterações locais são sinalizadas para sincronização', () async {
    final controller = _controller(InMemoryLocalVaultStore());
    await controller.initialize();
    await controller.createVault(_password);

    var signals = 0;
    final subscription = controller.localChanges.listen((_) => signals++);
    final saved = await controller.save(controller.draftItem().copyWith(title: 'A'));
    await controller.delete(saved.id);
    await Future<void>.delayed(Duration.zero);

    expect(signals, 2);
    await subscription.cancel();
    controller.dispose();
  });

  test('persiste o tempo de bloqueio automático', () async {
    final store = InMemoryLocalVaultStore();
    final first = _controller(store);
    await first.initialize();
    await first.setAutoLock(const Duration(minutes: 15));
    first.dispose();

    final second = _controller(store);
    await second.initialize();
    expect(second.autoLockAfter, const Duration(minutes: 15));
    second.dispose();
  });
}
