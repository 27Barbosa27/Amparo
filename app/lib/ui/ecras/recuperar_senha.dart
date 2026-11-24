import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../tema/tokens.dart';
import '../componentes/base.dart';
import '../componentes/estilo.dart';
import '../componentes/formulario.dart';
import '../componentes/icones.dart';
import '../componentes/resultado.dart';

final _padraoEmail = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

/// "Recuperar palavra-passe": pede o email e o servidor envia um código de 6 dígitos (vale 5 minutos, uso único).
/// A resposta é a mesma exista a conta ou não, por isso o ecrã nunca diz se o email está registado.
class RecuperarSenhaEcra extends StatefulWidget {
  const RecuperarSenhaEcra({
    super.key,
    required this.aoPedir,
    required this.aoTenhoCodigo,
    this.emailInicial = '',
  });

  /// Devolve `sem_rede` ou `demasiadas_tentativas`, ou nulo se o pedido seguiu.
  final Future<String?> Function(String email) aoPedir;

  /// Depois de enviar o código: abre o ecrã de definir a nova palavra-passe.
  final void Function(String email) aoTenhoCodigo;
  final String emailInicial;

  @override
  State<RecuperarSenhaEcra> createState() => _RecuperarSenhaEcraState();
}

class _RecuperarSenhaEcraState extends State<RecuperarSenhaEcra> {
  late final _email = TextEditingController(text: widget.emailInicial);
  bool _aEnviar = false;
  bool _enviado = false;
  String? _erroEmail;
  String? _erroGeral;

  static const _mensagens = {
    'sem_rede': 'Sem ligação. Verifique a internet e tente outra vez.',
    'demasiadas_tentativas':
        'Demasiados pedidos seguidos. Espere um pouco e tente outra vez.',
  };

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final email = _email.text.trim();
    if (!_padraoEmail.hasMatch(email)) {
      setState(
        () => _erroEmail = 'Escreva um email válido, como nome@exemplo.pt.',
      );
      return;
    }
    setState(() {
      _aEnviar = true;
      _erroEmail = null;
      _erroGeral = null;
    });
    final erro = await widget.aoPedir(email);
    if (!mounted) return;
    setState(() {
      _aEnviar = false;
      _enviado = erro == null;
      _erroGeral = erro == null
          ? null
          : (_mensagens[erro] ?? 'Não foi possível enviar. Tente outra vez.');
    });
    // Enviado: passa logo ao ecrã onde se escreve o código do email e a palavra-passe nova.
    if (erro == null) widget.aoTenhoCodigo(email);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return CorpoComRodape(
      margemInferior: 28,
      conteudo: [
        ...escalonar([
          const CabecalhoFormulario(
            titulo: 'Recuperar palavra-passe',
            subtitulo: 'Escreva o email da conta. Enviamos um código para definir uma nova palavra-passe.',
          ),
          CampoTexto(
            rotulo: 'Email',
            dica: 'nome@exemplo.pt',
            controlador: _email,
            teclado: TextInputType.emailAddress,
            maxLength: 254,
            erro: _erroEmail,
            autofill: const [AutofillHints.email],
            aoSubmeter: _aEnviar ? null : _enviar,
            aoMudar: (_) {
              if (_erroEmail != null) setState(() => _erroEmail = null);
            },
          ),
          if (_enviado)
            Semantics(
              liveRegion: true,
              child: Cartao(
                raio: 20,
                cor: t.okSuave,
                child: Text(
                  'Se existir uma conta com esse email, enviámos um código. Vale 5 minutos e só pode ser usado uma vez. Veja também o spam.',
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: t.okTexto,
                  ),
                ),
              ),
            ),
          if (_erroGeral != null)
            Semantics(
              liveRegion: true,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: t.mauSuave,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _erroGeral!,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: t.mauTexto,
                  ),
                ),
              ),
            ),
        ], espaco: 14),
      ],
      rodape: [
        Botao(
          texto: _aEnviar
              ? 'A enviar…'
              : (_enviado ? 'Enviar outro código' : 'Enviar código'),
          altura: 60,
          raio: 22,
          tamanhoTexto: 18,
          aoTocar: _aEnviar ? null : _enviar,
        ),
        const SizedBox(height: 6),
        AcaoTexto(
          texto: 'Voltar a entrar',
          aoTocar: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }
}

/// Valida a nova palavra-passe (as mesmas regras do registo e do servidor: 8 a 128 caracteres).
({String? senha, String? repetir}) validarNovaSenha(
  String senha,
  String repetir,
) {
  final s = senha.length < 8
      ? 'A palavra-passe precisa de pelo menos 8 caracteres.'
      : (senha.length > 128
            ? 'A palavra-passe é demasiado longa (máximo 128).'
            : null);
  final r = s == null && senha != repetir
      ? 'As palavras-passe não são iguais.'
      : null;
  return (senha: s, repetir: r);
}

/// "Nova palavra-passe": o código vem na ligação do email (já preenchido quando se abre pela ligação)
/// ou cola-se à mão.
class NovaSenhaEcra extends StatefulWidget {
  const NovaSenhaEcra({
    super.key,
    required this.aoVerificar,
    required this.aoRepor,
    required this.aoConcluir,
    required this.aoReenviar,
    required this.email,
  });

  /// O email a que se enviou o código (mostra-se no ecrã).
  final String email;

  /// Confirma o código (sem o gastar). Devolve `token_invalido`, `sem_rede`..., ou nulo se está certo.
  final Future<String?> Function(String email, String codigo) aoVerificar;

  /// Devolve `token_invalido`, `pedido_invalido`, `sem_rede`..., ou nulo se a palavra-passe mudou.
  final Future<String?> Function(String email, String codigo, String senha)
  aoRepor;

  /// Depois de mudar: o utilizador vai entrar com a nova palavra-passe.
  final VoidCallback aoConcluir;

  /// "Reenviar código": pede outro por email (o anterior deixa de valer). Devolve `sem_rede`... ou nulo.
  final Future<String?> Function(String email) aoReenviar;

  @override
  State<NovaSenhaEcra> createState() => _NovaSenhaEcraState();
}

class _NovaSenhaEcraState extends State<NovaSenhaEcra> {
  final _token = TextEditingController();
  final _senha = TextEditingController();
  final _repetir = TextEditingController();
  bool _aGuardar = false;
  bool _aConfirmar = false;
  bool _confirmado = false;
  bool _aReenviar = false;
  bool _reenviado = false;

  /// Segundos até se poder pedir outro código (acabou de se enviar um; evita pedidos a mais).
  int _espera = 30;
  Timer? _contagem;
  String? _erroToken;
  String? _erroSenha;
  String? _erroRepetir;
  String? _erroGeral;

  static const _mensagens = {
    'sem_rede': 'Sem ligação. Verifique a internet e tente outra vez.',
    'demasiadas_tentativas':
        'Demasiados pedidos seguidos. Espere um pouco e tente outra vez.',
    'pedido_invalido':
        'Confirme o código e a palavra-passe (8 a 128 caracteres).',
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

  Future<void> _reenviar() async {
    setState(() {
      _aReenviar = true;
      _reenviado = false;
      _erroGeral = null;
    });
    final erro = await widget.aoReenviar(widget.email);
    if (!mounted) return;
    if (erro != null) {
      setState(() {
        _aReenviar = false;
        _erroGeral =
            _mensagens[erro] ?? 'Não foi possível enviar. Tente outra vez.';
      });
      return;
    }
    // O código novo substitui o anterior: recomeça-se do campo do código.
    _token.clear();
    setState(() {
      _aReenviar = false;
      _reenviado = true;
      _confirmado = false;
      _aConfirmar = false;
      _erroToken = null;
    });
    _comecarEspera();
  }

  @override
  void dispose() {
    _contagem?.cancel();
    _token.dispose();
    _senha.dispose();
    _repetir.dispose();
    super.dispose();
  }

  String get _digitos => _token.text.replaceAll(RegExp(r'\s'), '');

  void _mudouCodigo(String _) {
    // Qualquer alteração ao código volta a bloquear a palavra-passe até nova confirmação.
    setState(() {
      _erroToken = null;
      _erroGeral = null;
      _confirmado = false;
      _aConfirmar = false;
    });
    if (_digitos.length == 6) _confirmar();
  }

  Future<void> _confirmar() async {
    final codigo = _digitos;
    setState(() => _aConfirmar = true);
    final erro = await widget.aoVerificar(widget.email, codigo);
    if (!mounted || _digitos != codigo) return; // o código mudou entretanto
    setState(() {
      _aConfirmar = false;
      _confirmado = erro == null;
      if (erro == 'token_invalido') {
        _erroToken = 'Código errado, expirado ou já usado. Depois de 5 erros o código deixa de valer.';
      } else if (erro != null) {
        _erroGeral =
            _mensagens[erro] ?? 'Não foi possível confirmar. Tente outra vez.';
      }
    });
  }

  Future<void> _guardar() async {
    if (!_confirmado) return;
    final token = _digitos;
    final v = validarNovaSenha(_senha.text, _repetir.text);
    setState(() {
      _erroToken = RegExp(r'^\d{6}$').hasMatch(token)
          ? null
          : 'O código tem 6 números.';
      _erroSenha = v.senha;
      _erroRepetir = v.repetir;
      _erroGeral = null;
    });
    if (_erroToken != null || v.senha != null || v.repetir != null) return;
    setState(() => _aGuardar = true);
    final erro = await widget.aoRepor(widget.email, token, _senha.text);
    if (!mounted) return;
    if (erro == null) {
      Navigator.of(context).pushReplacement(
        rotaPagina<void>(SenhaAlteradaEcra(aoEntrar: widget.aoConcluir)),
      );
      return;
    }
    setState(() {
      _aGuardar = false;
      if (erro == 'token_invalido') {
        _erroGeral = 'Código errado, expirado ou já usado. Depois de 5 erros o código deixa de valer: peça um novo.';
      } else {
        _erroGeral =
            _mensagens[erro] ?? 'Não foi possível guardar. Tente outra vez.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return CorpoComRodape(
      margemInferior: 28,
      conteudo: [
        ...escalonar([
          CabecalhoFormulario(
            titulo: 'Nova palavra-passe',
            subtitulo:
                'Escreva o código de 6 números que enviámos para ${widget.email} e escolha uma palavra-passe nova.',
          ),
          CampoTexto(
            rotulo: 'Código do email',
            dica: '000 000',
            controlador: _token,
            teclado: TextInputType.number,
            autofill: const [AutofillHints.oneTimeCode],
            maxLength: 7,
            erro: _erroToken,
            sufixo: _confirmado
                ? Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Semantics(
                      label: 'Código confirmado',
                      child: SeloIcone(
                        cor: t.ok,
                        dados: Icones.visto,
                        corIcone: t.superficie,
                        tamanho: 28,
                        traco: 2.6,
                      ),
                    ),
                  )
                : (_aConfirmar
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          ),
                        )
                      : null),
            aoSubmeter: _digitos.length == 6 && !_aConfirmar && !_confirmado
                ? _confirmar
                : null,
            aoMudar: _mudouCodigo,
          ),
          CampoTexto(
            rotulo: 'Nova palavra-passe',
            dica: 'Pelo menos 8 caracteres',
            controlador: _senha,
            ativo: _confirmado,
            senha: true,
            maxLength: 128,
            erro: _erroSenha,
            autofill: const [AutofillHints.newPassword],
            aoMudar: (_) {
              if (_erroSenha != null) setState(() => _erroSenha = null);
            },
          ),
          CampoTexto(
            rotulo: 'Repetir a palavra-passe',
            controlador: _repetir,
            ativo: _confirmado,
            senha: true,
            maxLength: 128,
            erro: _erroRepetir,
            autofill: const [AutofillHints.newPassword],
            aoSubmeter: _aGuardar ? null : _guardar,
            aoMudar: (_) {
              if (_erroRepetir != null) setState(() => _erroRepetir = null);
            },
          ),
          if (_erroGeral != null)
            Semantics(
              liveRegion: true,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: t.mauSuave,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _erroGeral!,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: t.mauTexto,
                  ),
                ),
              ),
            ),
        ], espaco: 14),
      ],
      rodape: [
        Botao(
          texto: _aGuardar ? 'A guardar…' : 'Guardar palavra-passe',
          altura: 60,
          raio: 22,
          tamanhoTexto: 18,
          aoTocar: _aGuardar || !_confirmado ? null : _guardar,
        ),
        if (_reenviado)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Enviámos um código novo para ${widget.email}.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: t.okTexto,
                ),
              ),
            ),
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

/// "Palavra-passe alterada": todas as sessões antigas foram terminadas, por isso é preciso entrar de novo.
class SenhaAlteradaEcra extends StatelessWidget {
  const SenhaAlteradaEcra({super.key, required this.aoEntrar});
  final VoidCallback aoEntrar;

  @override
  Widget build(BuildContext context) {
    return EcraResultado(
      topo: const TopoResultado(
        titulo: 'Palavra-passe alterada',
        texto: 'Por segurança, terminámos as sessões abertas. Entre com a palavra-passe nova.',
      ),
      acoes: [
        Botao(
          texto: 'Entrar',
          altura: 60,
          raio: 22,
          tamanhoTexto: 18,
          aoTocar: aoEntrar,
        ),
      ],
    );
  }
}
