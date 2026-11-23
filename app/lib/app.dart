import 'package:material_ui/material_ui.dart';

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
    this.relogio = DateTime.now,
    this.escuroInicial = true,
    this.telaInicial = '',
  });

  final Repositorio repositorio;
  final Relogio relogio;
  final bool escuroInicial;

  /// Só para desenvolvimento e capturas: abre direto num ecrã (`entrar-erro`, `hoje`, `simples`, `sucesso`).
  final String telaInicial;

  @override
  State<AmparoApp> createState() => _AmparoAppState();
}

enum _Modo { entrar, cuidador, previewPessoa, sucesso }

class _AmparoAppState extends State<AmparoApp> {
  late bool _escuro = widget.escuroInicial;

  @override
  void initState() {
    super.initState();
    if (widget.telaInicial.isNotEmpty &&
        widget.telaInicial != 'entrar' &&
        widget.telaInicial != 'entrar-erro') {
      _arranqueDeDesenvolvimento();
    }
  }

  Future<void> _arranqueDeDesenvolvimento() async {
    _perfis = await widget.repositorio.perfis();
    _abrirPerfil(_perfis.first);
    await _controlador!.carregar();
    switch (widget.telaInicial) {
      case 'simples':
        _modo = _Modo.previewPessoa;
      case 'sucesso':
        await _controlador!.marcarTomada(
          _controlador!.tomas.firstWhere((t) => t.id == 't2'),
        );
        _modo = _Modo.sucesso;
      default:
        _modo = _Modo.cuidador;
    }
    if (mounted) setState(() {});
  }

  _Modo _modo = _Modo.entrar;
  HojeControlador? _controlador;
  List<Perfil> _perfis = const [];
  int _separador = 0;
  final String _nomeCuidador = 'Ana';

  /// Entrada de teste: aceita qualquer credencial com sentido. A autenticação a sério liga-se à API depois.
  Future<String?> _entrar(String email, String senha) async {
    _perfis = await widget.repositorio.perfis();
    _abrirPerfil(_perfis.first);
    setState(() => _modo = _Modo.cuidador);
    return null;
  }

  void _abrirPerfil(Perfil p) {
    _controlador?.dispose();
    _controlador = HojeControlador(
      repositorio: widget.repositorio,
      perfil: p,
      relogio: widget.relogio,
      cuidador: _nomeCuidador,
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
          tomaId: 't2',
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
            aoTerminarSessao: () => setState(() {
              _controlador?.dispose();
              _controlador = null;
              _separador = 0;
              _modo = _Modo.entrar;
            }),
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
