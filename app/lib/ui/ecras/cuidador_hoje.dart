import 'dart:async';
import 'dart:math' as math;

import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../dominio/modelos.dart';
import '../../estado/hoje_controlador.dart';
import '../../tema/tema.dart';
import '../../tema/tokens.dart';
import '../componentes/base.dart';
import '../componentes/estilo.dart';
import '../componentes/icones.dart';
import 'sucesso_marcada.dart';

String horaCurta(DateTime d) => DateFormat('HH:mm').format(d);

String dataPorExtenso(DateTime d) {
  final s = DateFormat("EEEE, d 'de' MMMM", 'pt_PT').format(d);
  return s[0].toUpperCase() + s.substring(1);
}

/// `li:nth-child(n)` do design: cada item de lista entra 0,20 s + 0,07 s por posição, a subir.
Widget itemQueSobe(int posicao, Widget filho) => EntradaSobe(
  atraso: Duration(milliseconds: 200 + 70 * math.min(posicao, 7)),
  duracao: const Duration(milliseconds: 500),
  child: filho,
);

/// A página principal do cuidador: resumo do dia, últimos 7 dias e a linha do tempo das tomas.
/// O relógio anda sozinho (a cada 30 s) para o tempo que falta e os botões das tomas estarem certos.
class CuidadorHoje extends StatefulWidget {
  const CuidadorHoje({
    super.key,
    required this.controlador,
    required this.aoTrocarPerfil,
    this.aoAbrirDetalhe,
    this.aoLigar,
    this.aoLembrar,
  });

  final HojeControlador controlador;
  final VoidCallback aoTrocarPerfil;

  /// Abre o detalhe da toma (a linha com a seta, nas tomas por confirmar).
  final void Function(Toma toma)? aoAbrirDetalhe;

  /// "Ligar" e "Lembrar" da próxima toma. Sem [aoLigar] (a pessoa não tem número) o "Ligar" não aparece;
  /// sem [aoLembrar], o "Lembrar" avisa que ainda não está disponível.
  final void Function(Toma toma)? aoLigar;
  final void Function(Toma toma)? aoLembrar;

  @override
  State<CuidadorHoje> createState() => _CuidadorHojeState();
}

class _CuidadorHojeState extends State<CuidadorHoje> {
  Timer? _relogio;

  @override
  void initState() {
    super.initState();
    _relogio = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _relogio?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final controlador = widget.controlador;
    return ListenableBuilder(
      listenable: controlador,
      builder: (context, _) {
        final agora = controlador.agora;
        final proprio = eProprioCuidador(
          controlador.perfil,
          controlador.cuidador,
        );
        // Como no design, cada bloco da página entra a subir, 0,08 s depois do anterior.
        final blocos = <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  controlador.cuidador == null
                      ? 'Página principal'
                      : 'Olá, ${controlador.cuidador}',
                  style: Estilos.titulo(t),
                ),
              ),
              Text(dataPorExtenso(agora), style: Estilos.subtitulo(t)),
            ],
          ),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 6,
            children: [
              Text(
                proprio ? 'A minha medicação' : 'A cuidar de',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: t.texto2,
                ),
              ),
              _ChipPerfil(
                nome: controlador.perfil.nome,
                aoTocar: widget.aoTrocarPerfil,
              ),
            ],
          ),
          if (controlador.aCarregar)
            const Padding(
              padding: EdgeInsets.only(top: 46),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (controlador.falhouCarregar)
            _Erro(
              aoTentar: controlador.carregar,
              semRede: controlador.erro == 'sem_rede',
            )
          else ...[
            _ResumoDia(resumo: controlador.resumo, semana: controlador.semana),
          ],
        ];
        final carregado = !controlador.aCarregar && !controlador.falhouCarregar;
        // O cabeçalho e o resumo ficam fixos; só a lista de cartões das tomas se desloca.
        return SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: escalonar(blocos, espaco: 14),
                ),
              ),
              if (carregado)
                Expanded(
                  child: _LinhaDoTempo(
                    controlador: controlador,
                    proprio: proprio,
                    aoAbrirDetalhe: widget.aoAbrirDetalhe,
                    aoLigar: widget.aoLigar,
                    aoLembrar: widget.aoLembrar,
                  ),
                )
              else
                const Spacer(),
            ],
          ),
        );
      },
    );
  }
}

class _ChipPerfil extends StatelessWidget {
  const _ChipPerfil({required this.nome, required this.aoTocar});
  final String nome;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Pressionavel(
      child: Semantics(
        button: true,
        label: 'A cuidar de $nome. Trocar de pessoa',
        excludeSemantics: true,
        child: Material(
          color: t.primariaSuave,
          shape: StadiumBorder(side: BorderSide(color: t.primaria, width: 2)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: aoTocar,
            child: Container(
              height: 40,
              padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    nome,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: t.sobrePrimariaSuave,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icone(
                    Icones.setaBaixo,
                    tamanho: 20,
                    cor: t.sobrePrimariaSuave,
                    traco: 2.2,
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

class _Erro extends StatelessWidget {
  const _Erro({required this.aoTentar, this.semRede = false});
  final VoidCallback aoTentar;
  final bool semRede;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Cartao(
      raio: 5,
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

/// "1 tomada" / "3 tomadas".
String _tomadas(int n) => '$n ${n == 1 ? 'tomada' : 'tomadas'}';

/// O resumo do dia, compacto: o anel (quantas já foram), uma frase com o que falta e os últimos 7 dias
/// com a inicial de cada dia.
class _ResumoDia extends StatelessWidget {
  const _ResumoDia({required this.resumo, required this.semana});
  final ResumoDia resumo;
  final List<DiaAdesao> semana;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final r = resumo;
    final visiveis = semana
        .skipWhile((d) => d.resultado == ResultadoDia.semDados)
        .toList();
    final faltas = <InlineSpan>[
      if (r.porConfirmar > 0)
        TextSpan(
          text: '${r.porConfirmar} por confirmar',
          style: TextStyle(color: t.avisoTexto, fontWeight: FontWeight.w800),
        ),
      if (r.porConfirmar > 0 && r.porTomar > 0) const TextSpan(text: '  ·  '),
      if (r.porTomar > 0) TextSpan(text: '${r.porTomar} por tomar'),
    ];
    return Cartao(
      raio: 5,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Semantics(
        container: true,
        label: 'Resumo do dia',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Semantics(
                  label:
                      '${r.tomadas} tomas feitas, ${r.porConfirmar} por confirmar, ${r.porTomar} por tomar, de ${r.total}',
                  child: SizedBox(
                    width: 84,
                    height: 84,
                    child: AnimarComAtraso(
                      atraso: const Duration(milliseconds: 300),
                      duracao: const Duration(seconds: 1),
                      builder: (context, progresso) => CustomPaint(
                        painter: _AnelPainter(
                          resumo: r,
                          ok: t.ok,
                          aviso: t.aviso,
                          pista: t.superficie2,
                          progresso: progresso,
                        ),
                        child: Center(
                          child: ExcludeSemantics(
                            child: Text(
                              '${r.tomadas}/${r.total}',
                              style: TextStyle(
                                fontSize: 22,
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
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: itemQueSobe(
                    0,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.total > 0 && r.tomadas == r.total
                              ? 'Tudo tomado'
                              : _tomadas(r.tomadas),
                          style: TextStyle(
                            fontSize: 18,
                            height: 1.2,
                            fontWeight: FontWeight.w800,
                            color: r.tomadas > 0 ? t.okTexto : t.texto,
                          ),
                        ),
                        if (faltas.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text.rich(
                            TextSpan(children: faltas),
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                              color: t.texto2,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: t.linha)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          'Últimos 7 dias',
                          style: Estilos.corpo(
                            t,
                            peso: FontWeight.w700,
                            altura: 1.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (percentagemAdesao(semana) case final p?)
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: t.okSuave,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              '$p% de adesão',
                              style: Estilos.corpo(
                                t,
                                peso: FontWeight.w700,
                                cor: t.okTexto,
                                altura: 1.5,
                              ),
                            ),
                          ),
                        )
                      else
                        Flexible(
                          child: Text(
                            'Ainda sem histórico',
                            textAlign: TextAlign.end,
                            style: Estilos.corpo(
                              t,
                              peso: FontWeight.w500,
                              cor: t.texto2,
                              altura: 1.5,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Sete colunas iguais, cada uma com a bolinha e a inicial do dia por baixo. Numa conta
                  // nova só há os dias que existem, encostados à esquerda: os de antes não são "vazios".
                  Row(
                    mainAxisAlignment: visiveis.length == 7
                        ? MainAxisAlignment.spaceBetween
                        : MainAxisAlignment.start,
                    children: [
                      for (final (i, d) in visiveis.indexed) ...[
                        if (i > 0 && visiveis.length != 7)
                          const SizedBox(width: 18),
                        if (visiveis.length == 7)
                          Expanded(
                            child: Center(
                              child: itemQueSobe(
                                i,
                                _PontoDia(
                                  key: ValueKey('ponto-dia-${d.dia.day}'),
                                  dia: d,
                                ),
                              ),
                            ),
                          )
                        else
                          itemQueSobe(
                            i,
                            _PontoDia(
                              key: ValueKey('ponto-dia-${d.dia.day}'),
                              dia: d,
                            ),
                          ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Um dia dos últimos 7: a bolinha do resultado e, por baixo, a inicial do dia ("S", "T", "Q"...).
/// Hoje (em curso) é um contorno neutro com a inicial a negrito, não um aviso.
class _PontoDia extends StatelessWidget {
  const _PontoDia({super.key, required this.dia});
  final DiaAdesao dia;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final nome = DateFormat('EEEE', 'pt_PT').format(dia.dia);
    final inicial = nome.substring(0, 1).toUpperCase();
    final hoje = dia.resultado == ResultadoDia.emCurso;
    final (rotulo, Widget ponto) = switch (dia.resultado) {
      ResultadoDia.tudoTomado => (
        '$nome: tudo tomado',
        SeloIcone(cor: t.ok, dados: Icones.visto, corIcone: t.superficie),
      ),
      ResultadoDia.esquecida => (
        '$nome: uma toma esquecida',
        SeloIcone(cor: t.mau, dados: Icones.x, corIcone: t.superficie),
      ),
      ResultadoDia.semDados => (
        '$nome: sem registos',
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: t.superficie2,
            border: Border.all(color: t.linha),
          ),
        ),
      ),
      ResultadoDia.emCurso => (
        '$nome, hoje: em curso',
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: t.texto2, width: 2.5),
          ),
        ),
      ),
    };
    return Semantics(
      label: rotulo,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ponto,
          const SizedBox(height: 3),
          Text(
            inicial,
            style: TextStyle(
              fontSize: 12,
              height: 1.2,
              fontWeight: hoje ? FontWeight.w800 : FontWeight.w600,
              color: hoje ? t.texto : t.texto2,
            ),
          ),
        ],
      ),
    );
  }
}

/// O anel do resumo: o do design (viewBox 108, raio 44, traço 11, pontas redondas), em 72 px.
class _AnelPainter extends CustomPainter {
  _AnelPainter({
    required this.resumo,
    required this.ok,
    required this.aviso,
    required this.pista,
    this.progresso = 1,
  });
  final ResumoDia resumo;
  final Color ok;
  final Color aviso;
  final Color pista;

  /// 0 a 1: o anel desenha-se da esquerda para a direita (`@keyframes mRing`, de `0 276.5`).
  final double progresso;

  @override
  void paint(Canvas canvas, Size size) {
    const volta = 276.5; // 2π · 44, a unidade dos `stroke-dasharray` do design
    final escala = size.width / 108;
    final raio = 44 * escala;
    final centro = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: centro, radius: raio);
    Paint p(Color c) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11 * escala
      ..strokeCap = StrokeCap.round
      ..color = c;
    canvas.drawCircle(centro, raio, p(pista)..strokeCap = StrokeCap.butt);
    if (resumo.total == 0) return;
    // Unidades do `stroke-dasharray`: o arco começa em `inicio` e tem `comprimento`.
    void arco(double inicio, double comprimento, Color cor) {
      if (comprimento <= 0) return;
      canvas.drawArc(
        rect,
        -math.pi / 2 + inicio / volta * 2 * math.pi,
        comprimento / volta * 2 * math.pi,
        false,
        p(cor),
      );
    }

    final fatiaOk = volta * resumo.tomadas / resumo.total;
    final fatiaAviso = volta * resumo.porConfirmar / resumo.total;
    // Com 2/5 tomadas e 1 por confirmar o design usa "104 172.5" e "44 232.5" com desvio 110:
    // cada arco é a sua fatia menos o espaço das pontas redondas.
    if (fatiaOk > 0) arco(0, (fatiaOk - 6.6) * progresso, ok);
    if (fatiaAviso > 0) {
      arco(fatiaOk - .6, (fatiaAviso - 11.3) * progresso, aviso);
    }
  }

  @override
  bool shouldRepaint(_AnelPainter old) =>
      old.progresso != progresso ||
      old.resumo.tomadas != resumo.tomadas ||
      old.resumo.porConfirmar != resumo.porConfirmar ||
      old.resumo.porTomar != resumo.porTomar;
}

class _LinhaDoTempo extends StatelessWidget {
  const _LinhaDoTempo({
    required this.controlador,
    required this.proprio,
    required this.aoAbrirDetalhe,
    required this.aoLigar,
    required this.aoLembrar,
  });
  final HojeControlador controlador;
  final bool proprio;
  final void Function(Toma toma)? aoAbrirDetalhe;
  final void Function(Toma toma)? aoLigar;
  final void Function(Toma toma)? aoLembrar;

  @override
  Widget build(BuildContext context) {
    final tomas = controlador.tomas;
    if (tomas.isEmpty) {
      final t = context.t;
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 108),
        children: [
          Cartao(
            raio: 5,
            child: Text('Hoje não há tomas.', style: Estilos.corpo(t)),
          ),
        ],
      );
    }
    final proxima = _proxima(tomas, controlador.agora);
    return Semantics(
      container: true,
      label: 'Ao longo do dia',
      // Os cards esbatem-se ao chegar ao resumo (em vez de serem cortados a direito): só o topo da lista.
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (r) => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [Color(0x00000000), Color(0xFF000000)],
          stops: [0, r.height <= 0 ? 1 : (30 / r.height).clamp(0.0, 1.0)],
        ).createShader(r),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 108),
          children: [
            for (var i = 0; i < tomas.length; i++)
              itemQueSobe(
                i,
                _ItemTempo(
                  controlador: controlador,
                  proprio: proprio,
                  toma: tomas[i],
                  ultima: i == tomas.length - 1,
                  proxima: tomas[i].id == proxima?.id,
                  aoAbrirDetalhe: aoAbrirDetalhe,
                  aoLigar: aoLigar,
                  aoLembrar: aoLembrar,
                ),
              ),
          ],
        ),
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

/// Quanto falta para a hora da toma, arredondado para cima ("agora", "10 min", "2 h", "5 h 22 min").
String tempoQueFalta(DateTime agendada, DateTime agora) {
  final min = (agendada.difference(agora).inSeconds / 60).ceil();
  if (min <= 0) return 'agora';
  if (min < 60) return '$min min';
  final h = min ~/ 60;
  final resto = min % 60;
  return resto == 0 ? '$h h' : '$h h $resto min';
}

/// Só a partir de 5 minutos antes da hora da toma é que aparecem os botões.
const antecedenciaBotoes = Duration(minutes: 5);

class _ItemTempo extends StatelessWidget {
  const _ItemTempo({
    required this.controlador,
    required this.proprio,
    required this.toma,
    required this.ultima,
    required this.proxima,
    required this.aoAbrirDetalhe,
    required this.aoLigar,
    required this.aoLembrar,
  });
  final HojeControlador controlador;
  final bool proprio;
  final Toma toma;
  final bool ultima;
  final bool proxima;
  final void Function(Toma toma)? aoAbrirDetalhe;
  final void Function(Toma toma)? aoLigar;
  final void Function(Toma toma)? aoLembrar;

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

  void _emBreve(BuildContext context, String o) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text('$o ainda não está disponível.')));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final agora = controlador.agora;
    final atrasada = toma.atrasada(agora);
    final nome = controlador.perfil.nome;
    final hora = horaCurta(toma.agendada);
    final detalhe = [
      if (toma.dose.isNotEmpty) toma.dose,
      if (toma.nota != null) toma.nota!,
    ].join(' · ');
    final icone = iconeDoTipo(toma.dose);
    final faltam = tempoQueFalta(toma.agendada, agora);
    final textoConfirmar = proprio
        ? 'Confirmar que tomei'
        : 'Confirmar que $nome tomou';

    final Widget selo;
    final Widget cartao;
    if (toma.estado == EstadoToma.tomada) {
      selo = SeloIcone(cor: t.ok, dados: Icones.visto, corIcone: t.superficie);
      // "Marcada por Ana" só faz sentido quando quem marcou não é a própria pessoa.
      final quem = toma.registadaPor == null || proprio
          ? ''
          : ' · Marcada por ${toma.registadaPor}';
      cartao = _CartaoToma(
        medicamento: toma.medicamento,
        detalhe: detalhe,
        hora: hora,
        icone: Icones.visto,
        fundo: t.okSuave,
        corTile: t.ok,
        corIcone: t.superficie,
        corTexto: t.okTexto,
        linha: 'Tomada às ${horaCurta(toma.tomadaEm ?? toma.agendada)}$quem',
      );
    } else if (toma.estado == EstadoToma.saltada) {
      selo = SeloIcone(
        cor: t.superficie2,
        dados: const IconeDados('<path d="M7 12h10"/>'),
        corIcone: t.texto2,
        contorno: t.linha,
        tamanhoIcone: 14,
        traco: 2.6,
      );
      cartao = _CartaoToma(
        medicamento: toma.medicamento,
        detalhe: detalhe,
        hora: hora,
        icone: icone,
        fundo: t.superficie,
        corTile: t.superficie2,
        corIcone: t.texto2,
        linha: 'Saltada',
        corLinha: t.texto2,
        apagada: true,
      );
    } else if (toma.estado == EstadoToma.falhada) {
      selo = SeloIcone(cor: t.mau, dados: Icones.x, corIcone: t.superficie);
      cartao = _CartaoToma(
        medicamento: toma.medicamento,
        detalhe: detalhe,
        hora: hora,
        icone: Icones.x,
        fundo: t.mauSuave,
        corTile: t.mau,
        corIcone: t.superficie,
        corTexto: t.mauTexto,
        linha: 'Não foi tomada',
      );
    } else if (atrasada) {
      selo = SeloIcone(
        cor: t.aviso,
        dados: Icones.alerta,
        corIcone: Tokens.sobreAviso,
      );
      cartao = _CartaoToma(
        medicamento: toma.medicamento,
        detalhe: detalhe,
        hora: hora,
        icone: Icones.alerta,
        fundo: t.avisoSuave,
        corTile: t.aviso,
        corIcone: Tokens.sobreAviso,
        corTexto: t.avisoTexto,
        linha: 'Por confirmar',
        aoAbrirDetalhe: aoAbrirDetalhe == null
            ? null
            : () => aoAbrirDetalhe!(toma),
        botoes: [
          _BotaoToma(
            texto: textoConfirmar,
            icone: Icones.visto,
            tracoIcone: 2.4,
            fundo: t.primaria,
            cor: t.sobrePrimaria,
            peso: FontWeight.w700,
            aoTocar: () => _marcar(context),
          ),
        ],
      );
    } else if (proxima) {
      selo = SeloIcone(
        cor: t.primaria,
        dados: Icones.relogio,
        corIcone: t.sobrePrimaria,
        traco: 2.6,
      );
      // Os botões só aparecem quando a hora está a chegar (5 min antes) ou já chegou.
      final naHora = toma.agendada.difference(agora) <= antecedenciaBotoes;
      cartao = _CartaoToma(
        medicamento: toma.medicamento,
        detalhe: detalhe,
        hora: hora,
        icone: icone,
        pisca: true,
        fundo: t.superficie,
        corTile: t.primariaSuave,
        corIcone: t.sobrePrimariaSuave,
        linha: naHora ? 'É a hora desta toma' : 'Faltam $faltam',
        corLinha: t.primaria,
        botoes: !naHora
            ? const []
            : [
                _BotaoToma(
                  texto: textoConfirmar,
                  icone: Icones.visto,
                  tracoIcone: 2.4,
                  fundo: t.primaria,
                  cor: t.sobrePrimaria,
                  peso: FontWeight.w700,
                  aoTocar: () => _marcar(context),
                ),
                if (!proprio)
                  Row(
                    children: [
                      // Sem o número da pessoa (Mais › "Número da Rosa") não há a quem ligar.
                      if (aoLigar != null) ...[
                        Expanded(
                          child: _BotaoToma(
                            texto: 'Ligar a $nome',
                            icone: Icones.telefone,
                            tracoIcone: 2,
                            fundo: t.primariaSuave,
                            cor: t.sobrePrimariaSuave,
                            peso: FontWeight.w800,
                            aoTocar: () => aoLigar!(toma),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: _BotaoToma(
                          texto: 'Lembrar $nome',
                          icone: Icones.sino,
                          tracoIcone: 2,
                          fundo: Colors.transparent,
                          cor: t.texto,
                          contorno: t.linha,
                          peso: FontWeight.w700,
                          aoTocar: () => aoLembrar != null
                              ? aoLembrar!(toma)
                              : _emBreve(context, 'O lembrete'),
                        ),
                      ),
                    ],
                  ),
              ],
      );
    } else {
      selo = SeloIcone(
        cor: t.superficie2,
        dados: Icones.relogio,
        corIcone: t.texto2,
        contorno: t.linha,
        tamanhoIcone: 14,
        traco: 2.6,
      );
      cartao = _CartaoToma(
        medicamento: toma.medicamento,
        detalhe: detalhe,
        hora: hora,
        icone: icone,
        fundo: t.superficie,
        corTile: t.primariaSuave,
        corIcone: t.sobrePrimariaSuave,
        linha: 'Por tomar · faltam $faltam',
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
                const SizedBox(height: 18),
                selo,
                if (!ultima)
                  Expanded(child: Container(width: 2, color: t.linha)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: ultima ? 0 : 10),
              child: cartao,
            ),
          ),
        ],
      ),
    );
  }
}

/// O cartão de uma toma: quadrado com o ícone do tipo de medicação, nome e dose, a hora numa cápsula
/// e, por baixo, o estado (e os botões, quando já faz sentido tocar).
class _CartaoToma extends StatelessWidget {
  const _CartaoToma({
    required this.medicamento,
    required this.detalhe,
    required this.hora,
    required this.icone,
    required this.fundo,
    required this.corTile,
    required this.corIcone,
    required this.linha,
    this.corTexto,
    this.corLinha,
    this.pisca = false,
    this.apagada = false,
    this.botoes = const [],
    this.aoAbrirDetalhe,
  });
  final String medicamento;
  final String detalhe;
  final String hora;
  final IconeDados icone;
  final Color fundo;
  final Color corTile;
  final Color corIcone;
  final String linha;
  final Color? corTexto;
  final Color? corLinha;

  /// O contorno verde pisca devagar (a próxima toma a tomar).
  final bool pisca;
  final bool apagada;
  final List<Widget> botoes;
  final VoidCallback? aoAbrirDetalhe;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final texto = corTexto ?? t.texto;
    final cabecalho = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: corTile,
            borderRadius: BorderRadius.circular(16),
          ),
          child: ExcludeSemantics(
            child: Icone(icone, tamanho: 26, cor: corIcone, traco: 2.2),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                medicamento,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.2,
                  fontWeight: FontWeight.w800,
                  color: apagada ? t.texto2 : texto,
                ),
              ),
              if (detalhe.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  detalhe,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: t.texto2,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          hora,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: texto,
          ),
        ),
        if (aoAbrirDetalhe != null) ...[
          const SizedBox(width: 6),
          Icone(Icones.setaDireita, tamanho: 22, cor: texto),
        ],
      ],
    );
    final cartao = Cartao(
      raio: 5,
      cor: fundo,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            button: aoAbrirDetalhe != null,
            label: '$hora, $medicamento $detalhe. $linha',
            excludeSemantics: true,
            child: InkWell(onTap: aoAbrirDetalhe, child: cabecalho),
          ),
          const SizedBox(height: 10),
          Text(
            linha,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: corLinha ?? corTexto ?? t.texto2,
            ),
          ),
          for (final b in botoes) ...[const SizedBox(height: 8), b],
        ],
      ),
    );
    return pisca
        ? _ContornoQuePisca(raio: 5, cor: t.primaria, child: cartao)
        : cartao;
  }
}

/// Um contorno que respira: a opacidade sobe e desce devagar (2,6 s por ciclo, `ease-in-out`). Com "reduzir
/// movimento" fica fixo e visível.
class _ContornoQuePisca extends StatefulWidget {
  const _ContornoQuePisca({
    required this.raio,
    required this.cor,
    required this.child,
  });
  final double raio;
  final Color cor;
  final Widget child;

  @override
  State<_ContornoQuePisca> createState() => _ContornoQuePiscaState();
}

class _ContornoQuePiscaState extends State<_ContornoQuePisca>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );
  bool _iniciada = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_iniciada) return;
    _iniciada = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
    } else {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) => DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(widget.raio),
                    border: Border.all(
                      width: 2.5,
                      color: widget.cor.withValues(
                        alpha: .15 + .85 * Curves.easeInOut.transform(_c.value),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Botão dos cartões de toma do design: 44 px de altura, cantos de 16, texto de 15 px.
class _BotaoToma extends StatelessWidget {
  const _BotaoToma({
    required this.texto,
    required this.icone,
    required this.tracoIcone,
    required this.fundo,
    required this.cor,
    required this.peso,
    required this.aoTocar,
    this.contorno,
  });
  final String texto;
  final IconeDados icone;
  final double tracoIcone;
  final Color fundo;
  final Color cor;
  final FontWeight peso;
  final VoidCallback aoTocar;
  final Color? contorno;

  @override
  Widget build(BuildContext context) {
    return Pressionavel(
      child: Semantics(
        button: true,
        label: texto,
        excludeSemantics: true,
        child: Material(
          color: fundo,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: contorno == null
                ? BorderSide.none
                : BorderSide(color: contorno!, width: 2),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: aoTocar,
            child: SizedBox(
              height: 44,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icone(icone, tamanho: 20, cor: cor, traco: tracoIcone),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        texto,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: peso,
                          color: cor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
