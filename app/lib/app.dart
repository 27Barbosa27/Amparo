import 'package:material_ui/material_ui.dart';

import 'dados/api.dart';
import 'dados/autenticacao.dart';
import 'dados/repositorio.dart';
import 'dominio/modelos.dart';
import 'estado/hoje_controlador.dart';
import 'tema/tema.dart';
import 'tema/tokens.dart';
import 'ui/componentes/base.dart';
import 'ui/componentes/ilha_navegacao.dart';
import 'ui/ecras/cuidador_hoje.dart';
import 'ui/ecras/entrar.dart';
import 'ui/ecras/idoso_hoje.dart';
import 'ui/ecras/outros.dart';
import 'ui/ecras/sucesso_marcada.dart';

/// A raiz da app. Recebe o repositório (dados falsos por agora, a API depois) e o relógio (para os testes).
class AmparoApp extends StatefulWidget {
  const AmparoApp({
    super.key,
    required this.repositorio,
    required this.autenticacao,
    this.relogio = DateTime.now,
    this.escuroInicial = true,
    this.telaInicial = '',
    this.credenciaisDev,
  });

  final Repositorio repositorio;
  final Autenticacao autenticacao;
  final Relogio relogio;
  final bool escuroInicial;

  /// Só para desenvolvimento e capturas: abre direto num ecrã (`entrar-erro`, `hoje`, `simples`, `sucesso`).
  final String telaInicial;

  /// Só para desenvolvimento: entra sozinho com estas credenciais quando se abre direto num ecrã (`--dart-define`).
  final ({String email, String senha})? credenciaisDev;

  @override
  State<AmparoApp> createState() => _AmparoAppState();
}

enum _Modo { aArrancar, entrar, semPessoas, cuidador, previewPessoa, sucesso }

class _AmparoAppState extends State<AmparoApp> {
  late bool _escuro = widget.escuroInicial;

  @override
  void initState() {
    super.initState();
    _arrancar();
  }

  /// Retoma a sessão guardada, se houver; em desenvolvimento pode abrir direto num ecrã.
  Future<void> _arrancar() async {
    try {
      final dev =
          widget.telaInicial.isNotEmpty &&
          widget.telaInicial != 'entrar' &&
          widget.telaInicial != 'entrar-erro';
      var dentro = await widget.autenticacao.restaurar();
      if (!dentro && dev && widget.credenciaisDev != null) {
        dentro =
            await widget.autenticacao.entrar(
              widget.credenciaisDev!.email,
              widget.credenciaisDev!.senha,
            ) ==
            null;
      }
      if (dentro) {
        await _abrirSessao();
        if (dev && _controlador != null) await _ecraDeDesenvolvimento();
      } else {
        _modo = _Modo.entrar;
      }
    } on ErroApi {
      _modo = _Modo.entrar;
    }
    if (mounted) setState(() {});
  }

  Future<void> _ecraDeDesenvolvimento() async {
    await _controlador!.carregar();
    switch (widget.telaInicial) {
      case 'simples':
        _modo = _Modo.previewPessoa;
      case 'sucesso':
        final pendentes = _controlador!.tomas.where(
          (t) => t.estado == EstadoToma.pendente,
        );
        if (pendentes.isNotEmpty) {
          await _controlador!.marcarTomada(pendentes.first);
          _tomaDoSucesso = pendentes.first.id;
          _modo = _Modo.sucesso;
        }
      default:
    }
  }

  _Modo _modo = _Modo.aArrancar;
  String? _tomaDoSucesso;
  HojeControlador? _controlador;
  List<Perfil> _perfis = const [];
  int _separador = 0;

  /// Entra pela API (ou pelos dados falsos) e abre a primeira pessoa. Devolve o código de erro, se houver.
  Future<String?> _entrar(String email, String senha) async {
    final erro = await widget.autenticacao.entrar(email, senha);
    if (erro != null) return erro;
    try {
      await _abrirSessao();
    } on ErroApi catch (e) {
      return e.codigo;
    }
    return null;
  }

  Future<void> _abrirSessao() async {
    _perfis = await widget.repositorio.perfis();
    if (_perfis.isEmpty) {
      _modo = _Modo.semPessoas;
    } else {
      _abrirPerfil(_perfis.first);
      _modo = _Modo.cuidador;
    }
    if (mounted) setState(() {});
  }

  Future<void> _terminarSessao() async {
    await widget.autenticacao.sair();
    _voltarAEntrar();
  }

  void _voltarAEntrar() {
    _controlador?.dispose();
    _controlador = null;
    _separador = 0;
    if (mounted) setState(() => _modo = _Modo.entrar);
  }

  void _abrirPerfil(Perfil p) {
    _controlador?.dispose();
    _controlador = HojeControlador(
      repositorio: widget.repositorio,
      perfil: p,
      relogio: widget.relogio,
      cuidador: widget.autenticacao.nome,
      aoSessaoExpirada: _voltarAEntrar,
    )..carregar();
    setState(() {});
  }

  Future<void> _trocarPerfil(BuildContext context) async {
    final escolhido = await showModalBottomSheet<Perfil>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (c) =>
          _EscolherPerfil(perfis: _perfis, atual: _controlador!.perfil),
    );
    if (escolhido != null && escolhido.id != _controlador!.perfil.id) {
      _abrirPerfil(escolhido);
    }
  }

  @override
  void dispose() {
    _controlador?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = _escuro ? Tokens.escuroTema : Tokens.claroTema;
    return MaterialApp(
      title: 'Amparo',
      debugShowCheckedModeBanner: false,
      theme: criarTema(tokens),
      locale: const Locale('pt', 'PT'),
      supportedLocales: const [Locale('pt', 'PT')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Builder(
        builder: (context) =>
            Scaffold(body: FundoGradiente(child: _corpo(context))),
      ),
    );
  }

  void _aviso(BuildContext context, String texto) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  Widget _corpo(BuildContext context) {
    final c = _controlador;
    switch (_modo) {
      case _Modo.aArrancar:
        return const Center(child: CircularProgressIndicator());
      case _Modo.semPessoas:
        return _SemPessoas(aoTerminarSessao: _terminarSessao);
      case _Modo.entrar:
        return EntrarEcra(
          aoEntrar: _entrar,
          erroInicial: widget.telaInicial == 'entrar-erro'
              ? 'credenciais_invalidas'
              : null,
          aoApple: () => _aviso(
            context,
            'Entrar com a Apple liga-se quando a conta Apple Developer estiver configurada.',
          ),
          aoGoogle: () => _aviso(
            context,
            'Entrar com a Google liga-se quando o projeto Google estiver configurado.',
          ),
          aoTerCodigo: () =>
              _aviso(context, 'O ecrã "Tenho um código" vem a seguir.'),
          aoCriarConta: () =>
              _aviso(context, 'O ecrã "Criar conta" vem a seguir.'),
          aoEsquecerSenha: () =>
              _aviso(context, 'A recuperação de palavra-passe vem a seguir.'),
        );
      case _Modo.sucesso:
        return SucessoMarcadaEcra(
          controlador: c!,
          tomaId: _tomaDoSucesso ?? '',
          aoVoltar: () => setState(() => _modo = _Modo.cuidador),
        );
      case _Modo.previewPessoa:
        return Stack(
          children: [
            IdosoHoje(controlador: c!),
            Positioned(
              left: 20,
              right: 20,
              bottom: 20,
              child: SafeArea(
                child: Botao(
                  texto: 'Sair da pré-visualização',
                  icone: Icons.close,
                  altura: 52,
                  fundo: context.t.superficie,
                  cor: context.t.texto,
                  contorno: context.t.linha,
                  aoTocar: () => setState(() => _modo = _Modo.cuidador),
                ),
              ),
            ),
          ],
        );
      case _Modo.cuidador:
        final destinos = const [
          DestinoNav('Hoje', Icons.calendar_today_outlined),
          DestinoNav('Receitas', Icons.description_outlined),
          DestinoNav('Mais', Icons.settings_outlined),
        ];
        final pagina = switch (_separador) {
          0 => CuidadorHoje(
            controlador: c!,
            aoTrocarPerfil: () => _trocarPerfil(context),
          ),
          1 => ReceitasEcra(controlador: c!),
          _ => MaisEcra(
            escuro: _escuro,
            aoMudarTema: (v) => setState(() => _escuro = v),
            aoVerComoAPessoaVe: () =>
                setState(() => _modo = _Modo.previewPessoa),
            aoTerminarSessao: _terminarSessao,
          ),
        };
        return Stack(
          children: [
            pagina,
            IlhaNavegacao(
              destinos: destinos,
              atual: _separador,
              aoMudar: (i) => setState(() => _separador = i),
            ),
          ],
        );
    }
  }
}

class _EscolherPerfil extends StatelessWidget {
  const _EscolherPerfil({required this.perfis, required this.atual});
  final List<Perfil> perfis;
  final Perfil atual;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Material(
        color: t.superficie,
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text('Quem vai acompanhar?', style: Estilos.titulo(t)),
              ),
              const SizedBox(height: 12),
              for (final p in perfis)
                Semantics(
                  button: true,
                  selected: p.id == atual.id,
                  label: p.nome,
                  excludeSemantics: true,
                  child: ListTile(
                    minTileHeight: 56,
                    leading: Avatar(inicial: p.inicial, tamanho: 40),
                    title: Text(
                      p.nome,
                      style: Estilos.corpo(t, peso: FontWeight.w700),
                    ),
                    trailing: p.id == atual.id
                        ? Icon(Icons.check, color: t.primaria)
                        : null,
                    onTap: () => Navigator.of(context).pop(p),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Entrou, mas ainda não há ninguém para acompanhar. O ecrã "Adicionar pessoa" vem a seguir.
class _SemPessoas extends StatelessWidget {
  const _SemPessoas({required this.aoTerminarSessao});
  final VoidCallback aoTerminarSessao;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text('Quem vai acompanhar?', style: Estilos.titulo(t)),
                ),
                const SizedBox(height: 12),
                Cartao(
                  child: Text(
                    'Ainda não adicionou ninguém. O ecrã "Adicionar pessoa" vem a seguir.',
                    style: Estilos.corpo(t),
                  ),
                ),
                const SizedBox(height: 16),
                Botao(
                  texto: 'Terminar sessão',
                  icone: Icons.logout,
                  fundo: t.superficie,
                  cor: t.texto,
                  contorno: t.linha,
                  aoTocar: aoTerminarSessao,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
