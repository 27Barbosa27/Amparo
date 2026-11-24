import 'package:material_ui/material_ui.dart';

import '../../tema/tokens.dart';
import '../componentes/animacao.dart';
import '../componentes/base.dart';
import '../componentes/icones.dart';
import '../componentes/resultado.dart';
import '../componentes/formulario.dart';
import '../componentes/sso.dart';

/// Erros de cada campo do registo (nulo = está bem).
class ErrosRegisto {
  const ErrosRegisto({this.nome, this.email, this.senha, this.termos});
  final String? nome;
  final String? email;
  final String? senha;
  final String? termos;
  bool get temErros =>
      nome != null || email != null || senha != null || termos != null;
}

/// Valida o formulário antes de falar com o servidor (as mesmas regras do backend: palavra-passe de 8 a 128).
ErrosRegisto validarRegisto({
  required String nome,
  required String email,
  required String senha,
  required bool aceitaTermos,
}) {
  final e = email.trim();
  return ErrosRegisto(
    nome: nome.trim().isEmpty ? 'Escreva como quer ser chamado.' : null,
    email: RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(e)
        ? null
        : 'Escreva um email válido, como nome@exemplo.pt.',
    senha: senha.length < 8
        ? 'A palavra-passe precisa de pelo menos 8 caracteres.'
        : (senha.length > 128
              ? 'A palavra-passe é demasiado longa (máximo 128).'
              : null),
    termos: aceitaTermos ? null : 'Para criar a conta, aceite os termos.',
  );
}

/// "Criar conta" (design: Registo). Só cuidadores têm conta; as pessoas adicionam-se depois.
/// A caixa dos termos começa desmarcada: o consentimento para dados de saúde tem de ser um ato explícito.
class CriarContaEcra extends StatefulWidget {
  const CriarContaEcra({
    super.key,
    required this.aoCriar,
    required this.aoEntrar,
    this.aoApple,
    this.aoGoogle,
    this.googleWeb,
  });

  /// Devolve o código de erro (`email_ja_existe`, `sem_rede`...) ou nulo se a conta foi criada.
  final Future<String?> Function(String nome, String email, String senha)
  aoCriar;

  /// "Já tem conta? Entrar" e o link do erro "Já existe uma conta com este email".
  final VoidCallback aoEntrar;
  final VoidCallback? aoApple;
  final VoidCallback? aoGoogle;

  /// No browser, o botão do próprio Google.
  final Widget? googleWeb;

  @override
  State<CriarContaEcra> createState() => _CriarContaEcraState();
}

class _CriarContaEcraState extends State<CriarContaEcra> {
  final _nome = TextEditingController();
  final _email = TextEditingController();
  final _senha = TextEditingController();
  bool _termos = false;
  bool _ver = false;
  bool _aCriar = false;
  ErrosRegisto _erros = const ErrosRegisto();
  String? _erroGeral;
  bool _emailExiste = false;

  @override
  void dispose() {
    _nome.dispose();
    _email.dispose();
    _senha.dispose();
    super.dispose();
  }

  Future<void> _criar() async {
    final erros = validarRegisto(
      nome: _nome.text,
      email: _email.text,
      senha: _senha.text,
      aceitaTermos: _termos,
    );
    setState(() {
      _erros = erros;
      _erroGeral = null;
      _emailExiste = false;
    });
    if (erros.temErros) return;
    setState(() => _aCriar = true);
    final codigo = await widget.aoCriar(
      _nome.text.trim(),
      _email.text.trim(),
      _senha.text,
    );
    if (!mounted) return;
    setState(() {
      _aCriar = false;
      switch (codigo) {
        case null:
          break;
        case 'email_ja_existe':
          _emailExiste = true;
        case 'sem_rede':
          _erroGeral =
              'Sem ligação à internet. Verifique a ligação e tente outra vez.';
        case 'demasiadas_tentativas':
          _erroGeral =
              'Demasiadas tentativas. Espere um pouco e tente outra vez.';
        case 'pedido_invalido':
          _erroGeral =
              'Algum dado não é válido. Confirme o email e a palavra-passe.';
        default:
          _erroGeral = 'Não foi possível criar a conta. Tente outra vez.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return CorpoComRodape(
      conteudo: [
        Align(alignment: Alignment.centerLeft, child: _Voltar()),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      'Criar conta',
                      style: TextStyle(
                        fontSize: 22,
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.55,
                        color: t.texto,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Contas são para quem cuida. Adicione as pessoas depois.',
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                      color: t.texto2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const AnimacaoLottie(
              asset: 'assets/lottie/registo.json',
              largura: 150,
              altura: 150,
              repetir: true,
              descricao: 'Animação de boas-vindas',
            ),
          ],
        ),
        const SizedBox(height: 12),
        CampoTexto(
          rotulo: 'Como quer ser chamado?',
          dica: 'Ex.: Ana',
          controlador: _nome,
          erro: _erros.nome,
          maxLength: 60,
          altura: 52,
          espacoRotulo: 6,
          aoMudar: (_) => setState(
            () => _erros = ErrosRegisto(
              email: _erros.email,
              senha: _erros.senha,
              termos: _erros.termos,
            ),
          ),
        ),
        const SizedBox(height: 12),
        CampoTexto(
          rotulo: 'Email',
          dica: 'nome@exemplo.pt',
          controlador: _email,
          teclado: TextInputType.emailAddress,
          maxLength: 254,
          altura: 52,
          espacoRotulo: 6,
          erro: _emailExiste
              ? 'Já existe uma conta com este email.'
              : _erros.email,
          aoMudar: (_) => setState(() {
            _emailExiste = false;
            _erros = ErrosRegisto(
              nome: _erros.nome,
              senha: _erros.senha,
              termos: _erros.termos,
            );
          }),
        ),
        if (_emailExiste)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: widget.aoEntrar,
              child: Text(
                'Entrar com este email',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: t.primaria,
                ),
              ),
            ),
          ),
        const SizedBox(height: 12),
        _CampoSenha(
          aoSubmeter: _aCriar ? null : _criar,
          controlador: _senha,
          erro: _erros.senha,
          ver: _ver,
          aoVer: () => setState(() => _ver = !_ver),
          aoMudar: (_) => setState(
            () => _erros = ErrosRegisto(
              nome: _erros.nome,
              email: _erros.email,
              termos: _erros.termos,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Semantics(
          container: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() {
              _termos = !_termos;
              _erros = ErrosRegisto(
                nome: _erros.nome,
                email: _erros.email,
                senha: _erros.senha,
              );
            }),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: _CaixaMarcar(
                    key: const ValueKey('caixa-termos'),
                    marcada: _termos,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.zero,
                    child: Text(
                      'Aceito os Termos, a Política de Privacidade e o tratamento dos dados de saúde para gerir as tomas.',
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                        color: t.texto2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_erros.termos != null)
          Semantics(
            liveRegion: true,
            child: Text(
              _erros.termos!,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: t.mau,
              ),
            ),
          ),
        if (_erroGeral != null) ...[
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
                _erroGeral!,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: t.mauTexto,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Botao(
          texto: _aCriar ? 'A criar…' : 'Criar conta',
          altura: 56,
          raio: 20,
          tamanhoTexto: 18,
          aoTocar: _aCriar ? null : _criar,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: Container(height: 1, color: t.linha)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'ou registe-se com',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: t.texto2,
                ),
              ),
            ),
            Expanded(child: Container(height: 1, color: t.linha)),
          ],
        ),
        const SizedBox(height: 12),
        BotoesSso(
          aoApple: widget.aoApple ?? () {},
          aoGoogle: widget.aoGoogle ?? () {},
          googleWeb: widget.googleWeb,
        ),
      ],
      espacoRodape: 12,
      rodape: [
        Center(
          child: Text.rich(
            TextSpan(
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: t.texto2,
              ),
              children: [
                const TextSpan(text: 'Já tem conta? '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: InkWell(
                    onTap: widget.aoEntrar,
                    child: Text(
                      'Entrar',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: t.primaria,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Voltar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Semantics(
      button: true,
      label: 'Voltar',
      excludeSemantics: true,
      child: Material(
        color: t.superficie,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.of(context).maybePop(),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: t.sombra,
            ),
            child: Center(
              child: Icone(Icones.voltar, tamanho: 24, cor: t.texto),
            ),
          ),
        ),
      ),
    );
  }
}

class _CampoSenha extends StatelessWidget {
  const _CampoSenha({
    required this.controlador,
    required this.erro,
    required this.ver,
    required this.aoVer,
    required this.aoMudar,
    this.aoSubmeter,
  });
  final TextEditingController controlador;
  final String? erro;
  final VoidCallback? aoSubmeter;
  final bool ver;
  final VoidCallback aoVer;
  final ValueChanged<String> aoMudar;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    OutlineInputBorder borda(Color c) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: c, width: 2),
    );
    final cor = erro == null ? t.linha : t.mau;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Palavra-passe',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: t.texto,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 52,
          child: TextField(
            controller: controlador,
            obscureText: !ver,
            autocorrect: false,
            enableSuggestions: false,
            maxLength: 128,
            autofillHints: const [AutofillHints.newPassword],
            textInputAction: TextInputAction.done,
            onSubmitted: aoSubmeter == null ? null : (_) => aoSubmeter!(),
            onChanged: aoMudar,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: t.texto,
            ),
            decoration: InputDecoration(
              counterText: '',
              hintText: 'Pelo menos 8 caracteres',
              hintStyle: TextStyle(
                color: t.texto2.withValues(alpha: .85),
                fontWeight: FontWeight.w600,
              ),
              filled: true,
              fillColor: t.superficie,
              contentPadding: const EdgeInsets.fromLTRB(16, 0, 4, 0),
              border: borda(cor),
              enabledBorder: borda(cor),
              focusedBorder: borda(erro == null ? t.primaria : t.mau),
              suffixIcon: IconButton(
                tooltip: ver
                    ? 'Esconder palavra-passe'
                    : 'Mostrar palavra-passe',
                onPressed: aoVer,
                icon: Icon(
                  ver
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 22,
                  color: t.texto2,
                ),
              ),
            ),
          ),
        ),
        if (erro != null) ...[
          const SizedBox(height: 6),
          Semantics(
            liveRegion: true,
            child: Text(
              erro!,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: t.mau,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// "Conta criada!" (design: Sucesso-Conta). Texto neutro quanto ao género.
class SucessoContaEcra extends StatelessWidget {
  const SucessoContaEcra({
    super.key,
    required this.nome,
    required this.aoAdicionarPessoa,
    required this.aoDepois,
    this.aoSoParaMim,
  });
  final String nome;
  final VoidCallback aoAdicionarPessoa;
  final VoidCallback aoDepois;

  /// "Usar só para mim": o cuidador é também quem toma os medicamentos.
  final VoidCallback? aoSoParaMim;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return EcraResultado(
      topo: TopoResultado(
        titulo: 'Conta criada!',
        texto: aoSoParaMim == null
            ? 'Olá, $nome. Já pode adicionar a primeira pessoa.'
            : 'Olá, $nome. Pode usar o Amparo só para si ou acompanhar outra pessoa.',
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
                Icones.escudoVisto,
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
                    'Conta protegida',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: t.texto,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Entrou com email e palavra-passe',
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
        if (aoSoParaMim != null)
          Botao(
            texto: 'Usar só para mim',
            altura: 60,
            raio: 22,
            tamanhoTexto: 18,
            aoTocar: aoSoParaMim,
          ),
        Botao(
          texto: aoSoParaMim == null
              ? 'Adicionar a primeira pessoa'
              : 'Acompanhar outra pessoa',
          altura: 60,
          raio: 22,
          tamanhoTexto: 18,
          fundo: aoSoParaMim == null ? null : t.primariaSuave,
          cor: aoSoParaMim == null ? null : t.sobrePrimariaSuave,
          aoTocar: aoAdicionarPessoa,
        ),
        AcaoTexto(texto: 'Fazer isto mais tarde', aoTocar: aoDepois),
      ],
    );
  }
}

/// A caixa de aceitar do design: 24 px, cantos de 8; marcada fica verde-azulada com o visto.
class _CaixaMarcar extends StatelessWidget {
  const _CaixaMarcar({super.key, required this.marcada});
  final bool marcada;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: marcada ? t.primaria : t.superficie2,
        borderRadius: BorderRadius.circular(8),
        border: marcada ? null : Border.all(color: t.texto2, width: 2),
      ),
      child: marcada
          ? Icone(Icones.visto, tamanho: 16, cor: t.sobrePrimaria, traco: 2.6)
          : null,
    );
  }
}
