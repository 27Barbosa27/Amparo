import 'dart:convert';

import 'package:amparo/app.dart';
import 'package:amparo/dados/api.dart';
import 'package:amparo/dados/autenticacao.dart';

import 'apoio/autenticacao_memoria.dart';
import 'apoio/repositorio_memoria.dart';

import 'package:amparo/ui/componentes/icones.dart';
import 'package:amparo/ui/ecras/criar_conta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

final agora = DateTime(2026, 11, 21, 13, 0);

/// Uma autenticação que recusa o registo com o código pedido.
class AutenticacaoQueRecusa extends AutenticacaoMemoria {
  AutenticacaoQueRecusa(this.codigo);
  final String codigo;
  int tentativas = 0;

  @override
  Future<String?> registar(String nome, String email, String senha) async {
    tentativas++;
    return codigo;
  }
}

Future<void> abrir(
  WidgetTester tester, {
  Autenticacao? auth,
  bool vazio = true,
}) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  await tester.pumpWidget(
    AmparoApp(
      repositorio: RepositorioMemoria(agora: agora, vazio: vazio),
      autenticacao: auth ?? AutenticacaoMemoria(),
      relogio: () => agora,
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Criar conta'));
  await tester.pumpAndSettle();
}

Future<void> preencher(
  WidgetTester tester, {
  String nome = 'Ana',
  String email = 'ana@exemplo.pt',
  String senha = 'uma-senha-segura-123',
  bool termos = true,
}) async {
  await tester.enterText(find.byType(TextField).at(0), nome);
  await tester.enterText(find.byType(TextField).at(1), email);
  await tester.enterText(find.byType(TextField).at(2), senha);
  if (termos) await tester.tap(find.byKey(const ValueKey('caixa-termos')));
  await tester.pumpAndSettle();
}

Future<void> criar(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(InkWell, 'Criar conta'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('pt_PT'));

  group('Validação do registo', () {
    test('aceita dados válidos', () {
      expect(
        validarRegisto(
          nome: 'Ana',
          email: 'ana@exemplo.pt',
          senha: '12345678',
          aceitaTermos: true,
        ).temErros,
        isFalse,
      );
    });

    test('cada campo dá o seu erro', () {
      final e = validarRegisto(
        nome: '  ',
        email: 'isto-nao-e-email',
        senha: 'curta',
        aceitaTermos: false,
      );
      expect(e.nome, isNotNull);
      expect(e.email, isNotNull);
      expect(e.senha, contains('8 caracteres'));
      expect(e.termos, isNotNull);
    });

    test('emails: aceita os normais e recusa os partidos', () {
      for (final bom in [
        'a@b.pt',
        'ana.silva+x@exemplo.com',
        ' ana@exemplo.pt ',
      ]) {
        expect(
          validarRegisto(
            nome: 'A',
            email: bom,
            senha: '12345678',
            aceitaTermos: true,
          ).email,
          isNull,
          reason: bom,
        );
      }
      for (final mau in [
        '',
        'ana',
        'ana@',
        '@exemplo.pt',
        'ana@exemplo',
        'a b@exemplo.pt',
      ]) {
        expect(
          validarRegisto(
            nome: 'A',
            email: mau,
            senha: '12345678',
            aceitaTermos: true,
          ).email,
          isNotNull,
          reason: mau,
        );
      }
    });

    test(
      'a palavra-passe tem de ter entre 8 e 128 caracteres (como no servidor)',
      () {
        expect(
          validarRegisto(
            nome: 'A',
            email: 'a@b.pt',
            senha: '1234567',
            aceitaTermos: true,
          ).senha,
          isNotNull,
        );
        expect(
          validarRegisto(
            nome: 'A',
            email: 'a@b.pt',
            senha: '12345678',
            aceitaTermos: true,
          ).senha,
          isNull,
        );
        expect(
          validarRegisto(
            nome: 'A',
            email: 'a@b.pt',
            senha: 'x' * 128,
            aceitaTermos: true,
          ).senha,
          isNull,
        );
        expect(
          validarRegisto(
            nome: 'A',
            email: 'a@b.pt',
            senha: 'x' * 129,
            aceitaTermos: true,
          ).senha,
          isNotNull,
        );
      },
    );
  });

  group('Criar conta (ecrã)', () {
    testWidgets('mostra os campos do design e a caixa dos termos desmarcada', (
      tester,
    ) async {
      await abrir(tester);
      expect(find.text('Como quer ser chamado?'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Palavra-passe'), findsOneWidget);
      expect(
        find.text(
          'Aceito os Termos, a Política de Privacidade e o tratamento dos dados de saúde para gerir as tomas.',
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('caixa-termos')),
          matching: find.byType(Icone),
        ),
        findsNothing,
      ); // o consentimento é um ato explícito: a caixa começa sem visto
      expect(find.text('ou registe-se com'), findsOneWidget);
      expect(find.text('Apple'), findsOneWidget);
      expect(find.text('Google'), findsOneWidget);
    });

    testWidgets(
      'não cria sem validar: mostra o erro de cada campo e não chama o servidor',
      (tester) async {
        final auth = AutenticacaoQueRecusa('x');
        await abrir(tester, auth: auth);
        await preencher(
          tester,
          nome: '',
          email: 'mau',
          senha: 'curta',
          termos: false,
        );
        await criar(tester);
        expect(find.text('Escreva como quer ser chamado.'), findsOneWidget);
        expect(
          find.text('Escreva um email válido, como nome@exemplo.pt.'),
          findsOneWidget,
        );
        expect(
          find.text('A palavra-passe precisa de pelo menos 8 caracteres.'),
          findsOneWidget,
        );
        expect(
          find.text('Para criar a conta, aceite os termos.'),
          findsOneWidget,
        );
        expect(auth.tentativas, 0);
      },
    );

    testWidgets(
      'um email que já existe mostra o erro do design, com a saída para Entrar',
      (tester) async {
        await abrir(tester, auth: AutenticacaoQueRecusa('email_ja_existe'));
        await preencher(tester);
        await criar(tester);
        expect(
          find.text('Já existe uma conta com este email.'),
          findsOneWidget,
        );
        await tester.tap(find.text('Entrar com este email'));
        await tester.pumpAndSettle();
        expect(
          find.text('Que bom ver de novo. Entre para ver as tomas.'),
          findsOneWidget,
        ); // voltou ao Entrar
      },
    );

    testWidgets('sem rede e outros erros dão uma mensagem clara', (
      tester,
    ) async {
      for (final (codigo, texto) in [
        (
          'sem_rede',
          'Sem ligação à internet. Verifique a ligação e tente outra vez.',
        ),
        (
          'demasiadas_tentativas',
          'Demasiadas tentativas. Espere um pouco e tente outra vez.',
        ),
        (
          'pedido_invalido',
          'Algum dado não é válido. Confirme o email e a palavra-passe.',
        ),
        ('erro_estranho', 'Não foi possível criar a conta. Tente outra vez.'),
      ]) {
        await abrir(tester, auth: AutenticacaoQueRecusa(codigo));
        await preencher(tester);
        await criar(tester);
        expect(find.text(texto), findsOneWidget, reason: codigo);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets(
      'fluxo completo: cria a conta, mostra "Conta criada!" e leva a adicionar a primeira pessoa',
      (tester) async {
        await abrir(tester);
        await preencher(tester, nome: 'Ana');
        await criar(tester);
        expect(find.text('Conta criada!'), findsOneWidget);
        expect(
          find.text('Olá, Ana. Já pode adicionar a primeira pessoa.'),
          findsOneWidget,
        );
        expect(find.text('Conta protegida'), findsOneWidget);
        await tester.tap(find.text('Adicionar a primeira pessoa'));
        await tester.pumpAndSettle();
        expect(
          find.text('Nome ou apelido'),
          findsOneWidget,
        ); // o formulário de pessoa
      },
    );

    testWidgets(
      '"Fazer isto mais tarde" deixa a conta aberta, à espera da primeira pessoa',
      (tester) async {
        await abrir(tester);
        await preencher(tester);
        await criar(tester);
        await tester.tap(find.text('Fazer isto mais tarde'));
        await tester.pumpAndSettle();
        expect(
          find.text(
            'Pode usá-lo só para si, para os seus medicamentos, ou acompanhar outra pessoa. Pode fazer as duas coisas.',
          ),
          findsOneWidget,
        );
      },
    );
  });

  group('Registo pela API', () {
    ClienteApi montar(
      http.Response Function(http.Request) f,
      SessaoMemoria sessao,
    ) => ClienteApi(
      base: Uri.parse('http://api.teste'),
      sessao: sessao,
      cliente: MockClient((r) async => f(r)),
    );

    test('envia o consentimento e guarda a sessão e o nome', () async {
      http.Request? visto;
      final sessao = SessaoMemoria();
      final api = montar((r) {
        visto = r;
        return http.Response(
          jsonEncode({
            'utilizador': {'id': 'u1', 'nome': 'Ana'},
            'accessToken': 'a1',
            'refreshToken': 'r1',
            'expiraEmSegundos': 900,
          }),
          201,
        );
      }, sessao);
      final auth = AutenticacaoApi(api);
      expect(
        await auth.registar('Ana', 'ana@exemplo.pt', 'uma-senha-segura-123'),
        isNull,
      );
      expect(visto!.url.path, '/auth/registo');
      expect(jsonDecode(visto!.body), {
        'email': 'ana@exemplo.pt',
        'senha': 'uma-senha-segura-123',
        'nome': 'Ana',
        'aceitaTermos': true,
      });
      expect(visto!.headers.containsKey('authorization'), isFalse);
      expect((sessao.acesso, sessao.renovacao, auth.nome), ('a1', 'r1', 'Ana'));
    });

    test('os erros do servidor passam como códigos', () async {
      for (final (estado, corpo, esperado) in [
        (409, {'erro': 'email_ja_existe'}, 'email_ja_existe'),
        (
          400,
          {
            'erro': 'pedido_invalido',
            'campos': ['senha'],
          },
          'pedido_invalido',
        ),
        (429, {'erro': 'demasiadas_tentativas'}, 'demasiadas_tentativas'),
      ]) {
        final auth = AutenticacaoApi(
          montar(
            (_) => http.Response(jsonEncode(corpo), estado),
            SessaoMemoria(),
          ),
        );
        expect(await auth.registar('Ana', 'a@b.pt', '12345678'), esperado);
      }
      final semRede = ClienteApi(
        base: Uri.parse('http://api.teste'),
        sessao: SessaoMemoria(),
        cliente: MockClient((_) async => throw http.ClientException('x')),
      );
      expect(
        await AutenticacaoApi(semRede).registar('Ana', 'a@b.pt', '12345678'),
        'sem_rede',
      );
    });
  });
}
