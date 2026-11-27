import 'package:test/test.dart';
import 'package:vault_core/testing.dart';
import 'package:vault_core/vault_core.dart';

import 'support/helpers.dart';

void main() {
  late InMemoryLocalVaultStore store;
  late VaultService vault;

  setUp(() {
    store = InMemoryLocalVaultStore();
    vault = newVaultService(store);
  });

  group('criação e desbloqueio', () {
    test('cria o cofre já desbloqueado e persiste apenas o envelope', () async {
      expect(await vault.hasVault(), isFalse);
      await vault.createVault(masterPassword, params: testParams);
      expect(vault.isUnlocked, isTrue);
      expect(await vault.hasVault(), isTrue);
      final rawEnvelope = await store.readMeta(MetaKeys.keyEnvelope);
      expect(rawEnvelope, isNot(contains(masterPassword)));
    });

    test('recusa senha mestre fraca', () {
      expect(vault.createVault('curta', params: testParams),
          throwsA(isA<WeakMasterPasswordException>()));
    });

    test('não sobrescreve um cofre existente', () async {
      await vault.createVault(masterPassword, params: testParams);
      expect(vault.createVault(masterPassword, params: testParams),
          throwsA(isA<VaultAlreadyExistsException>()));
    });

    test('bloqueia e desbloqueia', () async {
      await vault.createVault(masterPassword, params: testParams);
      final item = await vault.saveItem(vault.draftItem().copyWith(title: 'Banco'));
      vault.lock();
      expect(vault.isUnlocked, isFalse);
      expect(vault.loadItems(), throwsA(isA<VaultLockedException>()));

      await vault.unlock(masterPassword);
      expect((await vault.loadItems()).items.single, equals(item));
    });

    test('senha errada falha igual com ou sem itens no cofre', () async {
      await vault.createVault(masterPassword, params: testParams);
      vault.lock();
      final emptyError = await _captureUnlockError(vault);

      final other = newVaultService(InMemoryLocalVaultStore());
      await other.createVault(masterPassword, params: testParams);
      await other.saveItem(other.draftItem().copyWith(title: 'Existe'));
      other.lock();
      final fullError = await _captureUnlockError(other);

      expect(emptyError, isA<InvalidMasterPasswordException>());
      expect(fullError.runtimeType, emptyError.runtimeType);
      expect(fullError.toString(), emptyError.toString());
    });

    test('detecta substituição do envelope por outra chave', () async {
      await vault.createVault(masterPassword, params: testParams);
      vault.lock();
      // Um "servidor malicioso" troca o envelope por outro, com a mesma senha.
      final attacker = newVaultService(InMemoryLocalVaultStore());
      await attacker.createVault(masterPassword, params: testParams);
      await store.writeMeta(
          MetaKeys.keyEnvelope, (await attacker.readEnvelope())!.encode());

      expect(vault.unlock(masterPassword), throwsA(isA<VaultKeyMismatchException>()));
      expect(vault.isUnlocked, isFalse);
    });

    test('sem cofre, desbloquear informa ausência', () {
      expect(vault.unlock(masterPassword), throwsA(isA<VaultNotFoundException>()));
    });
  });

  group('CRUD', () {
    setUp(() => vault.createVault(masterPassword, params: testParams));

    test('salva, edita e preserva a data de criação', () async {
      final created = await vault.saveItem(vault.draftItem().copyWith(
        title: '  GitHub ',
        username: 'dev',
        password: 'x',
        url: ' https://github.com ',
        category: ' Trabalho ',
      ));
      expect(created.title, 'GitHub');
      expect(created.url, 'https://github.com');
      expect(created.category, 'Trabalho');

      final updated = await vault.saveItem(created.copyWith(password: 'y'));
      final items = (await vault.loadItems()).items;
      expect(items, hasLength(1));
      expect(items.single.password, 'y');
      expect(items.single.createdAt, created.createdAt);
      expect(updated.updatedAt.isBefore(created.updatedAt), isFalse);
    });

    test('persiste somente ciphertext e coloca na fila de sincronização', () async {
      final item = await vault.saveItem(
          vault.draftItem().copyWith(title: 'Banco', password: 'senha-do-banco'));
      final record = store.records[item.id]!;
      expect(record.encryptedData, isNot(contains('senha-do-banco')));
      expect(record.hasPendingChange, isTrue);
      expect(record.pendingOperation, PendingOperation.upsert);
      expect(record.serverVersion, 0);
    });

    test('rejeita item sem título', () {
      expect(vault.saveItem(vault.draftItem()), throwsA(isA<ItemValidationException>()));
    });

    test('exclusão gera tombstone pendente e remove da listagem', () async {
      final item = await vault.saveItem(vault.draftItem().copyWith(title: 'Apagar'));
      await vault.deleteItem(item.id);

      expect((await vault.loadItems()).items, isEmpty);
      final record = store.records[item.id]!;
      expect(record.deleted, isTrue);
      expect(record.encryptedData, isNull);
      expect(record.pendingOperation, PendingOperation.delete);
    });

    test('registro corrompido é isolado sem quebrar o cofre', () async {
      final ok = await vault.saveItem(vault.draftItem().copyWith(title: 'Ok'));
      final bad = await vault.saveItem(vault.draftItem().copyWith(title: 'Ruim'));
      final record = store.records[bad.id]!;
      final data = record.encryptedData!;
      final replacement = data[0] == 'A' ? 'B' : 'A';
      await store.upsertRecord(record.copyWith(
        encryptedData: '$replacement${data.substring(1)}',
      ));

      final snapshot = await vault.loadItems();
      expect(snapshot.items.map((i) => i.id), [ok.id]);
      expect(snapshot.undecryptableIds, [bad.id]);
    });
  });
}

Future<Object> _captureUnlockError(VaultService vault) async {
  try {
    await vault.unlock('senha incorreta 123');
  } on Object catch (error) {
    return error;
  }
  fail('Desbloqueio deveria falhar');
}
