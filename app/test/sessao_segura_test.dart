import 'package:amparo/dados/sessao_segura.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a sessão guardada volta depois de reabrir a app', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final a = SessaoSegura();
    await a.guardar(acesso: 'acesso-1', renovacao: 'renovacao-1');

    final b = SessaoSegura(); // "reabrir a app"
    expect(b.renovacao, isNull);
    await b.carregar();
    expect(b.acesso, 'acesso-1');
    expect(b.renovacao, 'renovacao-1');
  });

  test('terminar a sessão apaga os tokens guardados', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final a = SessaoSegura();
    await a.guardar(acesso: 'x', renovacao: 'y');
    await a.limpar();

    final b = SessaoSegura();
    await b.carregar();
    expect(b.acesso, isNull);
    expect(b.renovacao, isNull);
  });
}
