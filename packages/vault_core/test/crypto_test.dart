import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vault_core/src/crypto/sensitive_key.dart';
import 'package:vault_core/vault_core.dart';

import 'support/helpers.dart';

SensitiveKey _randomKey() =>
    SensitiveKey(Uint8List.fromList(List.generate(32, (i) => (i * 7 + 3) % 256)));

Uint8List _flipByte(Uint8List source, int index) =>
    Uint8List.fromList(source)..[index] ^= 0x01;

void main() {
  group('KeyDerivation (Argon2id)', () {
    final salt = Uint8List.fromList(List.filled(16, 9));

    test('é determinística para mesma senha, salt e parâmetros', () async {
      final a = await testKdf.deriveKey(masterPassword: 'senha', salt: salt, params: testParams);
      final b = await testKdf.deriveKey(masterPassword: 'senha', salt: salt, params: testParams);
      expect(a.bytes, hasLength(32));
      expect(a.bytes, equals(b.bytes));
    });

    test('muda com outra senha ou outro salt', () async {
      final base = await testKdf.deriveKey(masterPassword: 'senha', salt: salt, params: testParams);
      final otherPassword =
          await testKdf.deriveKey(masterPassword: 'senhA', salt: salt, params: testParams);
      final otherSalt = await testKdf.deriveKey(
        masterPassword: 'senha',
        salt: Uint8List.fromList(List.filled(16, 8)),
        params: testParams,
      );
      expect(otherPassword.bytes, isNot(equals(base.bytes)));
      expect(otherSalt.bytes, isNot(equals(base.bytes)));
    });

    test('rejeita parâmetros abaixo do piso de produção', () {
      const production = KeyDerivation(runInIsolate: false);
      expect(
        production.deriveKey(masterPassword: 'x', salt: salt, params: testParams),
        throwsA(isA<InsecureKdfParametersException>()),
      );
    });

    test('rejeita parâmetros acima do teto (anti-DoS)', () {
      const production = KeyDerivation(runInIsolate: false);
      expect(
        production.deriveKey(
          masterPassword: 'x',
          salt: salt,
          params: const KdfParams(memoryKiB: 4 * 1024 * 1024, iterations: 3, parallelism: 4),
        ),
        throwsA(isA<InsecureKdfParametersException>()),
      );
    });

    test('rejeita salt curto', () {
      expect(
        testKdf.deriveKey(masterPassword: 'x', salt: [1, 2, 3], params: testParams),
        throwsA(isA<UnsupportedFormatException>()),
      );
    });

    test('padrões de produção respeitam o piso OWASP', () {
      expect(
        KdfParams.recommended.isWithin(floor: KdfParams.minimum, ceiling: KdfParams.maximum),
        isTrue,
      );
    });
  });

  group('AesGcmCipher', () {
    final cipher = AesGcmCipher();
    final aad = utf8.encode('contexto');
    final plaintext = utf8.encode('conteúdo secreto');

    test('cifra e decifra', () async {
      final key = _randomKey();
      final payload = await cipher.encrypt(plaintext, key, associatedData: aad);
      expect(payload.nonce, hasLength(AesGcmCipher.nonceLength));
      expect(payload.ciphertext, hasLength(plaintext.length + AesGcmCipher.tagLength));
      expect(await cipher.decrypt(payload, key, associatedData: aad), equals(plaintext));
    });

    test('usa nonce único a cada cifragem com a mesma chave', () async {
      final key = _randomKey();
      final nonces = <String>{};
      for (var i = 0; i < 500; i++) {
        final payload = await cipher.encrypt(plaintext, key, associatedData: aad);
        nonces.add(payload.nonceBase64);
      }
      expect(nonces, hasLength(500));
    });

    group('falha de forma segura quando', () {
      late SensitiveKey key;
      late EncryptedPayload payload;

      setUp(() async {
        key = _randomKey();
        payload = await cipher.encrypt(plaintext, key, associatedData: aad);
      });

      test('o ciphertext é alterado', () {
        final tampered = EncryptedPayload(
          nonce: payload.nonce,
          ciphertext: _flipByte(payload.ciphertext, 0),
        );
        expect(cipher.decrypt(tampered, key, associatedData: aad),
            throwsA(isA<DecryptionFailedException>()));
      });

      test('a tag é alterada', () {
        final tampered = EncryptedPayload(
          nonce: payload.nonce,
          ciphertext: _flipByte(payload.ciphertext, payload.ciphertext.length - 1),
        );
        expect(cipher.decrypt(tampered, key, associatedData: aad),
            throwsA(isA<DecryptionFailedException>()));
      });

      test('o nonce é alterado', () {
        final tampered = EncryptedPayload(
          nonce: _flipByte(payload.nonce, 0),
          ciphertext: payload.ciphertext,
        );
        expect(cipher.decrypt(tampered, key, associatedData: aad),
            throwsA(isA<DecryptionFailedException>()));
      });

      test('os dados associados diferem', () {
        expect(cipher.decrypt(payload, key, associatedData: utf8.encode('outro')),
            throwsA(isA<DecryptionFailedException>()));
      });

      test('a chave é outra', () {
        final other = SensitiveKey(Uint8List(32));
        expect(cipher.decrypt(payload, other, associatedData: aad),
            throwsA(isA<DecryptionFailedException>()));
      });

      test('o conteúdo está truncado ou o nonce tem tamanho errado', () {
        expect(
          cipher.decrypt(
            EncryptedPayload(nonce: payload.nonce, ciphertext: payload.ciphertext.sublist(0, 10)),
            key,
            associatedData: aad,
          ),
          throwsA(isA<DecryptionFailedException>()),
        );
        expect(
          cipher.decrypt(
            EncryptedPayload(nonce: Uint8List(8), ciphertext: payload.ciphertext),
            key,
            associatedData: aad,
          ),
          throwsA(isA<DecryptionFailedException>()),
        );
      });

      test('o base64 é inválido', () {
        expect(
          () => EncryptedPayload.fromBase64(nonce: '***', ciphertext: 'AAAA'),
          throwsA(isA<DecryptionFailedException>()),
        );
      });
    });

    test('a chave destruída não pode mais ser usada', () {
      final key = _randomKey()..destroy();
      expect(() => cipher.encrypt(plaintext, key, associatedData: aad), throwsStateError);
    });
  });

  group('VaultKeyring e envelope', () {
    final keyring = VaultKeyring(keyDerivation: testKdf);

    test('abre com a senha correta e obtém a mesma chave', () async {
      final (envelope, created) = await keyring.create(masterPassword, params: testParams);
      final opened = await keyring.open(envelope, masterPassword);
      expect(await opened.keyFingerprint(), equals(await created.keyFingerprint()));
    });

    test('senha errada resulta em erro genérico', () async {
      final (envelope, _) = await keyring.create(masterPassword, params: testParams);
      expect(
        keyring.open(envelope, 'senha errada qualquer'),
        throwsA(isA<InvalidMasterPasswordException>()
            .having((e) => e.message, 'message', 'Senha mestre incorreta.')),
      );
    });

    test('serializa e desserializa sem perdas', () async {
      final (envelope, _) = await keyring.create(masterPassword, params: testParams);
      final decoded = VaultKeyEnvelope.decode(envelope.encode());
      expect(decoded.matches(envelope), isTrue);
      expect(decoded.kdfParams, equals(testParams));
      await keyring.open(decoded, masterPassword);
    });

    test('envelope com parâmetros adulterados não abre', () async {
      final (envelope, _) = await keyring.create(masterPassword, params: testParams);
      final json = envelope.toJson();
      (json['kdf']! as Map<String, Object?>)['iterations'] = 2;
      final tampered = VaultKeyEnvelope.fromJson(json);
      expect(keyring.open(tampered, masterPassword),
          throwsA(isA<InvalidMasterPasswordException>()));
    });

    test('envelope com chave cifrada adulterada não abre', () async {
      final (envelope, _) = await keyring.create(masterPassword, params: testParams);
      final tampered = VaultKeyEnvelope(
        formatVersion: envelope.formatVersion,
        kdfParams: envelope.kdfParams,
        salt: envelope.salt,
        wrappedKey: EncryptedPayload(
          nonce: envelope.wrappedKey.nonce,
          ciphertext: _flipByte(envelope.wrappedKey.ciphertext, 3),
        ),
        createdAt: envelope.createdAt,
      );
      expect(keyring.open(tampered, masterPassword),
          throwsA(isA<InvalidMasterPasswordException>()));
    });

    test('rejeita versão de formato desconhecida e JSON inválido', () async {
      final (envelope, _) = await keyring.create(masterPassword, params: testParams);
      final json = envelope.toJson()..['formatVersion'] = 99;
      expect(() => VaultKeyEnvelope.fromJson(json), throwsA(isA<UnsupportedFormatException>()));
      expect(() => VaultKeyEnvelope.decode('{"x":'), throwsA(isA<UnsupportedFormatException>()));
    });

    test('cada cofre recebe salt e chave diferentes', () async {
      final (a, sa) = await keyring.create(masterPassword, params: testParams);
      final (b, sb) = await keyring.create(masterPassword, params: testParams);
      expect(a.salt, isNot(equals(b.salt)));
      expect(await sa.keyFingerprint(), isNot(equals(await sb.keyFingerprint())));
    });
  });

  group('VaultSession', () {
    late VaultSession session;
    final now = DateTime.utc(2026, 11, 27, 12);
    final item = VaultItem(
      id: '11111111-1111-4111-8111-111111111111',
      title: 'E-mail',
      username: 'eu@example.com',
      password: 'p@ss',
      url: 'https://mail.example.com',
      notes: 'nota',
      category: 'Pessoal',
      favorite: true,
      createdAt: now,
      updatedAt: now,
    );

    setUp(() async {
      final (_, created) = await VaultKeyring(keyDerivation: testKdf)
          .create(masterPassword, params: testParams);
      session = created;
    });

    test('cifra e decifra um item com todos os campos', () async {
      final payload = await session.encryptItem(item);
      final decrypted = await session.decryptItem(
        itemId: item.id,
        payload: payload,
        cryptoVersion: ItemCryptoFormat.current,
      );
      expect(decrypted, equals(item));
    });

    test('o ciphertext não contém o conteúdo em claro', () async {
      final payload = await session.encryptItem(item);
      final raw = latin1.decode(payload.ciphertext, allowInvalid: true);
      expect(raw.contains('p@ss'), isFalse);
      expect(raw.contains('eu@example.com'), isFalse);
    });

    test('não aceita ciphertext movido para outro id (AAD)', () async {
      final payload = await session.encryptItem(item);
      expect(
        session.decryptItem(
          itemId: '22222222-2222-4222-8222-222222222222',
          payload: payload,
          cryptoVersion: ItemCryptoFormat.current,
        ),
        throwsA(isA<DecryptionFailedException>()),
      );
    });

    test('rejeita versão criptográfica desconhecida', () async {
      final payload = await session.encryptItem(item);
      expect(
        session.decryptItem(itemId: item.id, payload: payload, cryptoVersion: 999),
        throwsA(isA<UnsupportedFormatException>()),
      );
    });

    test('após close, nenhuma operação é possível', () async {
      session.close();
      expect(session.isClosed, isTrue);
      expect(session.encryptItem(item), throwsA(isA<VaultLockedException>()));
    });

    test('toString do item não expõe campos sensíveis', () {
      expect(item.toString().contains('p@ss'), isFalse);
      expect(item.toString().contains('eu@example.com'), isFalse);
    });
  });
}
