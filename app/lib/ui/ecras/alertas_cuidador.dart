import 'package:material_ui/material_ui.dart';

import '../../dados/api.dart';
import '../../dados/repositorio.dart';
import '../../dominio/modelos.dart';
import '../../tema/tokens.dart';
import '../componentes/base.dart';
import '../componentes/formulario.dart';

/// "Alertas ao cuidador" (design: Alertas-ao-cuidador): quando o cuidador quer ser avisado sobre as
/// tomas da pessoa. Funciona da mesma forma quando o cuidador é a própria pessoa (perfil próprio):
/// são sempre as preferências de alerta *deste cuidador* para *este perfil*.
class AlertasCuidadorEcra extends StatefulWidget {
  const AlertasCuidadorEcra({
    super.key,
    required this.repositorio,
    required this.perfil,
    required this.proprio,
  });

  final Repositorio repositorio;
  final Perfil perfil;

  /// O perfil aberto é o do próprio cuidador: muda só a frase do subtítulo.
  final bool proprio;

  @override
  State<AlertasCuidadorEcra> createState() => _AlertasCuidadorEcraState();
}

class _AlertasCuidadorEcraState extends State<AlertasCuidadorEcra> {
  AlertasPrefs? _prefs;
  bool _aCarregar = true;
  bool _aGuardar = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _aCarregar = true;
      _erro = null;
    });
    try {
      final prefs = await widget.repositorio.alertasPrefs(widget.perfil.id);
      if (!mounted) return;
      setState(() => _prefs = prefs);
    } on ErroApi catch (e) {
      setState(() => _erro = e.codigo);
    } catch (_) {
      setState(() => _erro = 'falha_ao_carregar');
    } finally {
      if (mounted) setState(() => _aCarregar = false);
    }
  }

  Future<void> _guardar() async {
    final prefs = _prefs;
    if (prefs == null) return;
    setState(() {
      _aGuardar = true;
      _erro = null;
    });
    try {
      await widget.repositorio.atualizarAlertasPrefs(widget.perfil.id, prefs);
      if (mounted) Navigator.of(context).maybePop();
    } on ErroApi catch (e) {
      setState(() => _erro = e.codigo == 'sem_rede'
          ? 'Sem ligação à internet. Tente outra vez quando houver rede.'
          : 'Não foi possível guardar. Tente outra vez.');
    } catch (_) {
      setState(() => _erro = 'Não foi possível guardar. Tente outra vez.');
    } finally {
      if (mounted) setState(() => _aGuardar = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final prefs = _prefs;
    return CorpoComRodape(
      conteudo: [
        CabecalhoFormulario(
          titulo: 'Alertas ao cuidador',
          subtitulo: widget.proprio
              ? 'Escolha quando quer ser avisado sobre as suas tomas.'
              : 'Escolha quando quer ser avisado sobre ${widget.perfil.nome}.',
        ),
        const SizedBox(height: 18),
        if (_aCarregar)
          const Padding(
            padding: EdgeInsets.only(top: 20),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (prefs == null)
          Cartao(
            raio: 5,
            cor: t.mauSuave,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _erro == 'sem_rede'
                      ? 'Sem ligação. Verifique a internet e tente outra vez.'
                      : 'Não foi possível carregar os alertas.',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: t.mauTexto,
                  ),
                ),
                const SizedBox(height: 12),
                Botao(texto: 'Tentar outra vez', icone: Icons.refresh, aoTocar: _carregar),
              ],
            ),
          )
        else ...[
          Cartao(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _LinhaAlerta(
                  titulo: 'Toma não confirmada',
                  descricao: widget.proprio
                      ? 'Aviso se não confirmar a tempo'
                      : 'Aviso se ${widget.perfil.nome} não confirmar a tempo',
                  ligado: prefs.tomaNaoConfirmada,
                  primeira: true,
                  aoMudar: (v) =>
                      setState(() => _prefs = prefs.copiarCom(tomaNaoConfirmada: v)),
                  extra: prefs.tomaNaoConfirmada
                      ? Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: GrelhaOpcoes<int>(
                            titulo: '',
                            opcoes: const [10, 15, 30],
                            texto: (m) => '$m min',
                            valor: prefs.esperaMin,
                            aoEscolher: (m) =>
                                setState(() => _prefs = prefs.copiarCom(esperaMin: m)),
                          ),
                        )
                      : null,
                ),
                _LinhaAlerta(
                  titulo: 'Toma feita',
                  descricao: widget.proprio
                      ? 'Aviso sempre que confirmar'
                      : 'Aviso sempre que ${widget.perfil.nome} confirmar',
                  ligado: prefs.tomaFeita,
                  aoMudar: (v) => setState(() => _prefs = prefs.copiarCom(tomaFeita: v)),
                ),
                _LinhaAlerta(
                  titulo: 'Receita a acabar',
                  descricao: 'Aviso ${prefs.diasAntes} ${prefs.diasAntes == 1 ? 'dia' : 'dias'} antes de acabar',
                  ligado: prefs.receitaAcabar,
                  ultima: true,
                  aoMudar: (v) => setState(() => _prefs = prefs.copiarCom(receitaAcabar: v)),
                  extra: prefs.receitaAcabar
                      ? Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: GrelhaOpcoes<int>(
                            titulo: '',
                            opcoes: const [2, 4, 7, 14],
                            colunas: 4,
                            texto: (d) => '$d d',
                            valor: prefs.diasAntes,
                            aoEscolher: (d) =>
                                setState(() => _prefs = prefs.copiarCom(diasAntes: d)),
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: t.superficie,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Icon(Icons.notifications_none, size: 22, color: t.texto2),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Os avisos chegam como notificações no seu telemóvel.',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: t.texto2),
                  ),
                ),
              ],
            ),
          ),
          if (_erro != null) ...[
            const SizedBox(height: 10),
            Semantics(
              liveRegion: true,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: t.mauSuave,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _erro!,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: t.mauTexto),
                ),
              ),
            ),
          ],
        ],
      ],
      rodape: [
        Botao(
          texto: _aGuardar ? 'A guardar…' : 'Guardar',
          icone: Icons.check,
          altura: 60,
          raio: 22,
          tamanhoTexto: 18,
          aoTocar: (prefs == null || _aGuardar) ? null : _guardar,
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: SizedBox(
            height: 48,
            child: Center(
              child: Text(
                'Cancelar',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: t.texto),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LinhaAlerta extends StatelessWidget {
  const _LinhaAlerta({
    required this.titulo,
    required this.descricao,
    required this.ligado,
    required this.aoMudar,
    this.primeira = false,
    this.ultima = false,
    this.extra,
  });

  final String titulo;
  final String descricao;
  final bool ligado;
  final ValueChanged<bool> aoMudar;
  final bool primeira;
  final bool ultima;

  /// Conteúdo extra por baixo (por exemplo, o seletor de minutos), só quando [ligado].
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      padding: EdgeInsets.fromLTRB(18, 16, 18, ultima ? 16 : 16),
      decoration: BoxDecoration(
        border: primeira ? null : Border(top: BorderSide(color: t.linha)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => aoMudar(!ligado),
            child: Row(
              children: [
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
                        descricao,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: t.texto2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Interruptor(ligado: ligado),
              ],
            ),
          ),
          ?extra,
        ],
      ),
    );
  }
}
