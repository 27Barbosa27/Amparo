import 'package:material_ui/material_ui.dart';

import '../../tema/tema.dart';
import '../../tema/tokens.dart';
import '../componentes/animacao.dart';
import '../componentes/estilo.dart';
import '../componentes/sso.dart';

/// Entrar, como no design: animação de boas-vindas, campos com rótulo por cima, "ou continue com"
/// (Apple e Google lado a lado), "Tenho um código" e "Criar conta". Só cuidadores têm conta.
/// Sem botão de Face ID: o iPhone já preenche as credenciais (`autofillHints`) e a biometria da app
/// serve só para desbloquear ao abrir.
class EntrarEcra extends StatefulWidget {
  const EntrarEcra({
    super.key,
    required this.aoEntrar,
    this.aoCriarConta,
    this.aoTerCodigo,
    this.aoEsquecerSenha,
    this.aoApple,
    this.aoGoogle,
    this.erroInicial,
  });

  /// Recebe email e palavra-passe. Devolve o código de erro estável (ver o plano) ou nulo se correu bem.
  final Future<String?> Function(String email, String senha) aoEntrar;
  final VoidCallback? aoCriarConta;
  final VoidCallback? aoTerCodigo;
  final VoidCallback? aoEsquecerSenha;
  final VoidCallback? aoApple;
  final VoidCallback? aoGoogle;

  /// Para mostrar o ecrã já em estado de erro (capturas e testes).
  final String? erroInicial;

  @override
  State<EntrarEcra> createState() => _EntrarEcraState();
}

class _EntrarEcraState extends State<EntrarEcra> {
  final _email = TextEditingController();
  final _senha = TextEditingController();
  bool _aEntrar = false;
  bool _ver = false;
  late String? _erro = widget.erroInicial == null
      ? null
      : (_mensagens[widget.erroInicial] ?? _generica);

  static const _generica = 'Não foi possível entrar. Tente outra vez.';
  static const _mensagens = {
    'credenciais_invalidas':
        'Email ou palavra-passe incorretos. Tente outra vez.',
    'demasiadas_tentativas':
        'Demasiadas tentativas. Espere um pouco e tente outra vez.',
    'sem_rede': 'Sem ligação. Verifique a internet e tente outra vez.',
    'campos_vazios': 'Escreva o email e a palavra-passe.',
  };

  @override
  void dispose() {
    _email.dispose();
    _senha.dispose();
    super.dispose();
  }

  Future<void> _submeter() async {
    final email = _email.text.trim();
    if (email.isEmpty || _senha.text.isEmpty) {
      setState(() => _erro = _mensagens['campos_vazios']);
      return;
    }
    setState(() {
      _aEntrar = true;
      _erro = null;
    });
    final codigo = await widget.aoEntrar(email, _senha.text);
    if (!mounted) return;
    setState(() {
      _aEntrar = false;
      _erro = codigo == null ? null : (_mensagens[codigo] ?? _generica);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final comErro = _erro != null;
    // Os blocos do design, em coluna com `gap: 14`; os dois últimos ficam encostados em baixo.
    final blocos = <Widget>[
      Column(
        children: [
          // Com erro, a animação encolhe (150x120), como no design.
          AnimacaoLottie(
            asset: 'assets/lottie/entrar.json',
            largura: comErro ? 150 : 200,
            altura: comErro ? 120 : 190,
            repetir: true,
            descricao: 'Animação de boas-vindas',
          ),
          const SizedBox(height: 10),
          Semantics(
            header: true,
            child: Text('Entrar', style: Estilos.titulo(t)),
          ),
          const SizedBox(height: 10),
          Text(
            'Que bom ver de novo. Entre para ver as tomas.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              height: 1.45,
              fontWeight: FontWeight.w500,
              color: t.texto2,
            ),
          ),
        ],
      ),
      if (comErro)
        Semantics(
          liveRegion: true,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: t.mauSuave,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, size: 22, color: t.mauTexto),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _erro!,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: t.mauTexto,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Campo(
              rotulo: 'Email',
              dica: 'nome@exemplo.pt',
              controlador: _email,
              erro: comErro,
              teclado: TextInputType.emailAddress,
              autofill: const [AutofillHints.email],
            ),
            const SizedBox(height: 14),
            _Campo(
              rotulo: 'Palavra-passe',
              dica: 'Palavra-passe',
              controlador: _senha,
              erro: comErro,
              escondido: !_ver,
              autofill: const [AutofillHints.password],
              aoSubmeter: _submeter,
              sufixo: IconButton(
                tooltip: _ver
                    ? 'Esconder palavra-passe'
                    : 'Mostrar palavra-passe',
                onPressed: () => setState(() => _ver = !_ver),
                icon: Icon(
                  _ver
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 22,
                  color: t.texto2,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: InkWell(
                onTap: widget.aoEsquecerSenha,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 32),
                  child: Align(
                    alignment: Alignment.centerRight,
                    widthFactor: 1,
                    child: Text(
                      'Esqueci-me da palavra-passe',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: t.primaria,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      Pressionavel(
        ativo: !_aEntrar,
        child: Semantics(
          button: true,
          label: 'Entrar',
          excludeSemantics: true,
          child: Material(
            color: t.primaria,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: _aEntrar ? null : _submeter,
              child: SizedBox(
                height: 56,
                child: Center(
                  child: Text(
                    _aEntrar ? 'A entrar…' : 'Entrar',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: t.sobrePrimaria,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      Row(
        children: [
          Expanded(child: Container(height: 1, color: t.linha)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'ou continue com',
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
      BotoesSso(
        aoApple: widget.aoApple ?? () {},
        aoGoogle: widget.aoGoogle ?? () {},
      ),
      Pressionavel(
        child: InkWell(
          onTap: widget.aoTerCodigo,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Center(
              child: Text.rich(
                TextSpan(
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: t.texto2,
                  ),
                  children: [
                    const TextSpan(text: 'Telemóvel de alguém?'),
                    const WidgetSpan(child: SizedBox(width: 6)),
                    TextSpan(
                      text: 'Tenho um código',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: t.primaria,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      Center(
        child: Text.rich(
          TextSpan(
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              fontWeight: FontWeight.w500,
              color: t.texto2,
            ),
            children: [
              const TextSpan(text: 'Ainda não tem conta? '),
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: InkWell(
                  onTap: widget.aoCriarConta,
                  child: Text(
                    'Criar conta',
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
    ];
    Widget bloco(int i) => EntradaSobe(
      atraso: const Duration(milliseconds: 80) * (i > 7 ? 7 : i),
      child: blocos[i],
    );
    final ultimos = blocos.length - 2;
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: CustomScrollView(
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                // A margem vai dentro do filho: o `SliverFillRemaining` ignora a do `SliverPadding`.
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 44, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < ultimos; i++) ...[
                        if (i > 0) const SizedBox(height: 14),
                        bloco(i),
                      ],
                      const Spacer(),
                      const SizedBox(height: 14),
                      bloco(ultimos),
                      const SizedBox(height: 14),
                      bloco(ultimos + 1),
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

class _Campo extends StatelessWidget {
  const _Campo({
    required this.rotulo,
    required this.dica,
    required this.controlador,
    required this.erro,
    this.teclado,
    this.escondido = false,
    this.autofill,
    this.sufixo,
    this.aoSubmeter,
  });
  final String rotulo;
  final String dica;
  final TextEditingController controlador;
  final bool erro;
  final TextInputType? teclado;
  final bool escondido;
  final Iterable<String>? autofill;
  final Widget? sufixo;
  final VoidCallback? aoSubmeter;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final cor = erro ? t.mau : t.linha;
    OutlineInputBorder borda(Color c) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: c, width: 2),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          rotulo,
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
            keyboardType: teclado,
            obscureText: escondido,
            autofillHints: autofill,
            autocorrect: false,
            enableSuggestions: false,
            onSubmitted: aoSubmeter == null ? null : (_) => aoSubmeter!(),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: t.texto,
            ),
            decoration: InputDecoration(
              hintText: dica,
              hintStyle: TextStyle(
                color: t.texto2.withValues(alpha: .85),
                fontWeight: FontWeight.w600,
              ),
              filled: true,
              fillColor: t.superficie,
              suffixIcon: sufixo,
              contentPadding: EdgeInsets.fromLTRB(
                16,
                0,
                sufixo == null ? 16 : 4,
                0,
              ),
              border: borda(cor),
              enabledBorder: borda(cor),
              focusedBorder: borda(erro ? t.mau : t.primaria),
            ),
          ),
        ),
      ],
    );
  }
}
