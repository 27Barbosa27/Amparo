import 'dart:math' as math;

import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

import '../../dados/api.dart';
import '../../dados/corpo_receita.dart';
import '../../dados/repositorio.dart';
import '../../dominio/modelos.dart';
import '../../tema/tokens.dart';
import '../componentes/animacao.dart';
import '../componentes/base.dart';
import '../componentes/estilo.dart';
import '../componentes/formulario.dart';
import '../componentes/icones.dart';
import '../componentes/resultado.dart';

/// O fluxo do design: Adicionar receita → A criar as tomas → Receita criada (ou erro ao guardar).
class FluxoReceita {
  FluxoReceita({
    required this.repositorio,
    required this.perfil,
    required this.relogio,
    required this.aoVerHoje,
    this.aoCriada,
    this.agendarAlarmes,
    this.intervaloDeConsulta = const Duration(milliseconds: 500),
  });

  final Repositorio repositorio;
  final Perfil perfil;
  final DateTime Function() relogio;

  /// Quando os alarmes desta pessoa tocam neste telemóvel: recarrega as tomas e agenda-os. Nulo quando
  /// tocam no telemóvel da pessoa (ou neste não há alarmes), e o passo "Agendar os alarmes" não aparece.
  final Future<void> Function()? agendarAlarmes;

  /// O cuidador escolheu "Ver página principal": quem chamou volta a ela e recarrega.
  final VoidCallback aoVerHoje;

  /// A receita ficou criada (as tomas geradas): quem chamou recarrega as listas.
  final VoidCallback? aoCriada;
  final Duration intervaloDeConsulta;

  void abrir(BuildContext context) =>
      Navigator.of(context).push(rotaPagina<void>(_formulario()));

  Widget _formulario() => ReceitaNovaEcra(
    perfil: perfil,
    aoContinuar: (c, nova) => Navigator.of(c).pushReplacement(
      rotaPagina<void>(
        CarregarReceitaEcra(
          repositorio: repositorio,
          perfil: perfil,
          nova: nova,
          relogio: relogio,
          intervalo: intervaloDeConsulta,
          agendarAlarmes: agendarAlarmes,
          aoConcluir: (c2, r) {
            aoCriada?.call();
            Navigator.of(c2).pushReplacement(
              rotaPagina<void>(
                SucessoReceitaEcra(
                  nova: nova,
                  agora: relogio(),
                  aoVerHoje: (c3) {
                    Navigator.of(c3).popUntil((rota) => rota.isFirst);
                    aoVerHoje();
                  },
                  aoOutra: (c3) =>
                      Navigator.of(c3)
                          .pushReplacement(rotaPagina<void>(_formulario())),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}

/// "Adicionar receita" (design: Receita-Nova).
class ReceitaNovaEcra extends StatefulWidget {
  const ReceitaNovaEcra({
    super.key,
    required this.perfil,
    required this.aoContinuar,
    this.editar,
  });
  final Perfil perfil;
  final void Function(BuildContext, NovaReceita) aoContinuar;

  /// Uma receita que já existe: o formulário abre com os valores dela e guarda as alterações.
  final Receita? editar;

  @override
  State<ReceitaNovaEcra> createState() => _ReceitaNovaEcraState();
}

class _ReceitaNovaEcraState extends State<ReceitaNovaEcra> {
  late final NovaReceita? _inicial = widget.editar?.comoNova();
  late final _medicamento = TextEditingController(
    text: _inicial?.medicamento ?? '',
  );
  late final _dose = TextEditingController(
    text: _inicial?.dose ?? TipoMedicacao.comprimido.doseInicial,
  );
  late final _hora = TextEditingController(
    text: _inicial?.primeiraTomaTexto ?? '08:00',
  );
  late final _horasOutra = TextEditingController(
    text: _inicial?.horasOutra.join(', ') ?? '',
  );
  late Frequencia _frequencia =
      _inicial?.frequencia ?? Frequencia.cadaOitoHoras;
  late final _meses = TextEditingController(
    text: '${(_inicial?.duracao ?? Duracao.tresMeses).meses}',
  );
  String? _erroMeses;
  final _unidades = TextEditingController();
  String? _erroUnidades;
  late TipoMedicacao _tipo = _inicial?.tipo ?? TipoMedicacao.comprimido;
  String? _erroMedicamento, _erroDose, _erroHora, _erroOutra;

  /// Mudar o tipo muda a dose sugerida, mas só se a pessoa ainda não a escreveu à mão.
  void _escolherTipo(TipoMedicacao novo) {
    setState(() {
      if (_dose.text.trim() == _tipo.doseInicial) {
        _dose.text = novo.doseInicial;
      }
      _tipo = novo;
    });
  }

  @override
  void dispose() {
    _medicamento.dispose();
    _dose.dispose();
    _hora.dispose();
    _horasOutra.dispose();
    _meses.dispose();
    _unidades.dispose();
    super.dispose();
  }

  void _continuar() {
    final med = _medicamento.text.trim();
    final dose = _dose.text.trim();
    String? eMed, eDose, eHora, eOutra;
    if (med.isEmpty) eMed = 'Escreva o nome do medicamento.';
    if (dose.isEmpty) eDose = 'Escreva a dose (por exemplo, 1 comprimido).';

    var hora = 8, minuto = 0;
    List<String> outras = const [];
    if (_frequencia == Frequencia.outra) {
      final horas = lerHoras(_horasOutra.text);
      if (horas == null) {
        eOutra = 'Use horas como 08:00, 14:00, 21:00.';
      } else {
        outras = horas;
        hora = int.parse(horas.first.substring(0, 2));
        minuto = int.parse(horas.first.substring(3));
      }
    } else {
      final h = lerHoras(_hora.text);
      if (h == null || h.length != 1) {
        eHora = 'Escreva uma hora como 08:00.';
      } else {
        hora = int.parse(h.first.substring(0, 2));
        minuto = int.parse(h.first.substring(3));
      }
    }
    // "Durante quanto tempo?": um número de meses (só quando se cria; ao editar a duração não muda).
    var meses = Duracao.tresMeses.meses;
    String? eMeses;
    if (widget.editar == null) {
      final n = int.tryParse(_meses.text.trim());
      if (n == null || n < 1 || n > Duracao.maximoMeses) {
        eMeses = 'Escreva um número de meses entre 1 e ${Duracao.maximoMeses}.';
      } else {
        meses = n;
      }
    }
    // "Quantos tem?": obrigatório ao criar (sem isto não há aviso de que o stock não chega); ao editar não se pergunta.
    int? unidades;
    String? eUnidades;
    if (widget.editar == null) {
      unidades = int.tryParse(_unidades.text.trim());
      if (unidades == null || unidades < 1 || unidades > 100000) {
        unidades = null;
        eUnidades = 'Escreva quantas unidades tem, por exemplo 24.';
      }
    }
    setState(() {
      _erroUnidades = eUnidades;
      _erroMeses = eMeses;
      _erroMedicamento = eMed;
      _erroDose = eDose;
      _erroHora = eHora;
      _erroOutra = eOutra;
    });
    if (eMed != null ||
        eDose != null ||
        eHora != null ||
        eOutra != null ||
        eMeses != null ||
        eUnidades != null) {
      return;
    }
    widget.aoContinuar(
      context,
      NovaReceita(
        medicamento: med,
        dose: dose,
        frequencia: _frequencia,
        hora: hora,
        minuto: minuto,
        duracao: Duracao(meses),
        horasOutra: outras,
        tipo: _tipo,
        unidades: unidades,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CorpoComRodape(
      margemInferior: 28,
      conteudo: [
        CabecalhoFormulario(
          titulo: widget.editar == null
              ? 'Adicionar receita'
              : 'Editar receita',
          subtitulo: widget.editar == null
              ? 'Criamos as tomas por si, para ${widget.perfil.nome}.'
              : 'As tomas que ainda faltam ajustam-se às alterações.',
          espaco: 14,
        ),
        const SizedBox(height: 14),
        GrelhaOpcoes<TipoMedicacao>(
          titulo: 'O que toma?',
          opcoes: TipoMedicacao.values,
          texto: (o) => o.texto,
          valor: _tipo,
          colunas: 2,
          aoEscolher: _escolherTipo,
        ),
        const SizedBox(height: 14),
        CampoTexto(
          rotulo: 'Nome do medicamento',
          dica: 'Ex.: Lisinopril 10 mg',
          controlador: _medicamento,
          erro: _erroMedicamento,
          aoMudar: (_) => setState(() => _erroMedicamento = null),
        ),
        const SizedBox(height: 14),
        CampoTexto(
          rotulo: 'Dose',
          controlador: _dose,
          erro: _erroDose,
          aoMudar: (_) => setState(() => _erroDose = null),
        ),
        if (widget.editar == null) ...[
          const SizedBox(height: 14),
          CampoTexto(
            rotulo: 'Quantos tem agora?',
            dica: 'Ex.: 24',
            controlador: _unidades,
            teclado: TextInputType.number,
            maxLength: 6,
            erro: _erroUnidades,
            aoMudar: (_) => setState(() => _erroUnidades = null),
          ),
        ],
        const SizedBox(height: 14),
        GrelhaOpcoes<Frequencia>(
          titulo: 'Com que frequência?',
          opcoes: Frequencia.values,
          texto: (f) => f.texto,
          valor: _frequencia,
          colunas: 2,
          aoEscolher: (f) => setState(() => _frequencia = f),
        ),
        const SizedBox(height: 14),
        if (_frequencia == Frequencia.outra)
          CampoTexto(
            rotulo: 'Horas das tomas',
            dica: '08:00, 14:00, 21:00',
            controlador: _horasOutra,
            erro: _erroOutra,
            aoMudar: (_) => setState(() => _erroOutra = null),
          )
        else
          CampoTexto(
            rotulo: 'Primeira toma',
            controlador: _hora,
            teclado: TextInputType.datetime,
            maxLength: 5,
            erro: _erroHora,
            aoMudar: (_) => setState(() => _erroHora = null),
          ),
        if (widget.editar == null) ...[
          const SizedBox(height: 14),
          CampoTexto(
            rotulo: 'Durante quanto tempo?',
            controlador: _meses,
            teclado: TextInputType.number,
            maxLength: 2,
            erro: _erroMeses,
            // A unidade fica dentro do campo, à direita: o número é sempre de meses.
            sufixo: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                widthFactor: 1,
                child: Text(
                  'meses',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: context.t.texto2,
                  ),
                ),
              ),
            ),
            aoMudar: (_) => setState(() => _erroMeses = null),
          ),
        ],
      ],
      rodape: [
        Botao(
          texto: widget.editar == null
              ? 'Criar tomas e alarmes'
              : 'Guardar alterações',
          icone: Icons.check,
          altura: 60,
          raio: 22,
          tamanhoTexto: 18,
          aoTocar: _continuar,
        ),
      ],
    );
  }
}

enum _Fase { aCriar, aGerar, feito, erro }

/// "A criar as tomas" (design: Carregar-Receita): a geração corre em segundo plano no servidor e a app
/// segue o estado. Os passos mostram só o que é verdade: "Agendar os alarmes" só aparece quando os alarmes
/// tocam neste telemóvel, e só fica feito depois de agendados.
class CarregarReceitaEcra extends StatefulWidget {
  const CarregarReceitaEcra({
    super.key,
    required this.repositorio,
    required this.perfil,
    required this.nova,
    required this.relogio,
    required this.aoConcluir,
    this.intervalo = const Duration(milliseconds: 500),
    this.agendarAlarmes,
  });

  final Repositorio repositorio;
  final Perfil perfil;
  final NovaReceita nova;
  final DateTime Function() relogio;
  final void Function(BuildContext, Receita) aoConcluir;
  final Duration intervalo;

  /// Ver [FluxoReceita.agendarAlarmes].
  final Future<void> Function()? agendarAlarmes;

  @override
  State<CarregarReceitaEcra> createState() => _CarregarReceitaEcraState();
}

class _CarregarReceitaEcraState extends State<CarregarReceitaEcra> {
  _Fase _fase = _Fase.aCriar;
  _Passo _alarmes = _Passo.espera;
  Receita? _receita;
  int _tomas = 0;
  String _erro = 'falha_ao_guardar';

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    if (_fase != _Fase.aCriar) setState(() => _fase = _Fase.aCriar);
    try {
      // Numa nova tentativa depois de a receita já estar criada, só se retoma o acompanhamento.
      _receita ??= await widget.repositorio.criarReceita(
        widget.perfil.id,
        widget.nova,
        widget.relogio(),
      );
      if (!mounted) return;
      setState(() => _fase = _Fase.aGerar);
      for (var i = 0; i < 120; i++) {
        final e = await widget.repositorio.estadoGeracao(
          widget.perfil.id,
          _receita!.id,
        );
        if (!mounted) return;
        if (e.fase == FaseGeracao.concluida) {
          final agendar = widget.agendarAlarmes;
          if (agendar != null) {
            setState(() {
              _tomas = e.tomasGeradas;
              _alarmes = _Passo.aCorrer;
            });
            try {
              await agendar();
            } catch (_) {
              // as tomas estão criadas; os alarmes voltam a agendar-se ao abrir "Hoje"
            }
            if (!mounted) return;
          }
          setState(() {
            _tomas = e.tomasGeradas;
            _alarmes = _Passo.feito;
            _fase = _Fase.feito;
          });
          return;
        }
        if (e.fase == FaseGeracao.falhou) {
          throw const ErroApi('geracao_falhou');
        }
        await Future<void>.delayed(widget.intervalo);
      }
      throw const ErroApi('geracao_lenta');
    } on ErroApi catch (e) {
      _falhou(e.codigo);
    } catch (_) {
      _falhou('falha_ao_guardar');
    }
  }

  void _falhou(String codigo) {
    if (!mounted) return;
    setState(() {
      _erro = codigo;
      _fase = _Fase.erro;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_fase == _Fase.erro) {
      return ErroGuardarEcra(
        titulo: 'Receita do ${widget.nova.medicamento}',
        codigo: _erro,
        aoTentarDeNovo: _iniciar,
        aoCancelar: () => Navigator.of(context).maybePop(),
      );
    }
    final t = context.t;
    final nome = widget.perfil.nome;
    final geracao = switch (_fase) {
      _Fase.aCriar || _Fase.aGerar => _Passo.aCorrer,
      _ => _Passo.feito,
    };
    // A barra de baixo mostra onde vai o trabalho (no design é um valor fixo de 55%). Anda sempre
    // para a frente, devagar enquanto o servidor trabalha, em vez de saltar de um valor para o outro.
    final progresso = switch (_fase) {
      _Fase.aCriar => .2,
      _Fase.aGerar => .9,
      _ => 1.0,
    };
    final duracaoBarra = switch (_fase) {
      _Fase.aCriar => const Duration(milliseconds: 900),
      _Fase.aGerar => const Duration(seconds: 6),
      _ => const Duration(milliseconds: 450),
    };
    final blocos = <Widget>[
      Column(
        children: [
          SizedBox(
            width: 88,
            height: 88,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _fase != _Fase.feito
                  ? const _RodaAGirar(tamanho: 88, traco: 5)
                  // A mesma animação de sucesso dos outros ecrãs. O visto ocupa só parte do desenho,
                  // por isso este fica maior do que a caixa de 88 px e deixa-se transbordar.
                  : const OverflowBox(
                      key: ValueKey('feito'),
                      maxWidth: 176,
                      maxHeight: 176,
                      child: AnimacaoLottie(
                        asset: 'assets/lottie/sucesso.json',
                        largura: 176,
                        altura: 176,
                        descricao: 'Concluído com sucesso',
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Semantics(
            header: true,
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'A criar as tomas',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.48,
                  color: t.texto,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${widget.nova.medicamento} · ${widget.nova.duracao.texto}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              fontWeight: FontWeight.w500,
              color: t.texto2,
            ),
          ),
        ],
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        decoration: BoxDecoration(
          color: t.superficie,
          borderRadius: BorderRadius.circular(24),
          boxShadow: t.sombra,
        ),
        child: Column(
          children: [
            _LinhaPasso(
              estado: geracao,
              texto: _fase == _Fase.feito
                  ? 'Gerar as tomas ($_tomas)'
                  : 'Gerar as tomas',
            ),
            if (widget.agendarAlarmes != null)
              _LinhaPasso(estado: _alarmes, texto: 'Agendar os alarmes'),
            _LinhaPasso(
              estado: _fase == _Fase.feito ? _Passo.feito : _Passo.espera,
              texto: 'Sincronizar com $nome',
            ),
          ],
        ),
      ),
      ExcludeSemantics(
        child: Container(
          height: 8,
          decoration: BoxDecoration(
            color: t.superficie2,
            borderRadius: BorderRadius.circular(4),
          ),
          alignment: Alignment.centerLeft,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: progresso),
            duration: duracaoBarra,
            curve: Curves.easeOutCubic,
            builder: (context, valor, _) => FractionallySizedBox(
              widthFactor: valor,
              child: Container(
                height: 8,
                decoration: BoxDecoration(
                  color: t.primaria,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        ),
      ),
    ];
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: CustomScrollView(
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 48, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ...escalonar(blocos, espaco: 18),
                      const Spacer(),
                      const SizedBox(height: 8),
                      Botao(
                        texto: 'Continuar',
                        altura: 60,
                        raio: 22,
                        tamanhoTexto: 18,
                        aoTocar: _fase == _Fase.feito
                            ? () => widget.aoConcluir(context, _receita!)
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A roda a girar do design (viewBox 50: círculo de pista e arco de um quarto, uma volta em 0,9 s).
class _RodaAGirar extends StatefulWidget {
  const _RodaAGirar({required this.tamanho, required this.traco});
  final double tamanho;
  final double traco;

  @override
  State<_RodaAGirar> createState() => _RodaAGirarState();
}

class _RodaAGirarState extends State<_RodaAGirar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  bool _iniciada = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_iniciada) return;
    _iniciada = true;
    if (!MediaQuery.disableAnimationsOf(context)) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    // A pista e o arco desenham-se uma só vez; só a rotação muda (linear, 1 volta em 0,9 s), por isso
    // o movimento é contínuo mesmo quando o resto do ecrã se atualiza.
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: SizedBox(
          width: widget.tamanho,
          height: widget.tamanho,
          child: RotationTransition(
            turns: _c,
            child: CustomPaint(
              painter: _PintorRoda(
                pista: t.linha,
                arco: t.primaria,
                traco: widget.traco,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PintorRoda extends CustomPainter {
  const _PintorRoda({
    required this.pista,
    required this.arco,
    required this.traco,
  });
  final Color pista;
  final Color arco;
  final double traco;

  @override
  void paint(Canvas canvas, Size size) {
    final escala = size.width / 50;
    final centro = Offset(size.width / 2, size.height / 2);
    final raio = 20 * escala;
    Paint p(Color c) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = traco * escala
      ..strokeCap = StrokeCap.round
      ..color = c;
    canvas.drawCircle(centro, raio, p(pista));
    canvas.drawArc(
      Rect.fromCircle(center: centro, radius: raio),
      -math.pi / 2,
      math.pi / 2,
      false,
      p(arco),
    );
  }

  @override
  bool shouldRepaint(_PintorRoda antigo) =>
      antigo.pista != pista || antigo.arco != arco || antigo.traco != traco;
}

enum _Passo { espera, aCorrer, feito }

class _LinhaPasso extends StatelessWidget {
  const _LinhaPasso({required this.estado, required this.texto});
  final _Passo estado;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final Widget icone = switch (estado) {
      _Passo.feito => SeloIcone(
        cor: t.ok,
        dados: Icones.visto,
        corIcone: t.superficie,
        tamanho: 28,
        traco: 2.4,
      ),
      _Passo.aCorrer => const _RodaAGirar(tamanho: 28, traco: 6),
      _ => Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: t.linha, width: 2),
        ),
      ),
    };
    final apagado = estado == _Passo.espera;
    return Semantics(
      container: true,
      label:
          '$texto, ${switch (estado) {
            _Passo.feito => 'feito',
            _Passo.aCorrer => 'a decorrer',
            _Passo.espera => 'à espera',
          }}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            icone,
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                texto,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: apagado ? t.texto2 : t.texto,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A cápsula do design (a mesma do cartão do modo simples), em 34 px.
const _svgCapsulaReceita =
    '<svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg"><g transform="rotate(-45 32 32)"><rect x="6" y="21" width="52" height="22" rx="11" fill="#FFFFFF" stroke="#0F172A" stroke-width="3"/><path d="M32 21h15a11 11 0 0 1 0 22H32z" fill="#2DD4BF" stroke="#0F172A" stroke-width="3" stroke-linejoin="round"/></g></svg>';

/// "Receita criada" (design: Sucesso-Receita).
class SucessoReceitaEcra extends StatelessWidget {
  const SucessoReceitaEcra({
    super.key,
    required this.nova,
    required this.agora,
    required this.aoVerHoje,
    required this.aoOutra,
  });
  final NovaReceita nova;
  final DateTime agora;
  final void Function(BuildContext) aoVerHoje;
  final void Function(BuildContext) aoOutra;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return EcraResultado(
      topo: const TopoResultado(
        titulo: 'Receita criada',
        texto: 'Criámos as tomas.',
      ),
      cartao: CartaoResultado(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: t.primariaSuave,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ExcludeSemantics(
                    child: SvgPicture.string(
                      _svgCapsulaReceita,
                      width: 34,
                      height: 34,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nova.medicamento,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: t.texto,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        nova.resumo,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: t.texto2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(height: 1, color: t.linha),
            const SizedBox(height: 14),
            Row(
              children: [
                Icone(Icones.relogioCirculo, tamanho: 24, cor: t.texto2),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Primeira toma',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: t.texto,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        nova.primeiraTomaPorExtenso(agora),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: t.texto2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      acoes: [
        Botao(
          texto: 'Ver página principal',
          altura: 60,
          raio: 22,
          tamanhoTexto: 18,
          aoTocar: () => aoVerHoje(context),
        ),
        AcaoTexto(
          texto: 'Adicionar outra receita',
          aoTocar: () => aoOutra(context),
        ),
      ],
    );
  }
}

/// "Não foi possível guardar" (design: Erro-Guardar). "Guardar para depois" só existirá quando
/// houver fila offline, por isso por agora só há "Tentar de novo" e "Cancelar".
class ErroGuardarEcra extends StatelessWidget {
  const ErroGuardarEcra({
    super.key,
    required this.titulo,
    required this.codigo,
    required this.aoTentarDeNovo,
    required this.aoCancelar,
  });
  final String titulo;
  final String codigo;
  final VoidCallback aoTentarDeNovo;
  final VoidCallback aoCancelar;

  static String mensagem(String codigo) => switch (codigo) {
    'sem_rede' =>
      'Sem ligação à internet. Verifique a ligação e tente outra vez.',
    'sessao_expirada' => 'A sessão terminou. Entre outra vez.',
    'demasiadas_tentativas' =>
      'Demasiados pedidos seguidos. Espere um pouco e tente outra vez.',
    _ => 'Algo correu mal ao guardar. Tente outra vez.',
  };

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return EcraResultado(
      topo: TopoResultado(
        titulo: 'Não foi possível guardar',
        texto: mensagem(codigo),
        animacao: const AnimacaoLottie(
          asset: 'assets/lottie/erro.json',
          largura: 170,
          altura: 170,
          descricao: 'Algo correu mal',
        ),
      ),
      cartao: CartaoResultado(
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: t.primariaSuave,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icone(
                Icones.semNuvem,
                tamanho: 24,
                cor: t.sobrePrimariaSuave,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: t.texto,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Ainda não foi guardada',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: t.texto2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      acoes: [
        Botao(
          texto: 'Tentar de novo',
          altura: 60,
          raio: 22,
          tamanhoTexto: 18,
          aoTocar: aoTentarDeNovo,
        ),
        AcaoTexto(texto: 'Cancelar', aoTocar: aoCancelar),
      ],
    );
  }
}
