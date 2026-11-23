import 'package:material_ui/material_ui.dart';

import '../../dados/api.dart';
import '../../dados/corpo_receita.dart';
import '../../dados/repositorio.dart';
import '../../dominio/modelos.dart';
import '../../tema/tokens.dart';
import '../componentes/animacao.dart';
import '../componentes/base.dart';
import '../componentes/formulario.dart';

/// O fluxo do design: Adicionar receita → A criar as tomas → Receita criada (ou erro ao guardar).
class FluxoReceita {
  FluxoReceita({
    required this.repositorio,
    required this.perfil,
    required this.relogio,
    required this.aoVerHoje,
    this.intervaloDeConsulta = const Duration(milliseconds: 500),
  });

  final Repositorio repositorio;
  final Perfil perfil;
  final DateTime Function() relogio;

  /// O cuidador escolheu "Ver Hoje": quem chamou volta ao ecrã Hoje e recarrega.
  final VoidCallback aoVerHoje;
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
          aoConcluir: (c2, r) => Navigator.of(c2).pushReplacement(
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
          ),
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
  });
  final Perfil perfil;
  final void Function(BuildContext, NovaReceita) aoContinuar;

  @override
  State<ReceitaNovaEcra> createState() => _ReceitaNovaEcraState();
}

class _ReceitaNovaEcraState extends State<ReceitaNovaEcra> {
  final _medicamento = TextEditingController();
  final _dose = TextEditingController(text: '1 comprimido');
  final _hora = TextEditingController(text: '08:00');
  final _horasOutra = TextEditingController();
  Frequencia _frequencia = Frequencia.cadaOitoHoras;
  Duracao _duracao = Duracao.tresMeses;
  String? _erroMedicamento, _erroDose, _erroHora, _erroOutra;

  @override
  void dispose() {
    _medicamento.dispose();
    _dose.dispose();
    _hora.dispose();
    _horasOutra.dispose();
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
    setState(() {
      _erroMedicamento = eMed;
      _erroDose = eDose;
      _erroHora = eHora;
      _erroOutra = eOutra;
    });
    if (eMed != null || eDose != null || eHora != null || eOutra != null) {
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
        duracao: _duracao,
        horasOutra: outras,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CorpoComRodape(
      conteudo: [
        CabecalhoFormulario(
          titulo: 'Adicionar receita',
          subtitulo: 'Criamos as tomas por si, para ${widget.perfil.nome}.',
        ),
        const SizedBox(height: 14),
        CampoTexto(
          rotulo: 'Medicamento',
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
        const SizedBox(height: 14),
        GrelhaOpcoes<Duracao>(
          titulo: 'Durante quanto tempo?',
          opcoes: Duracao.values,
          texto: (d) => d.texto,
          valor: _duracao,
          aoEscolher: (d) => setState(() => _duracao = d),
        ),
      ],
      rodape: [
        Botao(
          texto: 'Criar tomas e alarmes',
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
/// segue o estado. Os passos mostram só o que é verdade: os alarmes locais ainda não existem.
class CarregarReceitaEcra extends StatefulWidget {
  const CarregarReceitaEcra({
    super.key,
    required this.repositorio,
    required this.perfil,
    required this.nova,
    required this.relogio,
    required this.aoConcluir,
    this.intervalo = const Duration(milliseconds: 500),
  });

  final Repositorio repositorio;
  final Perfil perfil;
  final NovaReceita nova;
  final DateTime Function() relogio;
  final void Function(BuildContext, Receita) aoConcluir;
  final Duration intervalo;

  @override
  State<CarregarReceitaEcra> createState() => _CarregarReceitaEcraState();
}

class _CarregarReceitaEcraState extends State<CarregarReceitaEcra> {
  _Fase _fase = _Fase.aCriar;
  Receita? _receita;
  int _tomas = 0;
  String _erro = 'falha_ao_guardar';

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  Future<void> _iniciar() async {
    setState(() => _fase = _Fase.aCriar);
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
          setState(() {
            _tomas = e.tomasGeradas;
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
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          child: Column(
            children: [
              const SizedBox(height: 40),
              Semantics(
                header: true,
                child: Text(
                  'A criar as tomas',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.65,
                    color: t.texto,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '${widget.nova.medicamento} · ${widget.nova.duracao.texto}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: t.texto2,
                ),
              ),
              const SizedBox(height: 28),
              Cartao(
                child: Column(
                  children: [
                    _LinhaPasso(
                      estado: geracao,
                      texto: _fase == _Fase.feito
                          ? 'Gerar as tomas ($_tomas)'
                          : 'Gerar as tomas',
                    ),
                    const SizedBox(height: 16),
                    const _LinhaPasso(
                      estado: _Passo.emBreve,
                      texto: 'Agendar os alarmes',
                      nota: 'Em breve',
                    ),
                    const SizedBox(height: 16),
                    _LinhaPasso(
                      estado: _fase == _Fase.feito
                          ? _Passo.feito
                          : _Passo.espera,
                      texto: 'Sincronizar com $nome',
                    ),
                  ],
                ),
              ),
              const Spacer(),
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
    );
  }
}

enum _Passo { espera, aCorrer, feito, emBreve }

class _LinhaPasso extends StatelessWidget {
  const _LinhaPasso({required this.estado, required this.texto, this.nota});
  final _Passo estado;
  final String texto;
  final String? nota;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final Widget icone = switch (estado) {
      _Passo.feito => Selo(
        cor: t.ok,
        icone: Icons.check,
        corIcone: t.superficie,
      ),
      _Passo.aCorrer => SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 3, color: t.primaria),
      ),
      _ => Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: t.superficie2,
          border: Border.all(color: t.linha),
        ),
      ),
    };
    final apagado = estado == _Passo.emBreve || estado == _Passo.espera;
    return Semantics(
      container: true,
      label:
          '$texto, ${switch (estado) {
            _Passo.feito => 'feito',
            _Passo.aCorrer => 'a decorrer',
            _Passo.emBreve => 'em breve',
            _Passo.espera => 'à espera',
          }}',
      excludeSemantics: true,
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
          if (nota != null)
            Text(
              nota!,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: t.texto2,
              ),
            ),
        ],
      ),
    );
  }
}

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
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          child: Column(
            children: [
              const AnimacaoLottie(
                asset: 'assets/lottie/sucesso.json',
                largura: 220,
                altura: 240,
                ultimoFotograma: 112,
                descricao: 'Concluído com sucesso',
              ),
              const SizedBox(height: 12),
              Semantics(
                header: true,
                child: Text(
                  'Receita criada',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.65,
                    color: t.texto,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Criámos as tomas.',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: t.texto2,
                ),
              ),
              const SizedBox(height: 18),
              Cartao(
                child: SizedBox(
                  width: double.infinity,
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
                      Text(
                        nova.resumo,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: t.texto2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Divider(height: 1, color: t.linha),
                      const SizedBox(height: 10),
                      Text(
                        'Primeira toma',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: t.texto2,
                        ),
                      ),
                      Text(
                        nova.primeiraTomaPorExtenso(agora),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: t.texto,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              Botao(
                texto: 'Ver Hoje',
                altura: 60,
                raio: 22,
                tamanhoTexto: 18,
                aoTocar: () => aoVerHoje(context),
              ),
              const SizedBox(height: 8),
              Botao(
                texto: 'Adicionar outra receita',
                icone: Icons.add,
                altura: 52,
                raio: 20,
                fundo: Colors.transparent,
                cor: t.texto,
                contorno: t.linha,
                aoTocar: () => aoOutra(context),
              ),
            ],
          ),
        ),
      ),
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
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          child: Column(
            children: [
              const AnimacaoLottie(
                asset: 'assets/lottie/erro.json',
                largura: 160,
                altura: 160,
                descricao: 'Algo correu mal',
              ),
              const SizedBox(height: 12),
              Semantics(
                header: true,
                child: Text(
                  'Não foi possível guardar',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 26,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.65,
                    color: t.texto,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  mensagem(codigo),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                    color: t.texto2,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Cartao(
                cor: t.mauSuave,
                child: SizedBox(
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: t.mauTexto,
                        ),
                      ),
                      Text(
                        'Ainda não foi guardada',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: t.mauTexto,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              Botao(
                texto: 'Tentar de novo',
                icone: Icons.refresh,
                altura: 60,
                raio: 22,
                tamanhoTexto: 18,
                aoTocar: aoTentarDeNovo,
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: aoCancelar,
                child: SizedBox(
                  height: 48,
                  child: Center(
                    child: Text(
                      'Cancelar',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: t.texto,
                      ),
                    ),
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
