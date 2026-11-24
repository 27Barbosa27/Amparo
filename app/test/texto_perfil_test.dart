import 'package:amparo/dominio/modelos.dart';
import 'package:amparo/estado/hoje_controlador.dart';
import 'package:amparo/tema/tema.dart';
import 'package:amparo/tema/tokens.dart';
import 'package:amparo/ui/ecras/idoso_hoje.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

import 'apoio/repositorio_memoria.dart';

final _agora = DateTime(2026, 11, 21, 13, 0);

/// A altura do título "Boa tarde, ..." no modo simples, para a definição de texto dada.
Future<double> _alturaDoTitulo(
  WidgetTester tester,
  TamanhoTexto tamanho,
) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controlador = HojeControlador(
    repositorio: RepositorioMemoria(agora: _agora),
    perfil: Perfil(id: 'maria', nome: 'Maria', tamanhoTexto: tamanho),
    relogio: () => _agora,
  );
  await controlador.carregar();
  await tester.pumpWidget(
    MaterialApp(
      theme: criarTema(Tokens.escuroTema),
      home: Scaffold(body: IdosoHoje(controlador: controlador)),
    ),
  );
  await tester.pump();
  return tester.getSize(find.text('Boa tarde, Maria')).height;
}

void main() {
  setUpAll(() => initializeDateFormatting('pt_PT'));

  testWidgets('o modo simples aumenta o texto conforme a definição da pessoa', (
    tester,
  ) async {
    final normal = await _alturaDoTitulo(tester, TamanhoTexto.normal);
    final grande = await _alturaDoTitulo(tester, TamanhoTexto.grande);
    final muito = await _alturaDoTitulo(tester, TamanhoTexto.muitoGrande);
    expect(grande / normal, closeTo(1.15, 0.05));
    expect(muito / normal, closeTo(1.3, 0.05));
  });
}
