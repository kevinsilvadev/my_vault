import 'package:flutter_test/flutter_test.dart';
import 'package:myvault/data/api/server_url.dart';

void main() {
  group('ServerUrl', () {
    test('aceita HTTPS e normaliza a barra final', () {
      expect(ServerUrl.parse(' https://cofre.example.com/ ').toString(), 'https://cofre.example.com');
      expect(ServerUrl.parse('HTTPS://cofre.example.com/api').path, '/api');
    });

    test('aceita HTTP apenas para servidores locais', () {
      expect(ServerUrl.parse('http://localhost:3000').port, 3000);
      expect(ServerUrl.parse('http://10.0.2.2:3000').host, '10.0.2.2');
      expect(() => ServerUrl.parse('http://cofre.example.com'), throwsFormatException);
    });

    test('rejeita endereços incompletos, outros esquemas e credenciais embutidas', () {
      expect(() => ServerUrl.parse('cofre.example.com'), throwsFormatException);
      expect(() => ServerUrl.parse('ftp://cofre.example.com'), throwsFormatException);
      expect(() => ServerUrl.parse('https://user:pass@cofre.example.com'), throwsFormatException);
      expect(() => ServerUrl.parse('https://cofre.example.com/?x=1'), throwsFormatException);
    });
  });
}
