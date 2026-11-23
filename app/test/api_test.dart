import 'dart:async';
import 'dart:convert';

import 'package:amparo/dados/api.dart';
import 'package:amparo/dados/autenticacao.dart';
import 'package:amparo/dados/repositorio.dart';
import 'package:amparo/dados/repositorio_api.dart';
import 'package:amparo/dominio/modelos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

typedef Pedido = http.Request;

/// Um servidor simulado: regista os pedidos e responde com o que o teste definir.
class Servidor {
  final pedidos = <Pedido>[];
  final respostas = <String, http.Response Function(Pedido)>{};

  MockClient get cliente => MockClient((r) async {
    pedidos.add(r);
    final f = respostas['${r.method} ${r.url.path}'];
    if (f == null) {
      return http.Response(jsonEncode({'erro': 'nao_encontrado'}), 404);
    }
    return f(r);
  });

  void responder(String chave, Object corpo, [int estado = 200]) =>
      respostas[chave] = (_) => http.Response(
        jsonEncode(corpo),
        estado,
        headers: {'content-type': 'application/json'},
      );

  Iterable<Pedido> de(String chave) =>
      pedidos.where((p) => '${p.method} ${p.url.path}' == chave);
}

({Servidor servidor, ClienteApi api, SessaoMemoria sessao}) montar() {
  final s = Servidor();
  final sessao = SessaoMemoria();
  return (
    servidor: s,
    api: ClienteApi(
      base: Uri.parse('http://api.teste'),
      sessao: sessao,
      cliente: s.cliente,
    ),
    sessao: sessao,
  );
}

Map<String, Object?> tomaJson(
  String id,
  String estado, {
  String agendada = '2026-11-21T09:00:00Z',
  String? tomadaEm,
  String? por,
  String atualizada = '2026-11-21T09:05:00Z',
}) => {
  'id': id,
  'receitaId': 'r1',
  'medicamento': {'nome': 'Lisinopril'},
  'dose': '10 mg',
  'agendadaUtc': agendada,
  'estado': estado,
  'atrasada': false,
  'tomadaEmUtc': tomadaEm,
  'origem': por == null ? null : 'cuidador',
  'registadaPor': por,
  'editadaManualmente': false,
  'atualizadoEm': atualizada,
};

void main() {
  group('Entrar', () {
    test('guarda os tokens e o nome do cuidador', () async {
      final m = montar();
      m.servidor.responder('POST /auth/login', {
        'utilizador': {'id': 'u1', 'nome': 'Ana'},
        'accessToken': 'acesso-1',
        'refreshToken': 'renova-1',
        'expiraEmSegundos': 900,
      });
      final auth = AutenticacaoApi(m.api);
      expect(
        await auth.entrar('ana@exemplo.pt', 'uma-senha-segura-123'),
        isNull,
      );
      expect(auth.nome, 'Ana');
      expect(m.sessao.acesso, 'acesso-1');
      expect(m.sessao.renovacao, 'renova-1');
      final corpo =
          jsonDecode(m.servidor.de('POST /auth/login').single.body) as Map;
      expect(corpo, {
        'email': 'ana@exemplo.pt',
        'senha': 'uma-senha-segura-123',
      });
      expect(
        m.servidor
            .de('POST /auth/login')
            .single
            .headers
            .containsKey('authorization'),
        isFalse,
      );
    });

    test('devolve o código estável de cada erro', () async {
      final m = montar();
      final auth = AutenticacaoApi(m.api);
      m.servidor.responder('POST /auth/login', {
        'erro': 'credenciais_invalidas',
      }, 401);
      expect(
        await auth.entrar('a@b.pt', 'errada-errada-1'),
        'credenciais_invalidas',
      );
      m.servidor.responder('POST /auth/login', {
        'erro': 'demasiadas_tentativas',
      }, 429);
      expect(
        await auth.entrar('a@b.pt', 'errada-errada-1'),
        'demasiadas_tentativas',
      );
      expect(m.sessao.acesso, isNull);
    });

    test('sem rede dá "sem_rede", incluindo quando o servidor não responde a tempo', () async {
      final sessao = SessaoMemoria();
      final semRede = ClienteApi(
        base: Uri.parse('http://api.teste'),
        sessao: sessao,
        cliente: MockClient(
          (_) async => throw http.ClientException('sem ligação'),
        ),
      );
      expect(await AutenticacaoApi(semRede).entrar('a@b.pt', 'x'), 'sem_rede');
      final lento = ClienteApi(
        base: Uri.parse('http://api.teste'),
        sessao: sessao,
        tempoLimite: const Duration(milliseconds: 50),
        cliente: MockClient((_) => Completer<http.Response>().future),
      );
      expect(await AutenticacaoApi(lento).entrar('a@b.pt', 'x'), 'sem_rede');
    });

    test('sair avisa o servidor e apaga a sessão, mesmo sem rede', () async {
      final m = montar();
      m.sessao.guardar(acesso: 'a', renovacao: 'r');
      m.servidor.responder('POST /auth/logout', {}, 204);
      final auth = AutenticacaoApi(m.api);
      await auth.sair();
      expect(jsonDecode(m.servidor.de('POST /auth/logout').single.body), {
        'refreshToken': 'r',
      });
      expect(m.sessao.renovacao, isNull);

      final semRede = ClienteApi(
        base: Uri.parse('http://api.teste'),
        sessao: SessaoMemoria()..renovacao = 'r2',
        cliente: MockClient((_) async => throw http.ClientException('x')),
      );
      await AutenticacaoApi(semRede).sair();
      expect(semRede.sessao.renovacao, isNull);
    });
  });

  group('Sessão', () {
    test('envia o token de acesso e o perfil em cada pedido', () async {
      final m = montar();
      m.sessao.guardar(acesso: 'acesso-1', renovacao: 'renova-1');
      m.servidor.responder('GET /tomas', {'tomas': []});
      await m.api.pedir('GET', '/tomas', perfilId: 'perfil-9');
      final p = m.servidor.de('GET /tomas').single;
      expect(p.headers['authorization'], 'Bearer acesso-1');
      expect(p.headers['x-profile-id'], 'perfil-9');
    });

    test(
      'renova o token expirado uma vez e repete o pedido com o novo',
      () async {
        final m = montar();
        m.sessao.guardar(acesso: 'velho', renovacao: 'renova-1');
        m.servidor.respostas['GET /profiles'] = (r) =>
            r.headers['authorization'] == 'Bearer novo'
            ? http.Response(jsonEncode({'perfis': []}), 200)
            : http.Response(jsonEncode({'erro': 'nao_autenticado'}), 401);
        m.servidor.responder('POST /auth/refresh', {
          'accessToken': 'novo',
          'refreshToken': 'renova-2',
          'expiraEmSegundos': 900,
        });
        final j = await m.api.pedir('GET', '/profiles');
        expect(j, {'perfis': []});
        expect(m.sessao.acesso, 'novo');
        expect(m.sessao.renovacao, 'renova-2');
        expect(jsonDecode(m.servidor.de('POST /auth/refresh').single.body), {
          'refreshToken': 'renova-1',
        });
      },
    );

    test('pedidos em simultâneo partilham a mesma renovação (o refresh token só serve uma vez)', () async {
      final m = montar();
      m.sessao.guardar(acesso: 'velho', renovacao: 'renova-1');
      m.servidor.respostas['GET /profiles'] = (r) =>
          r.headers['authorization'] == 'Bearer novo'
          ? http.Response(jsonEncode({'perfis': []}), 200)
          : http.Response(jsonEncode({'erro': 'nao_autenticado'}), 401);
      m.servidor.respostas['POST /auth/refresh'] = (_) => http.Response(
        jsonEncode({
          'accessToken': 'novo',
          'refreshToken': 'renova-2',
          'expiraEmSegundos': 900,
        }),
        200,
      );
      await Future.wait([
        m.api.pedir('GET', '/profiles'),
        m.api.pedir('GET', '/profiles'),
        m.api.pedir('GET', '/profiles'),
      ]);
      expect(m.servidor.de('POST /auth/refresh'), hasLength(1));
    });

    test(
      'se a renovação falha, a sessão acaba e o erro é "sessao_expirada"',
      () async {
        final m = montar();
        m.sessao.guardar(acesso: 'velho', renovacao: 'renova-1');
        m.servidor.responder('GET /profiles', {'erro': 'nao_autenticado'}, 401);
        m.servidor.responder('POST /auth/refresh', {
          'erro': 'refresh_invalido',
        }, 401);
        await expectLater(
          m.api.pedir('GET', '/profiles'),
          throwsA(
            isA<ErroApi>().having((e) => e.codigo, 'codigo', 'sessao_expirada'),
          ),
        );
        expect(m.sessao.acesso, isNull);
        expect(m.sessao.renovacao, isNull);
      },
    );

    test('um 401 sem token de renovação não tenta renovar', () async {
      final m = montar();
      m.servidor.responder('GET /profiles', {'erro': 'nao_autenticado'}, 401);
      await expectLater(
        m.api.pedir('GET', '/profiles'),
        throwsA(
          isA<ErroApi>().having((e) => e.codigo, 'codigo', 'nao_autenticado'),
        ),
      );
      expect(m.servidor.de('POST /auth/refresh'), isEmpty);
    });

    test(
      'restaurar: com token de renovação válido entra; sem ele, não',
      () async {
        final m = montar();
        expect(await AutenticacaoApi(m.api).restaurar(), isFalse);
        m.sessao.guardar(acesso: 'a', renovacao: 'r');
        m.servidor.responder('GET /auth/me', {
          'utilizador': {'id': 'u1', 'nome': 'Ana'},
        });
        final auth = AutenticacaoApi(m.api);
        expect(await auth.restaurar(), isTrue);
        expect(auth.nome, 'Ana');
      },
    );
  });

  group('Perfis e tomas', () {
    late ({Servidor servidor, ClienteApi api, SessaoMemoria sessao}) m;
    late RepositorioApi repo;
    setUp(() {
      m = montar();
      m.sessao.guardar(acesso: 'a', renovacao: 'r');
      repo = RepositorioApi(m.api);
    });

    test('perfis usa o pseudónimo como nome', () async {
      m.servidor.responder('GET /profiles', {
        'perfis': [
          {'id': 'p1', 'pseudonimo': 'Avó Rosa', 'papel': 'owner'},
        ],
      });
      final l = await repo.perfis();
      expect(
        (l.single.id, l.single.nome, l.single.inicial),
        ('p1', 'Avó Rosa', 'A'),
      );
    });

    test('as tomas de hoje pedem o dia local, em UTC, e traduzem o que o servidor devolve', () async {
      m.servidor.responder('GET /tomas', {
        'tomas': [
          tomaJson(
            't1',
            'tomada',
            tomadaEm: '2026-11-21T08:12:00Z',
            por: 'Ana',
            atualizada: '2026-11-21T08:12:30Z',
          ),
          tomaJson('t2', 'pendente', agendada: '2026-11-21T13:00:00Z'),
        ],
      });
      final agora = DateTime(2026, 11, 21, 13);
      final tomas = await repo.tomasDeHoje('p1', agora);
      final q = m.servidor.de('GET /tomas').single.url.queryParameters;
      expect(DateTime.parse(q['de']!).toLocal(), DateTime(2026, 11, 21));
      expect(DateTime.parse(q['ate']!).toLocal(), DateTime(2026, 11, 22));
      expect(m.servidor.de('GET /tomas').single.headers['x-profile-id'], 'p1');
      expect(tomas, hasLength(2));
      final t1 = tomas.first;
      expect(
        (t1.medicamento, t1.dose, t1.estado, t1.registadaPor),
        ('Lisinopril', '10 mg', EstadoToma.tomada, 'Ana'),
      );
      expect(t1.agendada, DateTime.utc(2026, 11, 21, 9).toLocal());
      expect(t1.tomadaEm, DateTime.utc(2026, 11, 21, 8, 12).toLocal());
      expect(
        t1.registadaEm,
        DateTime.utc(2026, 11, 21, 8, 12, 30).toLocal(),
      ); // serve a janela do "desfazer"
      expect(tomas.last.registadaEm, isNull);
    });

    test('marcar como tomada envia a hora real e uma chave de idempotência nova de cada vez', () async {
      m.servidor.responder('POST /tomas/t1/registo', {
        'estado': 'tomada',
        'repetido': false,
      });
      m.servidor.responder('GET /tomas/t1', {
        'toma': tomaJson('t1', 'tomada', tomadaEm: '2026-11-21T12:00:00Z'),
        'historico7dias': [],
      });
      final hora = DateTime.utc(2026, 11, 21, 12);
      final t = await repo.marcarTomada(
        'p1',
        't1',
        DateTime.utc(2026, 11, 21, 12, 5),
        hora: hora,
      );
      expect(t.estado, EstadoToma.tomada);
      await repo.marcarTomada('p1', 't1', DateTime.utc(2026, 11, 21, 12, 5));
      final enviados = m.servidor
          .de('POST /tomas/t1/registo')
          .map((p) => jsonDecode(p.body) as Map)
          .toList();
      expect(enviados[0]['tomadaEmUtc'], hora.toIso8601String());
      expect(enviados[1].containsKey('tomadaEmUtc'), isFalse);
      expect(enviados[0]['idempotencyKey'], matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(
        enviados[0]['idempotencyKey'],
        isNot(enviados[1]['idempotencyKey']),
      );
      expect(
        m.servidor.de('POST /tomas/t1/registo').first.headers['x-profile-id'],
        'p1',
      );
    });

    test(
      'as recusas do servidor passam a RegistoNaoPermitido com o mesmo código',
      () async {
        for (final codigo in [
          'toma_ja_registada',
          'hora_invalida',
          'desfazer_expirado',
        ]) {
          m.servidor.responder('POST /tomas/t1/registo', {'erro': codigo}, 409);
          m.servidor.responder('POST /tomas/t1/desfazer', {
            'erro': codigo,
          }, 409);
          await expectLater(
            repo.marcarTomada('p1', 't1', DateTime.now()),
            throwsA(
              isA<RegistoNaoPermitido>().having(
                (e) => e.motivo,
                'motivo',
                codigo,
              ),
            ),
          );
          await expectLater(
            repo.desfazer('p1', 't1', DateTime.now()),
            throwsA(isA<RegistoNaoPermitido>()),
          );
        }
      },
    );

    test('um erro de rede ao registar fica como ErroApi (não como recusa de negócio)', () async {
      m.servidor.respostas.clear();
      final semRede = RepositorioApi(
        ClienteApi(
          base: Uri.parse('http://api.teste'),
          sessao: SessaoMemoria(),
          cliente: MockClient((_) async => throw http.ClientException('x')),
        ),
      );
      await expectLater(
        semRede.saltar('p1', 't1', DateTime.now()),
        throwsA(isA<ErroApi>().having((e) => e.codigo, 'codigo', 'sem_rede')),
      );
    });

    test('saltar e desfazer chamam os endpoints certos', () async {
      m.servidor.responder('POST /tomas/t1/saltar', {
        'estado': 'saltada',
        'repetido': false,
      });
      m.servidor.responder('POST /tomas/t1/desfazer', {'estado': 'pendente'});
      m.servidor.responder('GET /tomas/t1', {
        'toma': tomaJson('t1', 'pendente'),
        'historico7dias': [],
      });
      await repo.saltar('p1', 't1', DateTime.now());
      expect(
        (await repo.desfazer('p1', 't1', DateTime.now())).estado,
        EstadoToma.pendente,
      );
      expect(m.servidor.de('POST /tomas/t1/saltar'), hasLength(1));
      expect(m.servidor.de('POST /tomas/t1/desfazer'), hasLength(1));
    });

    test('a adesão dos 7 dias marca como esquecido o dia com tomas por fazer, e hoje como em curso', () async {
      final agora = DateTime(2026, 11, 21, 15);
      String dia(int atras) =>
          DateTime(2026, 11, 21 - atras, 10).toUtc().toIso8601String();
      m.servidor.responder('GET /tomas', {
        'tomas': [
          tomaJson('a', 'tomada', agendada: dia(3)),
          tomaJson('b', 'falhada', agendada: dia(2)),
          tomaJson('c', 'saltada', agendada: dia(1)),
          tomaJson('d', 'pendente', agendada: dia(0)),
        ],
      });
      final dias = await repo.ultimos7Dias('p1', agora);
      expect(dias, hasLength(7));
      expect(dias[6].resultado, ResultadoDia.emCurso);
      expect(
        dias[3].resultado,
        ResultadoDia.tudoTomado,
      ); // 3 dias atrás: tomada
      expect(
        dias[4].resultado,
        ResultadoDia.esquecida,
      ); // 2 dias atrás: falhada
      expect(
        dias[5].resultado,
        ResultadoDia.tudoTomado,
      ); // ontem: saltada conta como resolvida
      expect(dias[0].resultado, ResultadoDia.tudoTomado); // sem tomas
    });

    test(
      'o nome do cuidador vem do contacto; se falhar, não impede ver as tomas',
      () async {
        m.servidor.responder('GET /contacto', {
          'contactos': [
            {'nome': 'Ana', 'telefone': '+351 912 345 678'},
          ],
        });
        expect(await repo.nomeDoCuidador('p1'), 'Ana');
        m.servidor.responder('GET /contacto', {'contactos': []});
        expect(await repo.nomeDoCuidador('p1'), isNull);
        m.servidor.responder('GET /contacto', {'erro': 'erro_interno'}, 500);
        expect(await repo.nomeDoCuidador('p1'), isNull);
      },
    );
  });

  group('Pessoas e receitas (tradução para a API)', () {
    late ({Servidor servidor, ClienteApi api, SessaoMemoria sessao}) m;
    late RepositorioApi repo;
    setUp(() {
      m = montar();
      m.sessao.guardar(acesso: 'a', renovacao: 'r');
      repo = RepositorioApi(m.api);
    });

    test('criar pessoa envia o pseudónimo, as escolhas e a declaração de autorização', () async {
      m.servidor.responder('POST /profiles', {
        'perfil': {'id': 'p9', 'pseudonimo': 'Avó Rosa', 'papel': 'owner'},
      }, 201);
      final p = await repo.criarPessoa(
        const NovaPessoa(
          nome: '  Avó Rosa ',
          alarmesEm: AlarmesEm.cuidador,
          tamanhoTexto: TamanhoTexto.muitoGrande,
        ),
      );
      expect((p.id, p.nome), ('p9', 'Avó Rosa'));
      final corpo =
          jsonDecode(m.servidor.de('POST /profiles').single.body) as Map;
      expect(corpo, {
        'pseudonimo': 'Avó Rosa',
        'tamanhoTexto': 'muito_grande',
        'alarmesEm': 'dispositivo_do_cuidador',
        'autorizacaoDeclarada': true,
      });
    });

    test('as receitas juntam o nome do medicamento, os dias que restam e a validade', () async {
      m.servidor.responder('GET /medicamentos', {
        'medicamentos': [
          {'id': 'm1', 'nome': 'Lisinopril 10 mg', 'notas': null},
        ],
      });
      m.servidor.responder('GET /receitas', {
        'receitas': [
          {
            'id': 'r1',
            'medicamentoId': 'm1',
            'dose': '1 comprimido',
            'ativa': true,
            'horario': {'tipo': 'intervalo', 'intervaloHoras': 8},
            'validaAte': '2027-03-15',
            'unidadesIniciais': 30,
            'stock': {'unidadesRestantes': 4, 'diasRestantes': 1},
          },
          {
            'id': 'r2',
            'medicamentoId': 'm1',
            'dose': '1',
            'ativa': true,
            'horario': {
              'tipo': 'horas_fixas',
              'horasLocais': ['08:00', '20:00'],
            },
            'validaAte': null,
            'unidadesIniciais': null,
            'stock': null,
          },
        ],
      });
      final l = await repo.receitas('p1');
      expect(
        m.servidor.de('GET /receitas').single.headers['x-profile-id'],
        'p1',
      );
      expect(l[0].medicamento, 'Lisinopril 10 mg');
      expect(l[0].horario, 'De 8 em 8 horas');
      expect(l[0].validaAte, DateTime(2027, 3, 15));
      expect((l[0].unidadesRestantes, l[0].diasRestantes), (4, 1));
      expect(l[0].fracaoRestante, closeTo(4 / 30, 1e-9));
      expect(l[1].horario, '08:00, 20:00');
      expect((l[1].diasRestantes, l[1].fracaoRestante), (null, null));
    });

    test(
      'criar receita cria o medicamento e depois a receita em modo assíncrono',
      () async {
        m.servidor.responder('POST /medicamentos', {
          'medicamento': {'id': 'm7', 'nome': 'Ramipril 5 mg'},
        }, 201);
        m.servidor.responder('POST /receitas', {
          'receita': {
            'id': 'r7',
            'medicamentoId': 'm7',
            'dose': '1 comprimido',
            'ativa': true,
            'horario': {'tipo': 'intervalo', 'intervaloHoras': 8},
            'geracao': {'estado': 'a_gerar', 'tomasGeradas': 0},
          },
        }, 202);
        final nova = NovaReceita(
          medicamento: ' Ramipril 5 mg ',
          dose: '1 comprimido',
          frequencia: Frequencia.cadaOitoHoras,
          hora: 8,
          minuto: 0,
          duracao: Duracao.tresMeses,
        );
        final r = await repo.criarReceita(
          'p1',
          nova,
          DateTime(2026, 11, 21, 13),
        );
        expect(
          (r.id, r.medicamento, r.horario),
          ('r7', 'Ramipril 5 mg', 'De 8 em 8 horas'),
        );
        expect(jsonDecode(m.servidor.de('POST /medicamentos').single.body), {
          'nome': 'Ramipril 5 mg',
        });
        final pedido = m.servidor.de('POST /receitas').single;
        expect(pedido.url.queryParameters, {'assincrono': 'true'});
        expect(pedido.headers['x-profile-id'], 'p1');
        final corpo = jsonDecode(pedido.body) as Map;
        expect(corpo['medicamentoId'], 'm7');
        expect(corpo['horario'], {'tipo': 'intervalo', 'intervaloHoras': 8});
      },
    );

    test('o estado da geração traduz as três fases', () async {
      for (final (texto, fase) in [
        ('a_gerar', FaseGeracao.aGerar),
        ('concluida', FaseGeracao.concluida),
        ('falhou', FaseGeracao.falhou),
      ]) {
        m.servidor.responder('GET /receitas/r7/geracao', {
          'estado': texto,
          'tomasGeradas': 90,
          'passos': [],
        });
        final e = await repo.estadoGeracao('p1', 'r7');
        expect((e.fase, e.tomasGeradas), (fase, 90));
      }
    });
  });
}
