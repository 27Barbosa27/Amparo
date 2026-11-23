// Teste de integração contra a API VERDADEIRA (não é simulada).
//   1. noutro terminal, em backend/:   npm run dev    e depois    npm run seed:dev
//   2. em app/:  flutter test --dart-define=API_REAL=http://127.0.0.1:3000 test/integracao_api_test.dart
// Sem API_REAL, estes testes ficam de fora. Mexe nos dados de demonstração (marca uma toma e desfaz).
import 'package:amparo/dados/api.dart';
import 'package:amparo/dados/autenticacao.dart';
import 'package:amparo/dados/repositorio.dart';
import 'package:amparo/dados/repositorio_api.dart';
import 'package:amparo/dominio/modelos.dart';
import 'package:flutter_test/flutter_test.dart';

const apiReal = String.fromEnvironment('API_REAL');

void main() {
  final saltar = apiReal.isEmpty
      ? 'defina --dart-define=API_REAL=<endereço da API>'
      : null;

  group('Contra a API verdadeira', skip: saltar, () {
    late ClienteApi api;
    late AutenticacaoApi auth;
    late RepositorioApi repo;
    late Perfil maria;

    setUp(() async {
      api = ClienteApi(base: Uri.parse(apiReal), sessao: SessaoMemoria());
      auth = AutenticacaoApi(api);
      repo = RepositorioApi(api);
    });

    test(
      'credenciais erradas dão o código estável; as certas entram',
      () async {
        expect(
          await auth.entrar('demo@amparo.test', 'errada-errada-1'),
          'credenciais_invalidas',
        );
        expect(
          await auth.entrar('demo@amparo.test', 'amparo-demo-123'),
          isNull,
        );
        expect(auth.nome, 'Ana');
      },
    );

    test('lê os perfis, as tomas de hoje, a adesão e o contacto', () async {
      await auth.entrar('demo@amparo.test', 'amparo-demo-123');
      final perfis = await repo.perfis();
      maria = perfis.firstWhere((p) => p.nome == 'Maria');
      final agora = DateTime.now();
      final tomas = await repo.tomasDeHoje(maria.id, agora);
      expect(
        tomas.map((t) => t.medicamento),
        containsAll(['Metformina', 'Lisinopril', 'Atorvastatina']),
      );
      expect(tomas.every((t) => t.dose.isNotEmpty), isTrue);
      final semana = await repo.ultimos7Dias(maria.id, agora);
      expect(semana, hasLength(7));
      expect(semana.last.resultado, ResultadoDia.emCurso);
      expect(await repo.nomeDoCuidador(maria.id), 'Ana');
    });

    test(
      'marcar, repetir (409), desfazer e saltar funcionam de ponta a ponta',
      () async {
        await auth.entrar('demo@amparo.test', 'amparo-demo-123');
        maria = (await repo.perfis()).firstWhere((p) => p.nome == 'Maria');
        final agora = DateTime.now();
        final pendente = (await repo.tomasDeHoje(
          maria.id,
          agora,
        )).firstWhere((t) => t.estado == EstadoToma.pendente);

        final tomada = await repo.marcarTomada(maria.id, pendente.id, agora);
        expect(tomada.estado, EstadoToma.tomada);
        expect(tomada.registadaPor, 'Ana'); // o servidor diz quem a marcou
        expect(tomada.podeDesfazer(DateTime.now()), isTrue);

        await expectLater(
          repo.marcarTomada(maria.id, pendente.id, agora),
          throwsA(
            isA<RegistoNaoPermitido>().having(
              (e) => e.motivo,
              'motivo',
              'toma_ja_registada',
            ),
          ),
        );

        final volta = await repo.desfazer(
          maria.id,
          pendente.id,
          DateTime.now(),
        );
        expect(volta.estado, EstadoToma.pendente);

        final saltada = await repo.saltar(
          maria.id,
          pendente.id,
          DateTime.now(),
        );
        expect(saltada.estado, EstadoToma.saltada);
        expect(
          (await repo.desfazer(maria.id, pendente.id, DateTime.now())).estado,
          EstadoToma.pendente,
        );
      },
    );

    test('uma hora no futuro é recusada pelo servidor', () async {
      await auth.entrar('demo@amparo.test', 'amparo-demo-123');
      maria = (await repo.perfis()).firstWhere((p) => p.nome == 'Maria');
      final pendente = (await repo.tomasDeHoje(
        maria.id,
        DateTime.now(),
      )).firstWhere((t) => t.estado == EstadoToma.pendente);
      await expectLater(
        repo.marcarTomada(
          maria.id,
          pendente.id,
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
    });

    test('um perfil que não é meu responde como inexistente, e sem sessão não se entra', () async {
      await auth.entrar('demo@amparo.test', 'amparo-demo-123');
      await expectLater(
        repo.tomasDeHoje(
          '11111111-1111-4111-8111-111111111111',
          DateTime.now(),
        ),
        throwsA(
          isA<ErroApi>().having(
            (e) => e.codigo,
            'codigo',
            'perfil_nao_encontrado',
          ),
        ),
      );
      await auth.sair();
      await expectLater(
        repo.perfis(),
        throwsA(
          isA<ErroApi>().having((e) => e.codigo, 'codigo', 'nao_autenticado'),
        ),
      );
    });

    test('adicionar pessoa e receita de ponta a ponta (gera as tomas em segundo plano) e apagar no fim', () async {
      await auth.entrar('demo@amparo.test', 'amparo-demo-123');
      final agora = DateTime.now();
      final pessoa = await repo.criarPessoa(
        NovaPessoa(
          nome: 'Teste ${agora.millisecondsSinceEpoch}',
          alarmesEm: AlarmesEm.pessoa,
          tamanhoTexto: TamanhoTexto.grande,
        ),
      );
      try {
        expect((await repo.perfis()).map((p) => p.id), contains(pessoa.id));
        final nova = NovaReceita(
          medicamento: 'Ramipril 5 mg',
          dose: '1 comprimido',
          frequencia: Frequencia.duasVezesDia,
          hora: 8,
          minuto: 0,
          duracao: Duracao.seteDias,
        );
        final r = await repo.criarReceita(pessoa.id, nova, agora);
        var e = await repo.estadoGeracao(pessoa.id, r.id);
        for (var i = 0; i < 40 && e.fase == FaseGeracao.aGerar; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          e = await repo.estadoGeracao(pessoa.id, r.id);
        }
        expect(e.fase, FaseGeracao.concluida);
        expect(e.tomasGeradas, inInclusiveRange(13, 15)); // 2 por dia, 7 dias
        final lista = await repo.receitas(pessoa.id);
        expect(lista.single.medicamento, 'Ramipril 5 mg');
        expect(lista.single.horario, '08:00, 20:00');
      } finally {
        // não deixar lixo nos dados de demonstração
        await api.pedir('DELETE', '/profiles/${pessoa.id}');
      }
      expect(
        (await repo.perfis()).map((p) => p.id),
        isNot(contains(pessoa.id)),
      );
    });

    test(
      'a sessão renova-se sozinha quando o token de acesso é inválido',
      () async {
        await auth.entrar('demo@amparo.test', 'amparo-demo-123');
        await api.sessao.guardar(
          acesso: 'token-estragado',
          renovacao: api.sessao.renovacao!,
        );
        final perfis = await repo.perfis(); // 401 → renova → repete
        expect(perfis, isNotEmpty);
        expect(api.sessao.acesso, isNot('token-estragado'));
      },
    );
  });
}
