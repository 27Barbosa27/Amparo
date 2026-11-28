import 'package:material_ui/material_ui.dart';

import '../../dados/alarmes.dart';
import '../../dominio/modelos.dart';
import '../../tema/tokens.dart';
import '../componentes/base.dart';
import '../componentes/estilo.dart';
import '../componentes/formulario.dart';
import '../componentes/icones.dart';
import '../componentes/resultado.dart';
import 'cuidador_hoje.dart' show horaCurta;

/// "Alarmes fiáveis" (design: Permissoes): as três permissões, cada uma "Feito" ou "Falta". O botão abre as
/// definições do telemóvel, um passo de cada vez; só se pede o que falta, e só quando a pessoa toca.
class AlarmesFiaveisEcra extends StatefulWidget {
  const AlarmesFiaveisEcra({super.key, required this.alarmes, this.aoMudar});

  final ServicoAlarmes alarmes;

  /// Depois de cada pedido: o Mais atualiza o "N em falta".
  final ValueChanged<PermissoesAlarme>? aoMudar;

  @override
  State<AlarmesFiaveisEcra> createState() => _AlarmesFiaveisEcraState();
}

class _AlarmesFiaveisEcraState extends State<AlarmesFiaveisEcra> {
  PermissoesAlarme? _estado;
  bool _aPedir = false;

  @override
  void initState() {
    super.initState();
    _ler();
  }

  Future<void> _ler() async {
    final p = await widget.alarmes.permissoes();
    if (mounted) setState(() => _estado = p);
  }

  Future<void> _pedir() async {
    setState(() => _aPedir = true);
    final p = await widget.alarmes.pedirPermissoes();
    widget.aoMudar?.call(p);
    if (!mounted) return;
    setState(() {
      _estado = p;
      _aPedir = false;
    });
    if (p.emFalta == 0) {
      Navigator.of(context)
          .pushReplacement(rotaPagina<void>(const SucessoAlarmesEcra()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final e = _estado;
    if (!widget.alarmes.suportado) {
      return CorpoComRodape(
        margemInferior: 28,
        conteudo: escalonar([
          const CabecalhoFormulario(
            titulo: 'Para os alarmes tocarem sempre',
            subtitulo: 'Os alarmes tocam na app do telemóvel. Abra o Amparo no telemóvel que recebe os alarmes para ver este passo.',
            espaco: 16,
          ),
        ], espaco: 16),
        rodape: [
          AcaoTexto(
            texto: 'Voltar',
            aoTocar: () => Navigator.of(context).maybePop(),
          ),
        ],
      );
    }
    final falta = e?.emFalta ?? 0;
    return CorpoComRodape(
      margemInferior: 28,
      conteudo: escalonar([
        CabecalhoFormulario(
          titulo: 'Para os alarmes tocarem sempre',
          subtitulo: e == null
              ? 'A ver como está este telemóvel…'
              : falta == 0
              ? 'Está tudo pronto. Os alarmes tocam à hora certa, mesmo com a app fechada.'
              : 'Falta${falta == 1 ? '' : 'm'} $falta passo${falta == 1 ? '' : 's'}. Sem ${falta == 1 ? 'ele' : 'eles'}, o telemóvel pode silenciar os lembretes.',
          espaco: 16,
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: t.superficie,
            borderRadius: BorderRadius.circular(24),
            boxShadow: t.sombra,
          ),
          child: Column(
            children: [
              _LinhaPermissao(
                icone: Icones.relogioCirculo,
                titulo: 'Alarmes exatos',
                texto: 'Tocam à hora certa',
                feito: e?.alarmesExatos,
                primeira: true,
              ),
              _LinhaPermissao(
                icone: const IconeDados(
                  '<rect x="2" y="7" width="18" height="10" rx="2"/><path d="M22 11v2M6 11v2"/>',
                ),
                titulo: 'Bateria sem limites',
                texto: 'O telemóvel não adormece a app',
                feito: e?.bateriaSemLimites,
              ),
              _LinhaPermissao(
                icone: Icones.telemovel,
                titulo: 'Sobre o ecrã bloqueado',
                texto: 'Vê o alarme com o telemóvel bloqueado',
                feito: e?.ecraBloqueado,
              ),
            ],
          ),
        ),
        if (falta > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: t.superficie2,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              'Vamos abrir as definições do telemóvel, um passo de cada vez.',
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                fontWeight: FontWeight.w500,
                color: t.texto2,
              ),
            ),
          ),
      ], espaco: 16),
      rodape: [
        if (falta > 0)
          Botao(
            texto: _aPedir ? 'A abrir…' : 'Abrir definições do telemóvel',
            altura: 60,
            raio: 22,
            tamanhoTexto: 18,
            aoTocar: _aPedir ? null : _pedir,
          )
        else
          Botao(
            texto: 'Concluir',
            altura: 60,
            raio: 22,
            tamanhoTexto: 18,
            aoTocar: e == null ? null : () => Navigator.of(context).maybePop(),
          ),
        if (falta > 0) ...[
          const SizedBox(height: 10),
          AcaoTexto(
            texto: 'Mais tarde',
            aoTocar: () => Navigator.of(context).maybePop(),
          ),
        ],
      ],
    );
  }
}

class _LinhaPermissao extends StatelessWidget {
  const _LinhaPermissao({
    required this.icone,
    required this.titulo,
    required this.texto,
    required this.feito,
    this.primeira = false,
  });
  final IconeDados icone;
  final String titulo;
  final String texto;

  /// Nulo enquanto se lê o estado.
  final bool? feito;
  final bool primeira;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final f = feito;
    return Semantics(
      container: true,
      label:
          '$titulo, ${f == null
              ? 'a verificar'
              : f
              ? 'feito'
              : 'falta'}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          border: primeira ? null : Border(top: BorderSide(color: t.linha)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: t.superficie2,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(child: Icone(icone, tamanho: 24, cor: t.texto)),
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
                    texto,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: t.texto2,
                    ),
                  ),
                ],
              ),
            ),
            if (f != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: f ? t.okSuave : t.avisoSuave,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  f ? 'Feito' : 'Falta',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: f ? t.okTexto : t.avisoTexto,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// "Alarmes prontos" (design: Sucesso-Permissoes).
class SucessoAlarmesEcra extends StatelessWidget {
  const SucessoAlarmesEcra({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    Widget feito(String texto) => Row(
      children: [
        SeloIcone(
          cor: t.ok,
          dados: Icones.visto,
          corIcone: t.superficie,
          tamanho: 28,
          traco: 2.4,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            texto,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: t.texto,
            ),
          ),
        ),
      ],
    );
    return EcraResultado(
      topo: const TopoResultado(
        titulo: 'Alarmes prontos',
        texto: 'Os alarmes vão tocar à hora certa, mesmo com a app fechada.',
      ),
      cartao: CartaoResultado(
        child: Column(
          children: [
            feito('Alarmes exatos'),
            const SizedBox(height: 14),
            feito('Bateria sem limites'),
            const SizedBox(height: 14),
            feito('Sobre o ecrã bloqueado'),
          ],
        ),
      ),
      acoes: [
        Botao(
          texto: 'Concluir',
          altura: 60,
          raio: 22,
          tamanhoTexto: 18,
          aoTocar: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }
}

/// As cores do alarme em ecrã inteiro (design: Alarme), iguais nos dois temas, um pouco mais claras no claro.
const _fundoAlarmeEscuro = Color(0xFF04201E);
const _fundoAlarmeClaro = Color(0xFF0B3B37);
const _menta = Color(0xFFCCFBF1);
const _mentaTexto = Color(0xFFD5F5EF);

/// O alarme em ecrã inteiro (design: Alarme e Alarme-Adiado): a hora, o medicamento, "Tomei" e "Adiar 10 min".
/// Abre-se quando o alarme dispara (também por cima do ecrã bloqueado) ou quando se toca na notificação.
class AlarmeEcra extends StatefulWidget {
  const AlarmeEcra({
    super.key,
    required this.alarme,
    required this.aoTomei,
    required this.aoAdiar,
  });

  final AlarmeToma alarme;

  /// Regista a toma. Devolve a mensagem de erro, ou nulo se ficou registada.
  final Future<String?> Function() aoTomei;

  /// Volta a tocar daqui a 10 minutos; devolve a hora do novo alarme.
  final Future<DateTime> Function() aoAdiar;

  @override
  State<AlarmeEcra> createState() => _AlarmeEcraState();
}

class _AlarmeEcraState extends State<AlarmeEcra> {
  DateTime? _adiadoPara;
  bool _aRegistar = false;
  String? _erro;

  Future<void> _tomei() async {
    setState(() {
      _aRegistar = true;
      _erro = null;
    });
    final erro = await widget.aoTomei();
    if (!mounted) return;
    if (erro == null) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _aRegistar = false;
      _erro = erro;
    });
  }

  Future<void> _adiar() async {
    final quando = await widget.aoAdiar();
    if (mounted) setState(() => _adiadoPara = quando);
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.alarme;
    final escuro = Theme.of(context).brightness == Brightness.dark;
    final adiado = _adiadoPara;
    final detalhe = a.dose;
    return Container(
      color: escuro ? _fundoAlarmeEscuro : _fundoAlarmeClaro,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: CustomScrollView(
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 40, 24, 36),
                    child: Column(
                      children: [
                        _Etiqueta(
                          icone: adiado == null
                              ? Icones.sino
                              : Icones.relogioCirculo,
                          texto: adiado == null
                              ? 'Hora do medicamento'
                              : 'Adiado',
                        ),
                        if (adiado == null) ...[
                          const SizedBox(height: 24),
                          Semantics(
                            label: 'Hora prevista ${horaCurta(a.hora)}',
                            excludeSemantics: true,
                            child: Text(
                              horaCurta(a.hora),
                              style: const TextStyle(
                                fontSize: 80,
                                height: 1,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -3.2,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                        SizedBox(height: adiado == null ? 24 : 56),
                        _Circulo(
                          child: adiado == null
                              ? Icone(
                                  iconeDoTipo(a.dose),
                                  tamanho: 72,
                                  cor: _fundoAlarmeClaro,
                                )
                              : const Icone(
                                  Icones.relogioCirculo,
                                  tamanho: 72,
                                  cor: _fundoAlarmeClaro,
                                ),
                        ),
                        const SizedBox(height: 28),
                        Semantics(
                          header: true,
                          liveRegion: true,
                          child: Text(
                            adiado == null
                                ? a.medicamento
                                : 'Volto a avisar às ${horaCurta(adiado)}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: adiado == null ? 32 : 28,
                              height: 1.1,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.6,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          adiado == null
                              ? detalhe
                              : [
                                  a.medicamento,
                                  if (detalhe.isNotEmpty) detalhe,
                                ].join(' · '),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: adiado == null ? 20 : 18,
                            fontWeight: FontWeight.w500,
                            color: _mentaTexto,
                          ),
                        ),
                        if (_erro != null) ...[
                          const SizedBox(height: 16),
                          Semantics(
                            liveRegion: true,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: .12),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                _erro!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                        const Spacer(),
                        const SizedBox(height: 24),
                        Botao(
                          texto: _aRegistar
                              ? 'A registar…'
                              : adiado == null
                              ? 'Tomei'
                              : 'Tomei agora',
                          iconeSvg: Icones.visto,
                          tracoIcone: 2.4,
                          tamanhoIcone: adiado == null ? 36 : 28,
                          altura: adiado == null ? 80 : 64,
                          raio: 48,
                          tamanhoTexto: adiado == null ? 28 : 22,
                          fundo: Colors.white,
                          cor: _fundoAlarmeClaro,
                          aoTocar: _aRegistar ? null : _tomei,
                        ),
                        const SizedBox(height: 14),
                        if (adiado == null)
                          Botao(
                            texto: 'Adiar 10 min',
                            iconeSvg: Icones.relogioCirculo,
                            tamanhoIcone: 28,
                            altura: 60,
                            raio: 36,
                            tamanhoTexto: 20,
                            fundo: Colors.white.withValues(alpha: .08),
                            cor: Colors.white,
                            contorno: Colors.white.withValues(alpha: .75),
                            aoTocar: _aRegistar ? null : _adiar,
                          )
                        else
                          Botao(
                            texto: 'Está bem',
                            altura: 56,
                            raio: 36,
                            tamanhoTexto: 18,
                            fundo: Colors.transparent,
                            cor: Colors.white,
                            contorno: Colors.white.withValues(alpha: .75),
                            aoTocar: () => Navigator.of(context).maybePop(),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta({required this.icone, required this.texto});
  final IconeDados icone;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 18, 8),
      decoration: BoxDecoration(
        color: _menta,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SeloIcone(
            cor: _fundoAlarmeClaro,
            dados: icone,
            corIcone: _menta,
            tamanho: 32,
            tamanhoIcone: 20,
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              texto,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: _fundoAlarmeClaro,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// O círculo branco com os dois anéis à volta (design: Alarme).
class _Circulo extends StatelessWidget {
  const _Circulo({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _menta.withValues(alpha: .07),
            ),
          ),
          Container(
            width: 154,
            height: 154,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _menta.withValues(alpha: .13),
            ),
          ),
          Container(
            width: 128,
            height: 128,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Color(0x59000000),
                  blurRadius: 50,
                  offset: Offset(0, 20),
                ),
              ],
            ),
            child: Center(child: child),
          ),
        ],
      ),
    );
  }
}
