import 'package:material_ui/material_ui.dart';

import '../../dominio/modelos.dart';
import '../../estado/hoje_controlador.dart';
import '../../tema/tema.dart';
import '../../tema/tokens.dart';
import '../componentes/base.dart';
import 'cuidador_hoje.dart';

/// "Hoje" no modo simples: a toma atrasada ou a próxima em destaque, botões grandes, o resto mais abaixo.
/// É o único modo no telemóvel de uma pessoa ligada por código (e a pré-visualização "ver como a pessoa vê").
class IdosoHoje extends StatelessWidget {
  const IdosoHoje({super.key, required this.controlador, this.aoLigar});

  final HojeControlador controlador;

  /// Ligar ao cuidador (a chamada em si depende do telemóvel).
  final void Function(String nome)? aoLigar;

  String _saudacao(int hora) =>
      hora < 12 ? 'Bom dia' : (hora < 20 ? 'Boa tarde' : 'Boa noite');

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return ListenableBuilder(
      listenable: controlador,
      builder: (context, _) {
        final agora = controlador.agora;
        final r = controlador.resumo;
        final destaque = controlador.emDestaque;
        final depois = controlador.tomas
            .where(
              (x) => x.estado == EstadoToma.pendente && x.id != destaque?.id,
            )
            .toList();
        final cuidador = controlador.nomeCuidador;
        return SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            '${_saudacao(agora.hour)}, ${controlador.perfil.nome}',
                            style: TextStyle(
                              fontSize: 22,
                              height: 1.15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.44,
                              color: t.texto,
                            ),
                          ),
                        ),
                        Text(
                          dataPorExtenso(agora),
                          style: Estilos.subtitulo(t),
                        ),
                      ],
                    ),
                  ),
                  Avatar(inicial: controlador.perfil.inicial, tamanho: 48),
                ],
              ),
              const SizedBox(height: 18),
              _Progresso(feitas: r.tomadas, total: r.total),
              const SizedBox(height: 18),
              if (destaque != null)
                _CartaoDestaque(
                  controlador: controlador,
                  toma: destaque,
                  cuidador: cuidador,
                )
              else
                _TudoFeito(total: r.total),
              if (depois.isNotEmpty) ...[
                const SizedBox(height: 18),
                _MaisTarde(tomas: depois, agora: agora),
              ],
              if (cuidador != null && aoLigar != null) ...[
                const SizedBox(height: 18),
                Material(
                  color: t.superficie,
                  borderRadius: BorderRadius.circular(22),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: () => aoLigar!(cuidador),
                    child: Container(
                      height: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: t.sombra,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Avatar(
                            inicial: cuidador.substring(0, 1).toUpperCase(),
                            tamanho: 36,
                            coral: true,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Ligar à $cuidador',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: t.texto,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Progresso extends StatelessWidget {
  const _Progresso({required this.feitas, required this.total});
  final int feitas;
  final int total;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$feitas de $total tomas feitas',
          style: Estilos.corpo(t, peso: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        ExcludeSemantics(
          child: Row(
            children: [
              for (var i = 0; i < total; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: i < feitas ? t.primaria : t.superficie2,
                      borderRadius: BorderRadius.circular(5),
                      border: i < feitas ? null : Border.all(color: t.linha),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _CartaoDestaque extends StatelessWidget {
  const _CartaoDestaque({
    required this.controlador,
    required this.toma,
    required this.cuidador,
  });
  final HojeControlador controlador;
  final Toma toma;
  final String? cuidador;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final agora = controlador.agora;
    final atrasada = toma.atrasada(agora);
    final fundo = atrasada ? t.avisoSuave : t.primariaSuave;
    final corTexto = atrasada ? t.avisoTexto : t.sobrePrimariaSuave;
    final horas = agora.difference(toma.agendada);
    final ha = horas.inMinutes >= 120
        ? 'há ${horas.inHours} h'
        : 'há ${horas.inMinutes} min';

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: fundo,
        borderRadius: BorderRadius.circular(32),
        boxShadow: t.sombra,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    if (atrasada) ...[
                      Selo(
                        cor: t.aviso,
                        icone: Icons.priority_high,
                        corIcone: Tokens.sobreAviso,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        atrasada
                            ? 'Atrasada desde as ${horaCurta(toma.agendada)}'
                            : 'Próxima toma, às ${horaCurta(toma.agendada)}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: corTexto,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (atrasada)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: t.aviso,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    ha,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Tokens.sobreAviso,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFFFF),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(
                  Icons.medication,
                  size: 36,
                  color: Color(0xFF0F766E),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      toma.medicamento,
                      style: TextStyle(
                        fontSize: 22,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        color: t.texto,
                      ),
                    ),
                    Text(
                      [
                        if (toma.dose.isNotEmpty) toma.dose,
                        if (toma.nota != null) toma.nota!,
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: corTexto,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: Botao(
                  texto: 'Tomei',
                  icone: Icons.check,
                  altura: 64,
                  raio: 22,
                  tamanhoTexto: 18,
                  aoTocar: () => _marcar(context, toma),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Botao(
                  texto: 'Saltar',
                  altura: 64,
                  raio: 22,
                  tamanhoTexto: 16,
                  fundo: Colors.transparent,
                  cor: corTexto,
                  contorno: atrasada ? t.aviso : t.primaria,
                  aoTocar: () => controlador.saltar(toma),
                ),
              ),
            ],
          ),
          if (atrasada) ...[
            const SizedBox(height: 16),
            Text(
              'Não tome em dobro.${cuidador == null ? '' : ' Se tiver dúvidas, ligue à $cuidador.'}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: corTexto,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _marcar(BuildContext context, Toma toma) async {
    final mensagens = ScaffoldMessenger.maybeOf(context);
    final ok = await controlador.marcarTomada(toma);
    if (!ok) return;
    // "Desfazer" durante 1 minuto, como no plano.
    mensagens?.hideCurrentSnackBar();
    mensagens?.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Text('${toma.medicamento} marcada como tomada.'),
        action: SnackBarAction(
          label: 'Desfazer',
          onPressed: () => controlador.desfazer(toma),
        ),
      ),
    );
  }
}

class _TudoFeito extends StatelessWidget {
  const _TudoFeito({required this.total});
  final int total;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: t.okSuave,
        borderRadius: BorderRadius.circular(32),
        boxShadow: t.sombra,
      ),
      child: Row(
        children: [
          Selo(
            cor: t.ok,
            icone: Icons.check,
            corIcone: t.superficie,
            tamanho: 40,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              total == 0
                  ? 'Hoje não há tomas.'
                  : 'Está tudo feito por hoje. Obrigado!',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: t.okTexto,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MaisTarde extends StatelessWidget {
  const _MaisTarde({required this.tomas, required this.agora});
  final List<Toma> tomas;
  final DateTime agora;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Cartao(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              'Mais tarde hoje',
              style: Estilos.corpo(t, peso: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 4),
          for (var i = 0; i < tomas.length; i++)
            Container(
              constraints: const BoxConstraints(minHeight: 60),
              decoration: BoxDecoration(
                border: i == 0 ? null : Border(top: BorderSide(color: t.linha)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 52,
                    child: Text(
                      horaCurta(tomas[i].agendada),
                      style: Estilos.corpo(
                        t,
                        peso: FontWeight.w700,
                        cor: t.texto2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      tomas[i].medicamento,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: t.texto,
                      ),
                    ),
                  ),
                  _Quando(toma: tomas[i], agora: agora),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Quando extends StatelessWidget {
  const _Quando({required this.toma, required this.agora});
  final Toma toma;
  final DateTime agora;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final min = toma.agendada.difference(agora).inMinutes;
    if (min >= 0 && min <= 60) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: t.primariaSuave,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          min == 0 ? 'Agora' : 'Em $min min',
          style: Estilos.corpo(
            t,
            peso: FontWeight.w700,
            cor: t.sobrePrimariaSuave,
          ),
        ),
      );
    }
    return Text('Por tomar', style: Estilos.corpo(t, cor: t.texto2));
  }
}
