import 'package:material_ui/material_ui.dart';

import '../../tema/tema.dart';
import '../../tema/tokens.dart';
import '../componentes/base.dart';

/// Entrar (só cuidadores têm conta). Sem botão de Face ID: o iPhone já preenche as credenciais
/// (`autofillHints` certos) e a biometria da app serve só para desbloquear ao abrir.
class EntrarEcra extends StatefulWidget {
  const EntrarEcra({super.key, required this.aoEntrar, this.aoCriarConta});

  /// Recebe email e palavra-passe. Devolve o código de erro estável (ver o plano) ou nulo se correu bem.
  final Future<String?> Function(String email, String senha) aoEntrar;
  final VoidCallback? aoCriarConta;

  @override
  State<EntrarEcra> createState() => _EntrarEcraState();
}

class _EntrarEcraState extends State<EntrarEcra> {
  final _email = TextEditingController();
  final _senha = TextEditingController();
  bool _aEntrar = false;
  bool _ver = false;
  String? _erro;

  @override
  void dispose() {
    _email.dispose();
    _senha.dispose();
    super.dispose();
  }

  static const _mensagens = {
    'credenciais_invalidas': 'Email ou palavra-passe errados.',
    'demasiadas_tentativas':
        'Demasiadas tentativas. Espere um pouco e tente outra vez.',
    'sem_rede': 'Sem ligação. Verifique a internet e tente outra vez.',
  };

  Future<void> _submeter() async {
    final email = _email.text.trim();
    if (email.isEmpty || _senha.text.isEmpty) {
      setState(() => _erro = 'Escreva o email e a palavra-passe.');
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
      _erro = codigo == null
          ? null
          : (_mensagens[codigo] ?? 'Não foi possível entrar. Tente outra vez.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Amparo',
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.9,
                    color: t.primaria,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Entre na sua conta de cuidador',
                style: Estilos.subtitulo(t),
              ),
              const SizedBox(height: 28),
              AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Campo(
                      controlador: _email,
                      rotulo: 'Email',
                      teclado: TextInputType.emailAddress,
                      dicas: const [AutofillHints.email],
                    ),
                    const SizedBox(height: 12),
                    _Campo(
                      controlador: _senha,
                      rotulo: 'Palavra-passe',
                      escondido: !_ver,
                      dicas: const [AutofillHints.password],
                      aoSubmeter: _submeter,
                      sufixo: IconButton(
                        tooltip: _ver
                            ? 'Esconder a palavra-passe'
                            : 'Mostrar a palavra-passe',
                        onPressed: () => setState(() => _ver = !_ver),
                        icon: Icon(
                          _ver ? Icons.visibility_off : Icons.visibility,
                          color: t.texto2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_erro != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: t.mauSuave,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      _erro!,
                      style: Estilos.corpo(
                        t,
                        peso: FontWeight.w700,
                        cor: t.mauTexto,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Botao(
                texto: _aEntrar ? 'A entrar…' : 'Entrar',
                altura: 56,
                raio: 18,
                tamanhoTexto: 17,
                aoTocar: _aEntrar ? null : _submeter,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: Divider(color: t.linha)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('ou', style: Estilos.subtitulo(t)),
                  ),
                  Expanded(child: Divider(color: t.linha)),
                ],
              ),
              const SizedBox(height: 20),
              // O "Entrar com a Apple" e com a Google aparecem sempre juntos (regra da Apple). Ligam-se quando houver as contas.
              Botao(
                texto: 'Continuar com a Apple',
                icone: Icons.apple,
                altura: 52,
                raio: 18,
                fundo: t.superficie,
                cor: t.texto,
                aoTocar: null,
              ),
              const SizedBox(height: 10),
              Botao(
                texto: 'Continuar com a Google',
                icone: Icons.g_mobiledata,
                altura: 52,
                raio: 18,
                fundo: t.superficie,
                cor: t.texto,
                aoTocar: null,
              ),
              const SizedBox(height: 24),
              Center(
                child: TextButton(
                  onPressed: widget.aoCriarConta,
                  child: Text(
                    'Criar conta de cuidador',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: t.primaria,
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

class _Campo extends StatelessWidget {
  const _Campo({
    required this.controlador,
    required this.rotulo,
    this.teclado,
    this.escondido = false,
    this.dicas,
    this.sufixo,
    this.aoSubmeter,
  });
  final TextEditingController controlador;
  final String rotulo;
  final TextInputType? teclado;
  final bool escondido;
  final Iterable<String>? dicas;
  final Widget? sufixo;
  final VoidCallback? aoSubmeter;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return TextField(
      controller: controlador,
      keyboardType: teclado,
      obscureText: escondido,
      autofillHints: dicas,
      autocorrect: false,
      enableSuggestions: false,
      onSubmitted: aoSubmeter == null ? null : (_) => aoSubmeter!(),
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: t.texto,
      ),
      decoration: InputDecoration(
        labelText: rotulo,
        labelStyle: TextStyle(color: t.texto2),
        filled: true,
        fillColor: t.superficie,
        suffixIcon: sufixo,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: t.linha),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: t.linha),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: t.primaria, width: 2),
        ),
      ),
    );
  }
}
