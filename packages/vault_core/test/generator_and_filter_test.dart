import 'package:test/test.dart';
import 'package:vault_core/vault_core.dart';

VaultItem _item(String title,
        {String username = '', String url = '', String category = '', bool favorite = false}) =>
    VaultItem(
      id: title,
      title: title,
      username: username,
      url: url,
      category: category,
      favorite: favorite,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

void main() {
  group('PasswordGenerator', () {
    final generator = PasswordGenerator();

    test('respeita o comprimento configurado', () {
      for (final length in [8, 20, 64, 128]) {
        expect(generator.generate(PasswordGeneratorOptions(length: length)), hasLength(length));
      }
    });

    test('inclui ao menos um caractere de cada conjunto selecionado', () {
      for (var i = 0; i < 200; i++) {
        final password = generator.generate(const PasswordGeneratorOptions(length: 8));
        expect(password, matches(RegExp('[a-z]')));
        expect(password, matches(RegExp('[A-Z]')));
        expect(password, matches(RegExp('[0-9]')));
        expect(password, matches(RegExp(r'[^a-zA-Z0-9]')));
      }
    });

    test('usa apenas os conjuntos selecionados', () {
      final password = generator.generate(const PasswordGeneratorOptions(
        length: 64,
        uppercase: false,
        symbols: false,
      ));
      expect(password, matches(RegExp(r'^[a-z0-9]+$')));
    });

    test('exclui caracteres ambíguos quando solicitado', () {
      for (var i = 0; i < 50; i++) {
        final password = generator.generate(
            const PasswordGeneratorOptions(length: 128, excludeAmbiguous: true));
        expect(password, isNot(matches(RegExp('[Il1O0o]'))));
      }
    });

    test('gera valores diferentes a cada chamada', () {
      final values = {for (var i = 0; i < 100; i++) generator.generate()};
      expect(values, hasLength(100));
    });

    test('rejeita configurações inválidas', () {
      expect(() => generator.generate(const PasswordGeneratorOptions(length: 4)),
          throwsArgumentError);
      expect(
        () => generator.generate(const PasswordGeneratorOptions(
            lowercase: false, uppercase: false, digits: false, symbols: false)),
        throwsArgumentError,
      );
    });

    test('estima a entropia', () {
      const options = PasswordGeneratorOptions(
          length: 10, uppercase: false, symbols: false, lowercase: false);
      expect(options.entropyBits, closeTo(33.2, 0.1)); // 10 × log2(10)
    });
  });

  group('ItemFilter', () {
    final items = [
      _item('GitHub', username: 'dev', url: 'https://github.com', category: 'Trabalho'),
      _item('Banco', username: 'cliente123', category: 'Finanças', favorite: true),
      _item('e-mail', url: 'https://mail.example.com', category: 'Pessoal'),
    ];

    test('busca por título, usuário ou URL sem diferenciar maiúsculas', () {
      expect(const ItemFilter(query: 'github').apply(items).single.title, 'GitHub');
      expect(const ItemFilter(query: 'CLIENTE').apply(items).single.title, 'Banco');
      expect(const ItemFilter(query: 'example.com').apply(items).single.title, 'e-mail');
      expect(const ItemFilter(query: 'inexistente').apply(items), isEmpty);
    });

    test('filtra por categoria e favoritos', () {
      expect(const ItemFilter(category: 'Pessoal').apply(items).single.title, 'e-mail');
      expect(const ItemFilter(favoritesOnly: true).apply(items).single.title, 'Banco');
    });

    test('ordena favoritos primeiro e depois por título', () {
      expect(const ItemFilter().apply(items).map((i) => i.title), ['Banco', 'e-mail', 'GitHub']);
    });

    test('lista categorias distintas', () {
      expect(categoriesOf(items), ['Finanças', 'Pessoal', 'Trabalho']);
    });
  });

  group('MasterPasswordPolicy', () {
    test('exige comprimento mínimo e não aceita senha em branco', () {
      expect(MasterPasswordPolicy.validate('curta'), isNotEmpty);
      expect(MasterPasswordPolicy.validate('              '), isNotEmpty);
      expect(MasterPasswordPolicy.validate('uma frase longa o bastante'), isEmpty);
    });
  });
}
