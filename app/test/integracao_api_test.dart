// Teste de integração contra a API VERDADEIRA (não é simulada). Não usa dados prontos: cada teste cria a sua
// própria conta, as suas pessoas e receitas, e apaga tudo no fim.
//   1. noutro terminal, em backend/:   npm run dev
//   2. em app/:  flutter test --dart-define=API_REAL=http://127.0.0.1:3000 test/integracao_api_test.dart
// Sem API_REAL, estes testes ficam de fora.
import 'package:amparo/dados/api.dart';
import 'package:amparo/dados/autenticacao.dart';
import 'package:amparo/dados/repositorio.dart';
import 'package:amparo/dados/repositorio_api.dart';
import 'package:amparo/dominio/modelos.dart';
import 'package:flutter_test/flutter_test.dart';

const apiReal = String.fromEnvironment('API_REAL');
const senha = 'palavra-passe-de-teste-1';

/// Uma conta de teste, criada de raiz e apagada no fim.
class Conta {
  Conta._(this.email, this.api)
    : auth = AutenticacaoApi(api),
      repo = RepositorioApi(api);

  final String email;
  final ClienteApi api;
  final AutenticacaoApi auth;
  final RepositorioApi repo;

  static int _n = 0;

  static ClienteApi _novoCliente() =>
      ClienteApi(base: Uri.parse(apiReal), sessao: SessaoMemoria());

  static Future<Conta> criar() async {
    final email =
        'integracao.${DateTime.now().microsecondsSinceEpoch}.${_n++}@amparo.test';
    final c = Conta._(email, _novoCliente());
    final erro = await c.auth.registar('Rui', email, senha);
    expect(erro, isNull, reason: 'não foi possível criar a conta de teste');
    return c;
  }

  /// Entra com as mesmas credenciais, num cliente novo (sem sessão).
  Future<String?> entrarDeNovo() =>
      AutenticacaoApi(_novoCliente()).entrar(email, senha);

  Future<void> apagar() async {
    // Apaga a conta e as pessoas que só ela tinha (o servidor trata disso).
    await api.pedir('DELETE', '/auth/me', corpo: {'senha': senha});
  }
}

NovaPessoa pessoa(String nome) => NovaPessoa(
  nome: nome,
  alarmesEm: AlarmesEm.pessoa,
  tamanhoTexto: TamanhoTexto.grande,
);

/// Uma receita "de 8 em 8 horas" que começa daqui a poucos minutos, para haver tomas já.
NovaReceita receitaJa(DateTime agora) {
  final t = agora.add(const Duration(minutes: 2));
  return NovaReceita(
    medicamento: 'Ramipril 5 mg',
    dose: '1 comprimido',
    frequencia: Frequencia.cadaOitoHoras,
    hora: t.hour,
    minuto: t.minute,
    duracao: Duracao.umMes,
  );
}

Future<EstadoGeracao> esperarGeracao(
  Repositorio repo,
  String perfilId,
  String receitaId,
) async {
  var e = await repo.estadoGeracao(perfilId, receitaId);
  for (var i = 0; i < 40 && e.fase == FaseGeracao.aGerar; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    e = await repo.estadoGeracao(perfilId, receitaId);
  }
  return e;
}

void main() {
  final saltar = apiReal.isEmpty
      ? 'defina --dart-define=API_REAL=<endereço da API>'
      : null;

  group('Contra a API verdadeira', skip: saltar, () {
    late Conta c;
    setUp(() async => c = await Conta.criar());
    tearDown(() async => c.apagar());

    test('uma conta nova entra com as credenciais, começa sem ninguém e recusa o mesmo email e senhas curtas', () async {
      expect(c.auth.nome, 'Rui');
      expect(await c.repo.perfis(), isEmpty);
      expect(await c.entrarDeNovo(), isNull);
      final outra = AutenticacaoApi(Conta._novoCliente());
      expect(
        await outra.entrar(c.email, 'errada-errada-1'),
        'credenciais_invalidas',
      );
      expect(await outra.registar('Rui', c.email, senha), 'email_ja_existe');
      expect(
        await outra.registar('Rui', 'curta.${c.email}', 'curta'),
        'pedido_invalido',
      );
    });

    test('apagar a conta faz com que deixe de entrar', () async {
      final outra = await Conta.criar();
      expect(await outra.entrarDeNovo(), isNull);
      await outra.apagar();
      expect(await outra.entrarDeNovo(), 'credenciais_invalidas');
    });

    test('adicionar pessoa e receita: as tomas geram-se em segundo plano e a lista reflete-o', () async {
      final agora = DateTime.now();
      final p = await c.repo.criarPessoa(pessoa('Teste'));
      expect((await c.repo.perfis()).map((x) => x.id), [p.id]);

      final r = await c.repo.criarReceita(p.id, receitaJa(agora), agora);
      final e = await esperarGeracao(c.repo, p.id, r.id);
      expect(e.fase, FaseGeracao.concluida);
      expect(
        e.tomasGeradas,
        inInclusiveRange(18, 22),
      ); // 3 por dia durante 7 dias

      final lista = await c.repo.receitas(p.id);
      expect(lista.single.medicamento, 'Ramipril 5 mg');
      expect(lista.single.horario, 'De 8 em 8 horas');
      expect(
        lista.single.diasRestantes,
        isNull,
      ); // sem unidades iniciais, não há stock a calcular
    });

    test(
      'marcar, repetir (409), desfazer e saltar funcionam de ponta a ponta',
      () async {
        final agora = DateTime.now();
        final p = await c.repo.criarPessoa(pessoa('Teste'));
        final r = await c.repo.criarReceita(p.id, receitaJa(agora), agora);
        await esperarGeracao(c.repo, p.id, r.id);

        // a primeira toma, em qualquer dia (a hora escolhida pode já ser a de amanhã)
        final j = await c.api.pedir(
          'GET',
          '/tomas',
          perfilId: p.id,
          query: {
            'de': agora
                .subtract(const Duration(hours: 1))
                .toUtc()
                .toIso8601String(),
            'ate': agora
                .add(const Duration(hours: 48))
                .toUtc()
                .toIso8601String(),
          },
        );
        final tomaId = ((j!['tomas'] as List).first as Map)['id'] as String;

        final tomada = await c.repo.marcarTomada(p.id, tomaId, agora);
        expect(tomada.estado, EstadoToma.tomada);
        expect(tomada.registadaPor, 'Rui'); // o servidor diz quem a marcou
        expect(tomada.podeDesfazer(DateTime.now()), isTrue);

        await expectLater(
          c.repo.marcarTomada(p.id, tomaId, agora),
          throwsA(
            isA<RegistoNaoPermitido>().having(
              (e) => e.motivo,
              'motivo',
              'toma_ja_registada',
            ),
          ),
        );
        expect(
          (await c.repo.desfazer(p.id, tomaId, DateTime.now())).estado,
          EstadoToma.pendente,
        );
        expect(
          (await c.repo.saltar(p.id, tomaId, DateTime.now())).estado,
          EstadoToma.saltada,
        );
        expect(
          (await c.repo.desfazer(p.id, tomaId, DateTime.now())).estado,
          EstadoToma.pendente,
        );

        // uma hora no futuro é recusada
        await expectLater(
          c.repo.marcarTomada(
            p.id,
            tomaId,
            DateTime.now(),
            hora: DateTime.now().add(const Duration(hours: 3)),
          ),
          throwsA(
            isA<RegistoNaoPermitido>().having(
              (e) => e.motivo,
              'motivo',
              'hora_invalida',
            ),
          ),
        );
      },
    );

    test(
      'cada conta só vê as suas pessoas: a de outra responde como inexistente',
      () async {
        final p = await c.repo.criarPessoa(pessoa('Só da primeira'));
        final outra = await Conta.criar();
        try {
          expect(await outra.repo.perfis(), isEmpty);
          await expectLater(
            outra.repo.tomasDeHoje(p.id, DateTime.now()),
            throwsA(
              isA<ErroApi>().having(
                (e) => e.codigo,
                'codigo',
                'perfil_nao_encontrado',
              ),
            ),
          );
          await expectLater(
            outra.repo.receitas(p.id),
            throwsA(
              isA<ErroApi>().having(
                (e) => e.codigo,
                'codigo',
                'perfil_nao_encontrado',
              ),
            ),
          );
        } finally {
          await outra.apagar();
        }
      },
    );

    test('sem sessão não se lê nada; depois de sair, também não', () async {
      await c.auth.sair();
      await expectLater(
        c.repo.perfis(),
        throwsA(
          isA<ErroApi>().having((e) => e.codigo, 'codigo', 'nao_autenticado'),
        ),
      );
      // volta a entrar para o tearDown conseguir apagar a conta
      expect(await c.auth.entrar(c.email, senha), isNull);
    });

    test(
      'a sessão renova-se sozinha quando o token de acesso é inválido',
      () async {
        await c.api.sessao.guardar(
          acesso: 'token-estragado',
          renovacao: c.api.sessao.renovacao!,
        );
        expect(await c.repo.perfis(), isEmpty); // 401 → renova → repete
        expect(c.api.sessao.acesso, isNot('token-estragado'));
      },
    );
  });
}
