import 'dart:math' as math;

import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../dominio/modelos.dart';
import '../../estado/hoje_controlador.dart';
import '../../tema/tema.dart';
import '../../tema/tokens.dart';
import '../componentes/base.dart';
import 'sucesso_marcada.dart';

String horaCurta(DateTime d) => DateFormat('HH:mm').format(d);

String dataPorExtenso(DateTime d) {
  final s = DateFormat("EEEE, d 'de' MMMM", 'pt_PT').format(d);
  return s[0].toUpperCase() + s.substring(1);
}

/// "Hoje" do cuidador: resumo do dia, últimos 7 dias e a linha do tempo das tomas.
class CuidadorHoje extends StatelessWidget {
  const CuidadorHoje({
    super.key,
    required this.controlador,
    required this.aoTrocarPerfil,
  });

  final HojeControlador controlador;
  final VoidCallback aoTrocarPerfil;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return ListenableBuilder(
      listenable: controlador,
      builder: (context, _) {
        final agora = controlador.agora;
        return SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text('Hoje', style: Estilos.titulo(t)),
                        ),
                        Text(
                          dataPorExtenso(agora),
                          style: Estilos.subtitulo(t),
                        ),
                      ],
                    ),
                  ),
                  _ChipPerfil(
                    nome: controlador.perfil.nome,
                    inicial: controlador.perfil.inicial,
                    aoTocar: aoTrocarPerfil,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (controlador.aCarregar)
                const Padding(
                  padding: EdgeInsets.only(top: 60),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (controlador.falhouCarregar)
                _Erro(
                  aoTentar: controlador.carregar,
                  semRede: controlador.erro == 'sem_rede',
                )
              else ...[
                _ResumoDia(
                  resumo: controlador.resumo,
                  semana: controlador.semana,
                ),
                const SizedBox(height: 16),
                _LinhaDoTempo(controlador: controlador),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ChipPerfil extends StatelessWidget {
  const _ChipPerfil({
    required this.nome,
    required this.inicial,
    required this.aoTocar,
  });
  final String nome;
  final String inicial;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Semantics(
      button: true,
      label: 'Perfil ativo: $nome. Trocar de perfil',
      excludeSemantics: true,
      child: Material(
        color: t.superficie,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: aoTocar,
          child: Container(
            height: 44,
            padding: const EdgeInsets.fromLTRB(6, 0, 12, 0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: t.sombra,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Avatar(inicial: inicial),
                const SizedBox(width: 8),
                Text(nome, style: Estilos.corpo(t, peso: FontWeight.w700)),
                const SizedBox(width: 4),
                Icon(Icons.expand_more, size: 20, color: t.texto),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Erro extends StatelessWidget {
  const _Erro({required this.aoTentar, this.semRede = false});
  final VoidCallback aoTentar;
  final bool semRede;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Cartao(
      cor: t.mauSuave,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            semRede
                ? 'Sem ligação. Verifique a internet e tente outra vez.'
                : 'Não foi possível carregar as tomas.',
            style: Estilos.corpo(t, peso: FontWeight.w800, cor: t.mauTexto),
          ),
          const SizedBox(height: 12),
          Botao(
            texto: 'Tentar outra vez',
            aoTocar: aoTentar,
            icone: Icons.refresh,
          ),
        ],
      ),
    );
  }
}

class _ResumoDia extends StatelessWidget {
  const _ResumoDia({required this.resumo, required this.semana});
  final ResumoDia resumo;
  final List<DiaAdesao> semana;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final r = resumo;
    return Cartao(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Column(
        children: [
          Row(
            children: [
              Semantics(
                label:
                    '${r.tomadas} tomas feitas, ${r.porConfirmar} por confirmar, ${r.porTomar} por tomar, de ${r.total}',
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: CustomPaint(
                    painter: _AnelPainter(
                      resumo: r,
                      ok: t.ok,
                      aviso: t.aviso,
                      pista: t.superficie2,
                    ),
                    child: Center(
                      child: ExcludeSemantics(
                        child: Text(
                          '${r.tomadas}/${r.total}',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                            color: t.texto,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  children: [
                    _LinhaResumo(
                      selo: Selo(
                        cor: t.ok,
                        icone: Icons.check,
                        corIcone: t.superficie,
                      ),
                      n: r.tomadas,
                      texto: 'tomadas',
                    ),
                    const SizedBox(height: 8),
                    _LinhaResumo(
                      selo: Selo(
                        cor: t.aviso,
                        icone: Icons.priority_high,
                        corIcone: Tokens.sobreAviso,
                      ),
                      n: r.porConfirmar,
                      texto: 'por confirmar',
                    ),
                    const SizedBox(height: 8),
                    _LinhaResumo(
                      selo: Selo(
                        cor: t.superficie2,
                        icone: Icons.schedule,
                        corIcone: t.texto2,
                        contorno: t.linha,
                      ),
                      n: r.porTomar,
                      texto: 'por tomar',
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (semana.isNotEmpty) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: t.linha),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                Text(
                  'Últimos 7 dias',
                  style: Estilos.corpo(t, peso: FontWeight.w700),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: t.okSuave,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '${percentagemAdesao(semana)}% de adesão',
                    style: Estilos.corpo(
                      t,
                      peso: FontWeight.w700,
                      cor: t.okTexto,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [for (final d in semana) _PontoDia(dia: d)],
            ),
          ],
        ],
      ),
    );
  }
}

class _LinhaResumo extends StatelessWidget {
  const _LinhaResumo({
    required this.selo,
    required this.n,
    required this.texto,
  });
  final Widget selo;
  final int n;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Row(
      children: [
        selo,
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$n',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                TextSpan(text: ' $texto'),
              ],
            ),
            style: Estilos.corpo(t),
          ),
        ),
      ],
    );
  }
}

class _PontoDia extends StatelessWidget {
  const _PontoDia({required this.dia});
  final DiaAdesao dia;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final nome = DateFormat('EEEE', 'pt_PT').format(dia.dia);
    return switch (dia.resultado) {
      ResultadoDia.tudoTomado => Semantics(
        label: '$nome: tudo tomado',
        child: Selo(cor: t.ok, icone: Icons.check, corIcone: t.superficie),
      ),
      ResultadoDia.esquecida => Semantics(
        label: '$nome: uma toma esquecida',
        child: Selo(cor: t.mau, icone: Icons.close, corIcone: t.superficie),
      ),
      ResultadoDia.emCurso => Semantics(
        label: '$nome, hoje: em curso',
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: t.aviso, width: 3),
          ),
        ),
      ),
    };
  }
}

class _AnelPainter extends CustomPainter {
  _AnelPainter({
    required this.resumo,
    required this.ok,
    required this.aviso,
    required this.pista,
  });
  final ResumoDia resumo;
  final Color ok;
  final Color aviso;
  final Color pista;

  @override
  void paint(Canvas canvas, Size size) {
    const traco = 8.0;
    final rect = Rect.fromLTWH(
      traco / 2,
      traco / 2,
      size.width - traco,
      size.height - traco,
    );
    Paint p(Color c) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = traco
      ..strokeCap = StrokeCap.round
      ..color = c;
    canvas.drawArc(rect, 0, 2 * math.pi, false, p(pista));
    if (resumo.total == 0) return;
    const inicio = -math.pi / 2;
    final volta = 2 * math.pi;
    final fatiaOk = volta * resumo.tomadas / resumo.total;
    final fatiaAviso = volta * resumo.porConfirmar / resumo.total;
    if (fatiaOk > 0) canvas.drawArc(rect, inicio, fatiaOk - .12, false, p(ok));
    if (fatiaAviso > 0) {
      canvas.drawArc(rect, inicio + fatiaOk, fatiaAviso - .12, false, p(aviso));
    }
  }

  @override
  bool shouldRepaint(_AnelPainter old) =>
      old.resumo.tomadas != resumo.tomadas ||
      old.resumo.porConfirmar != resumo.porConfirmar ||
      old.resumo.porTomar != resumo.porTomar;
}

class _LinhaDoTempo extends StatelessWidget {
  const _LinhaDoTempo({required this.controlador});
  final HojeControlador controlador;

  @override
  Widget build(BuildContext context) {
    final tomas = controlador.tomas;
    if (tomas.isEmpty) {
      final t = context.t;
      return Cartao(child: Text('Hoje não há tomas.', style: Estilos.corpo(t)));
    }
    final proxima = _proxima(tomas, controlador.agora);
    return Semantics(
      container: true,
      label: 'Ao longo do dia',
      child: Column(
        children: [
          for (var i = 0; i < tomas.length; i++)
            _ItemTempo(
              controlador: controlador,
              toma: tomas[i],
              ultima: i == tomas.length - 1,
              proxima: tomas[i].id == proxima?.id,
            ),
        ],
      ),
    );
  }

  /// A próxima toma a tomar (pendente e ainda não atrasada).
  Toma? _proxima(List<Toma> tomas, DateTime agora) {
    for (final t in tomas) {
      if (t.estado == EstadoToma.pendente && !t.atrasada(agora)) return t;
    }
    return null;
  }
}

class _ItemTempo extends StatelessWidget {
  const _ItemTempo({
    required this.controlador,
    required this.toma,
    required this.ultima,
    required this.proxima,
  });
  final HojeControlador controlador;
  final Toma toma;
  final bool ultima;
  final bool proxima;

  Future<void> _marcar(BuildContext context) async {
    final navegador = Navigator.of(context);
    final ok = await controlador.marcarTomada(toma);
    if (!ok) return;
    navegador.push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          body: FundoGradiente(
            child: SucessoMarcadaEcra(
              controlador: controlador,
              tomaId: toma.id,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final agora = controlador.agora;
    final atrasada = toma.atrasada(agora);
    final titulo =
        '${horaCurta(toma.agendada)} · ${toma.medicamento}${toma.dose.isEmpty ? '' : ' ${toma.dose}'}';

    final Widget selo;
    final Widget cartao;
    if (toma.estado == EstadoToma.tomada) {
      selo = Selo(cor: t.ok, icone: Icons.check, corIcone: t.superficie);
      final quem = toma.registadaPor == null
          ? ''
          : ' · Marcada por ${toma.registadaPor}';
      cartao = _CartaoSimples(
        titulo: titulo,
        linha: 'Tomadas às ${horaCurta(toma.tomadaEm ?? toma.agendada)}$quem',
        corLinha: t.okTexto,
      );
    } else if (toma.estado == EstadoToma.saltada) {
      selo = Selo(
        cor: t.superficie2,
        icone: Icons.remove,
        corIcone: t.texto2,
        contorno: t.linha,
      );
      cartao = _CartaoSimples(
        titulo: titulo,
        linha: 'Saltada',
        corLinha: t.texto2,
      );
    } else if (toma.estado == EstadoToma.falhada) {
      selo = Selo(cor: t.mau, icone: Icons.close, corIcone: t.superficie);
      cartao = _CartaoSimples(
        titulo: titulo,
        linha: 'Não foi tomada',
        corLinha: t.mauTexto,
        fundo: t.mauSuave,
      );
    } else if (atrasada) {
      selo = Selo(
        cor: t.aviso,
        icone: Icons.priority_high,
        corIcone: Tokens.sobreAviso,
      );
      final atraso = agora.difference(toma.agendada);
      final ha = atraso.inMinutes >= 120
          ? '${atraso.inHours} h'
          : '${atraso.inMinutes} min';
      cartao = _CartaoAcao(
        toma: toma,
        fundo: t.avisoSuave,
        corTitulo: t.texto,
        corSubtitulo: t.avisoTexto,
        estado: _EstadoToma(
          texto: 'Atrasada há $ha',
          icone: Icons.priority_high,
          fundo: t.aviso,
          cor: Tokens.sobreAviso,
        ),
        corSecundario: t.avisoTexto,
        fundoSecundario: t.aviso.withValues(alpha: .22),
        aoTomar: () => _marcar(context),
        aoSaltar: () => controlador.saltar(toma),
      );
    } else if (proxima) {
      selo = Selo(
        cor: t.primaria,
        icone: Icons.schedule,
        corIcone: t.sobrePrimaria,
      );
      final min = toma.agendada.difference(agora).inMinutes;
      cartao = _CartaoAcao(
        toma: toma,
        fundo: t.heroi,
        corTitulo: t.sobreHeroi,
        corSubtitulo: t.sobreHeroi2,
        estado: _EstadoToma(
          texto: min <= 0 ? 'Agora' : 'Em $min min',
          icone: Icons.schedule,
          fundo: t.primariaSuave,
          cor: t.sobrePrimariaSuave,
        ),
        corSecundario: t.sobreHeroi,
        fundoSecundario: const Color(0x1FFFFFFF),
        aoTomar: () => _marcar(context),
        aoSaltar: () => controlador.saltar(toma),
      );
    } else {
      selo = Selo(
        cor: t.superficie2,
        icone: Icons.schedule,
        corIcone: t.texto2,
        contorno: t.linha,
        tamanho: 24,
      );
      cartao = _CartaoSimples(
        titulo: titulo,
        linha: 'Por tomar',
        corLinha: t.texto2,
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                const SizedBox(height: 12),
                selo,
                if (!ultima)
                  Expanded(child: Container(width: 2, color: t.linha)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: ultima ? 0 : 8),
              child: cartao,
            ),
          ),
        ],
      ),
    );
  }
}

class _CartaoSimples extends StatelessWidget {
  const _CartaoSimples({
    required this.titulo,
    required this.linha,
    required this.corLinha,
    this.fundo,
  });
  final String titulo;
  final String linha;
  final Color corLinha;
  final Color? fundo;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Cartao(
      raio: _raioCartaoToma,
      cor: fundo,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: Estilos.corpo(t, peso: FontWeight.w700)),
            Text(linha, style: Estilos.corpo(t, cor: corLinha)),
          ],
        ),
      ),
    );
  }
}

/// Cantos dos cartões da linha do tempo (menos arredondados do que os 20 do resto da app).
const _raioCartaoToma = 12.0;

class _EstadoToma {
  const _EstadoToma({
    required this.texto,
    required this.icone,
    required this.fundo,
    required this.cor,
  });
  final String texto;
  final IconData icone;
  final Color fundo;
  final Color cor;
}

/// O cartão de uma toma que pede ação (a próxima ou a atrasada): a hora em destaque, o nome do medicamento,
/// o estado à direita e dois botões compactos, "Tomada" e "Saltar".
class _CartaoAcao extends StatelessWidget {
  const _CartaoAcao({
    required this.toma,
    required this.fundo,
    required this.corTitulo,
    required this.corSubtitulo,
    required this.estado,
    required this.corSecundario,
    required this.fundoSecundario,
    required this.aoTomar,
    required this.aoSaltar,
  });
  final Toma toma;
  final Color fundo;
  final Color corTitulo;
  final Color corSubtitulo;
  final _EstadoToma estado;
  final Color corSecundario;
  final Color fundoSecundario;
  final VoidCallback aoTomar;
  final VoidCallback aoSaltar;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final detalhe = [
      if (toma.dose.isNotEmpty) toma.dose,
      if (toma.nota != null) toma.nota!,
    ].join(' · ');
    return Cartao(
      raio: _raioCartaoToma,
      cor: fundo,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                horaCurta(toma.agendada),
                style: TextStyle(
                  fontSize: 20,
                  height: 1.1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: corTitulo,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      toma.medicamento,
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        color: corTitulo,
                      ),
                    ),
                    if (detalhe.isNotEmpty)
                      Text(
                        detalhe,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.3,
                          fontWeight: FontWeight.w500,
                          color: corSubtitulo,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: estado.fundo,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(estado.icone, size: 14, color: estado.cor),
                  const SizedBox(width: 4),
                  Text(
                    estado.texto,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: estado.cor,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _BotaoToma(
                  texto: 'Tomada',
                  descricao: 'Marcar ${toma.medicamento} como tomada',
                  icone: Icons.check,
                  fundo: t.primaria,
                  cor: t.sobrePrimaria,
                  aoTocar: aoTomar,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: _BotaoToma(
                  texto: 'Saltar',
                  descricao: 'Saltar a toma de ${toma.medicamento}',
                  fundo: fundoSecundario,
                  cor: corSecundario,
                  aoTocar: aoSaltar,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Botão compacto (44 px de altura, cantos de 10) dos cartões de toma.
class _BotaoToma extends StatelessWidget {
  const _BotaoToma({
    required this.texto,
    required this.descricao,
    required this.fundo,
    required this.cor,
    required this.aoTocar,
    this.icone,
  });
  final String texto;
  final String descricao;
  final Color fundo;
  final Color cor;
  final VoidCallback aoTocar;
  final IconData? icone;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: descricao,
      excludeSemantics: true,
      child: Material(
        color: fundo,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: aoTocar,
          child: SizedBox(
            height: 44,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icone != null) ...[
                    Icon(icone, size: 18, color: cor),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    texto,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: cor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
