import 'package:test/test.dart';
import 'package:vault_core/vault_core.dart';

import 'support/fake_sync_server.dart';
import 'support/helpers.dart';

void main() {
  late FakeSyncServer server;
  late TestDevice windows;
  late TestDevice android;

  setUp(() async {
    server = FakeSyncServer();
    windows = TestDevice(server);
    android = TestDevice(server);
    await windows.createVault();
    await android.joinVaultOf(windows);
  });

  test('envia alterações locais e limpa a fila', () async {
    final item = await windows.addItem('GitHub');
    final report = await windows.sync.synchronize();

    expect(report.pushed, 1);
    expect(await windows.vault.pendingChangeCount(), 0);
    expect(windows.store.records[item.id]!.serverVersion, 1);
    expect(server.items[item.id]!.encryptedData, isNot(contains('s3cret')));
  });

  test('outro dispositivo recebe e descriptografa os itens', () async {
    await windows.addItem('GitHub', password: 'abc');
    await windows.sync.synchronize();

    final report = await android.sync.synchronize();
    expect(report.pulled, 1);
    expect((await android.itemTitled('GitHub')).password, 'abc');
  });

  test('offline: mantém a fila e envia quando a conexão volta', () async {
    await windows.addItem('Offline');
    server.offline = true;
    await expectLater(windows.sync.synchronize(), throwsA(isA<OfflineException>()));
    expect(await windows.vault.pendingChangeCount(), 1);

    server.offline = false;
    await windows.sync.synchronize();
    expect(await windows.vault.pendingChangeCount(), 0);
    expect(server.items, hasLength(1));
  });

  test('repetição após resposta perdida é idempotente', () async {
    final item = await windows.addItem('Retry');
    server.dropNextPushResponse = true;
    await expectLater(windows.sync.synchronize(), throwsA(isA<OfflineException>()));
    expect(server.items[item.id]!.version, 1, reason: 'servidor já aplicou');

    await windows.sync.synchronize();
    expect(server.items[item.id]!.version, 1, reason: 'não aplicou duas vezes');
    expect(await windows.vault.pendingChangeCount(), 0);
    expect(await windows.vault.loadConflicts(), isEmpty);
  });

  test('exclusões são sincronizadas como tombstones', () async {
    final item = await windows.addItem('Temporário');
    await windows.sync.synchronize();
    await android.sync.synchronize();
    expect(await android.items(), hasLength(1));

    await windows.vault.deleteItem(item.id);
    await windows.sync.synchronize();
    expect(server.items[item.id]!.deleted, isTrue);
    expect(server.items[item.id]!.encryptedData, isNull);

    await android.sync.synchronize();
    expect(await android.items(), isEmpty);
  });

  group('conflitos', () {
    late VaultItem original;

    setUp(() async {
      original = await windows.addItem('Banco', password: 'v1');
      await windows.sync.synchronize();
      await android.sync.synchronize();

      await windows.vault.saveItem(original.copyWith(password: 'windows'));
      await windows.sync.synchronize();
      await android.vault.saveItem(original.copyWith(password: 'android'));
    });

    test('preserva a versão local em vez de sobrescrever', () async {
      final report = await android.sync.synchronize();
      expect(report.conflicts, 1);

      // O registro principal passa a refletir o servidor...
      expect((await android.itemTitled('Banco')).password, 'windows');
      // ...e a versão local fica guardada para decisão do usuário.
      final conflict = (await android.vault.loadConflicts()).single;
      expect(conflict.local!.password, 'android');
      expect(conflict.remote!.password, 'windows');
      expect(server.items[original.id]!.version, 2);
    });

    test('manter a local reenvia sobre a versão do servidor', () async {
      await android.sync.synchronize();
      final conflict = (await android.vault.loadConflicts()).single;
      await android.vault.resolveConflict(conflict.conflictId, ConflictResolution.keepLocal);
      await android.sync.synchronize();

      expect(server.items[original.id]!.version, 3);
      await windows.sync.synchronize();
      expect((await windows.itemTitled('Banco')).password, 'android');
      expect(await android.vault.loadConflicts(), isEmpty);
    });

    test('manter a remota descarta a local', () async {
      await android.sync.synchronize();
      final conflict = (await android.vault.loadConflicts()).single;
      await android.vault.resolveConflict(conflict.conflictId, ConflictResolution.keepRemote);

      expect(await android.vault.pendingChangeCount(), 0);
      expect((await android.itemTitled('Banco')).password, 'windows');
    });

    test('manter ambas cria uma cópia sincronizável', () async {
      await android.sync.synchronize();
      final conflict = (await android.vault.loadConflicts()).single;
      await android.vault.resolveConflict(conflict.conflictId, ConflictResolution.keepBoth);
      await android.sync.synchronize();
      await windows.sync.synchronize();

      final titles = (await windows.items()).map((i) => i.title).toSet();
      expect(titles, {'Banco', 'Banco${VaultService.conflictCopySuffix}'});
    });

    test('edição x exclusão também gera conflito', () async {
      await windows.vault.deleteItem(original.id);
      await windows.sync.synchronize();
      // android já tem uma edição pendente sobre a versão 2... e o servidor
      // está na versão 3 (exclusão).
      await android.sync.synchronize();
      final conflicts = await android.vault.loadConflicts();
      expect(conflicts, isNotEmpty);
      expect(conflicts.last.remoteDeleted, isTrue);
      expect(conflicts.last.local!.password, 'android');
    });
  });

  test('edição durante o envio não é perdida', () async {
    final item = await windows.addItem('Em voo', password: 'primeira');
    server.onPush = () async {
      await windows.vault.saveItem(item.copyWith(password: 'segunda'));
    };
    await windows.sync.synchronize();

    // A primeira versão foi aceita; a segunda continua pendente sobre ela.
    expect(await windows.vault.pendingChangeCount(), 1);
    expect(windows.store.records[item.id]!.serverVersion, 1);

    await windows.sync.synchronize();
    expect(server.items[item.id]!.version, 2);
    await android.sync.synchronize();
    expect((await android.itemTitled('Em voo')).password, 'segunda');
  });

  test('paginação recebe todos os registros', () async {
    final engine = SyncEngine(store: android.store, api: android.api, pullPageSize: 3);
    for (var i = 0; i < 10; i++) {
      await windows.addItem('Item $i');
    }
    await windows.sync.synchronize();

    final report = await engine.synchronize();
    expect(report.pulled, 10);
    expect(await android.items(), hasLength(10));
  });

  test('recupera-se de um servidor restaurado de backup antigo', () async {
    final item = await windows.addItem('Recuperar', password: 'v1');
    await windows.sync.synchronize();
    final backup = server.snapshot();

    await windows.vault.saveItem(item.copyWith(password: 'v2'));
    await windows.sync.synchronize();
    expect(server.items[item.id]!.version, 2);

    server.restore(backup); // servidor volta para a versão 1
    await windows.sync.synchronize(); // detecta e reenfileira a versão local
    await windows.sync.synchronize(); // reenvia

    expect(server.items[item.id]!.version, 2);
    await android.sync.synchronize();
    expect((await android.itemTitled('Recuperar')).password, 'v2');
  });

  test('sincronizações concorrentes compartilham a mesma execução', () async {
    await windows.addItem('Único');
    final results = await Future.wait([
      windows.sync.synchronize(),
      windows.sync.synchronize(),
    ]);
    expect(identical(results[0], results[1]), isTrue);
    expect(windows.api.pushCalls, 1);
  });
}
