import 'package:amparo/dados/repositorio.dart';

import 'apoio/repositorio_memoria.dart';

import 'package:amparo/dominio/modelos.dart';
import 'package:flutter_test/flutter_test.dart';

final sabado13h = DateTime(2026, 11, 21, 13, 0);

void main() {
  group('Toma', () {
    final base = Toma(
      id: 'a',
      medicamento: 'X',
      dose: '1',
      agendada: DateTime(2026, 11, 21, 9),
    );

    test('"atrasada" não é um estado: deriva-se depois da tolerância', () {
      expect(base.atrasada(DateTime(2026, 11, 21, 9, 10)), isFalse);
      expect(base.atrasada(DateTime(2026, 11, 21, 9, 15)), isFalse);
      expect(base.atrasada(DateTime(2026, 11, 21, 9, 16)), isTrue);
    });

    test('só uma toma pendente pode estar atrasada', () {
      final tomada = base.copiarCom(
        estado: EstadoToma.tomada,
        tomadaEm: DateTime(2026, 11, 21, 9, 5),
      );
      expect(tomada.atrasada(DateTime(2026, 11, 21, 23)), isFalse);
    });

    test('desfazer só durante 1 minuto depois do registo', () {
      final registada = base.copiarCom(
        estado: EstadoToma.tomada,
        tomadaEm: sabado13h,
        registadaEm: sabado13h,
      );
      expect(
        registada.podeDesfazer(sabado13h.add(const Duration(seconds: 59))),
        isTrue,
      );
      expect(
        registada.podeDesfazer(sabado13h.add(const Duration(seconds: 61))),
        isFalse,
      );
      expect(base.podeDesfazer(sabado13h), isFalse);
    });
  });

  group('ResumoDia e adesão', () {
    test('conta tomadas, por confirmar (atrasadas) e por tomar', () async {
      final repo = RepositorioMemoria(agora: sabado13h);
      final r = ResumoDia.de(
        await repo.tomasDeHoje('maria', sabado13h),
        sabado13h,
      );
      expect((r.tomadas, r.porConfirmar, r.porTomar, r.total), (1, 1, 2, 4));
    });

    test('a adesão ignora o dia em curso', () async {
      final repo = RepositorioMemoria(agora: sabado13h);
      final dias = await repo.ultimos7Dias('maria', sabado13h);
      expect(dias, hasLength(7));
      expect(dias.last.resultado, ResultadoDia.emCurso);
      expect(percentagemAdesao(dias), 83); // 5 de 6 dias fechados
      expect(
        percentagemAdesao(const []),
        isNull,
      ); // sem histórico não se inventa uma percentagem
      // dias sem tomas não contam: nem como bons nem como maus
      final soSemDados = [
        for (var i = 0; i < 7; i++)
          DiaAdesao(
            dia: DateTime(2026, 11, 15 + i),
            resultado: ResultadoDia.semDados,
          ),
      ];
      expect(percentagemAdesao(soSemDados), isNull);
      final misto = [
        DiaAdesao(
          dia: DateTime(2026, 11, 15),
          resultado: ResultadoDia.semDados,
        ),
        DiaAdesao(
          dia: DateTime(2026, 11, 16),
          resultado: ResultadoDia.tudoTomado,
        ),
        DiaAdesao(
          dia: DateTime(2026, 11, 17),
          resultado: ResultadoDia.esquecida,
        ),
        DiaAdesao(dia: DateTime(2026, 11, 18), resultado: ResultadoDia.emCurso),
      ];
      expect(percentagemAdesao(misto), 50);
    });
  });

  group('RepositorioMemoria (o mesmo contrato que a API)', () {
    late RepositorioMemoria repo;
    setUp(() => repo = RepositorioMemoria(agora: sabado13h));

    test('marcar como tomada guarda a hora real e quem marcou', () async {
      final t = await repo.marcarTomada(
        'maria',
        't2',
        sabado13h,
        hora: DateTime(2026, 11, 21, 12),
        porCuidador: 'Ana',
      );
      expect(t.estado, EstadoToma.tomada);
      expect(t.tomadaEm, DateTime(2026, 11, 21, 12));
      expect(t.registadaPor, 'Ana');
    });

    test('não se regista duas vezes a mesma toma', () async {
      await repo.marcarTomada('maria', 't2', sabado13h);
      expect(
        () => repo.marcarTomada('maria', 't2', sabado13h),
        throwsA(
          isA<RegistoNaoPermitido>().having(
            (e) => e.motivo,
            'motivo',
            'toma_ja_registada',
          ),
        ),
      );
      expect(
        () => repo.saltar('maria', 't2', sabado13h),
        throwsA(isA<RegistoNaoPermitido>()),
      );
    });

    test('recusa uma hora no futuro', () {
      expect(
        () => repo.marcarTomada(
          'maria',
          't2',
          sabado13h,
          hora: sabado13h.add(const Duration(hours: 1)),
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

    test(
      'desfazer volta a pendente dentro de 1 minuto e é recusado depois',
      () async {
        await repo.marcarTomada('maria', 't2', sabado13h);
        final volta = await repo.desfazer(
          'maria',
          't2',
          sabado13h.add(const Duration(seconds: 30)),
        );
        expect(volta.estado, EstadoToma.pendente);
        expect(volta.tomadaEm, isNull);
        await repo.marcarTomada('maria', 't2', sabado13h);
        expect(
          () => repo.desfazer(
            'maria',
            't2',
            sabado13h.add(const Duration(minutes: 2)),
          ),
          throwsA(
            isA<RegistoNaoPermitido>().having(
              (e) => e.motivo,
              'motivo',
              'desfazer_expirado',
            ),
          ),
        );
      },
    );

    test('cada perfil só tem as suas tomas', () async {
      final maria = (await repo.tomasDeHoje(
        'maria',
        sabado13h,
      )).map((t) => t.id);
      final manuel = (await repo.tomasDeHoje(
        'manuel',
        sabado13h,
      )).map((t) => t.id);
      expect(maria.toSet().intersection(manuel.toSet()), isEmpty);
    });
  });

  group('TamanhoTexto', () {
    test('lê o valor da API e cresce do normal ao muito grande', () {
      expect(TamanhoTexto.daApi('normal'), TamanhoTexto.normal);
      expect(TamanhoTexto.daApi('grande'), TamanhoTexto.grande);
      expect(TamanhoTexto.daApi('muito_grande'), TamanhoTexto.muitoGrande);
      expect(TamanhoTexto.daApi(null), TamanhoTexto.normal);
      expect(
        TamanhoTexto.grande.escala,
        greaterThan(TamanhoTexto.normal.escala),
      );
      expect(
        TamanhoTexto.muitoGrande.escala,
        greaterThan(TamanhoTexto.grande.escala),
      );
    });
  });
}
