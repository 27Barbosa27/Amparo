import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../tema/tokens.dart';
import '../componentes/base.dart';
import '../componentes/estilo.dart';
import '../componentes/formulario.dart';
import '../componentes/icones.dart';
import '../componentes/resultado.dart';

/// "Confirme o seu email": depois de criar a conta (ou de tentar entrar sem ter confirmado), o servidor envia um
/// código de 6 números para o email. A conta só abre sessão quando o código está certo.
class VerificarEmailEcra extends StatefulWidget {
  const VerificarEmailEcra({
    super.key,
    required this.email,
    required this.aoVerificar,
    required this.aoReenviar,
  });

  final String email;

  /// Devolve `codigo_invalido`, `sem_rede`, `demasiadas_tentativas`..., ou nulo se o email ficou confirmado.
  final Future<String?> Function(String codigo) aoVerificar;

  /// Pede outro código ao servidor. Devolve `sem_rede`... ou nulo.
  final Future<String?> Function(String email) aoReenviar;

  @override
  State<VerificarEmailEcra> createState() => _VerificarEmailEcraState();
}

class _VerificarEmailEcraState extends State<VerificarEmailEcra> {
  final _codigo = TextEditingController();
  bool _aVerificar = false;
  bool _aReenviar = false;
  bool _reenviado = false;
  String? _erro;

  /// Segundos até se poder pedir outro código (acabou de se enviar um).
  int _espera = 30;
  Timer? _contagem;

  static const _mensagens = {
    'codigo_invalido': 'Código errado, expirado ou já usado. Depois de 5 erros o código deixa de valer: peça um novo.',
    'sem_rede':
        'Sem ligação à internet. Verifique a ligação e tente outra vez.',
    'demasiadas_tentativas':
        'Demasiadas tentativas. Espere um pouco e tente outra vez.',
  };

  @override
  void initState() {
    super.initState();
    _comecarEspera();
  }

  void _comecarEspera() {
    _contagem?.cancel();
    setState(() => _espera = 30);
    _contagem = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _espera--);
      if (_espera <= 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _contagem?.cancel();
    _codigo.dispose();
    super.dispose();
  }

  String get _digitos => _codigo.text.replaceAll(RegExp(r'\s'), '');

  void _mudou(String _) {
    setState(() {
      _erro = null;
      _reenviado = false;
    });
    if (_digitos.length == 6 && !_aVerificar) _verificar();
  }

  Future<void> _verificar() async {
    final codigo = _digitos;
    setState(() => _aVerificar = true);
    final erro = await widget.aoVerificar(codigo);
    if (!mounted) return;
    // (se correu bem, o ecrã seguinte já substituiu este)
    setState(() {
      _aVerificar = false;
      _erro = erro == null
          ? null
          : (_mensagens[erro] ??
                'Não foi possível confirmar. Tente outra vez.');
    });
  }

  Future<void> _reenviar() async {
    setState(() {
      _aReenviar = true;
      _reenviado = false;
      _erro = null;
    });
    final erro = await widget.aoReenviar(widget.email);
    if (!mounted) return;
    if (erro != null) {
      setState(() {
        _aReenviar = false;
        _erro = _mensagens[erro] ?? 'Não foi possível enviar. Tente outra vez.';
      });
      return;
    }
    _codigo.clear();
    setState(() {
      _aReenviar = false;
      _reenviado = true;
    });
    _comecarEspera();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return CorpoComRodape(
      margemInferior: 28,
      conteudo: [
        ...escalonar([
          CabecalhoFormulario(
            titulo: 'Confirme o seu email',
            subtitulo:
                'Enviámos um código de 6 números para ${widget.email}. Escreva-o aqui para abrir a conta.',
          ),
          CampoTexto(
            rotulo: 'Código do email',
            dica: '000 000',
            controlador: _codigo,
            teclado: TextInputType.number,
            autofill: const [AutofillHints.oneTimeCode],
            maxLength: 7,
            erro: _erro,
            aoSubmeter: _digitos.length == 6 && !_aVerificar
                ? _verificar
                : null,
            sufixo: _aVerificar
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  )
                : null,
            aoMudar: _mudou,
          ),
          if (_reenviado)
            Semantics(
              liveRegion: true,
              child: Row(
                children: [
                  SeloIcone(
                    cor: t.ok,
                    dados: Icones.visto,
                    corIcone: t.superficie,
                    tamanho: 22,
                    traco: 2.6,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Enviámos um código novo.',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: t.okTexto,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ], espaco: 14),
      ],
      rodape: [
        Botao(
          texto: _aVerificar ? 'A confirmar…' : 'Confirmar email',
          altura: 60,
          raio: 22,
          tamanhoTexto: 18,
          aoTocar: _aVerificar || _digitos.length != 6 ? null : _verificar,
        ),
        const SizedBox(height: 6),
        AcaoTexto(
          texto: _aReenviar
              ? 'A enviar…'
              : (_espera > 0
                    ? 'Reenviar código ($_espera s)'
                    : 'Reenviar código'),
          aoTocar: _aReenviar || _espera > 0 ? null : _reenviar,
        ),
      ],
    );
  }
}
