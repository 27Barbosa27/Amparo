import 'package:material_ui/material_ui.dart';

import 'dados/api.dart';
import 'dados/autenticacao.dart';
import 'dados/repositorio.dart';
import 'dominio/modelos.dart';
import 'estado/hoje_controlador.dart';
import 'estado/receitas_controlador.dart';
import 'tema/tema.dart';
import 'tema/tokens.dart';
import 'ui/componentes/base.dart';
import 'ui/componentes/formulario.dart';
import 'ui/componentes/ilha_navegacao.dart';
import 'ui/ecras/adicionar_pessoa.dart';
import 'ui/ecras/criar_conta.dart';
import 'ui/ecras/cuidador_hoje.dart';
import 'ui/ecras/entrar.dart';
import 'ui/ecras/idoso_hoje.dart';
import 'ui/ecras/outros.dart';
import 'ui/ecras/receita_nova.dart';
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

  /// Só para abrir ecrãs empurrados em desenvolvimento (`TELA=pessoa-nova`, `receita-nova`).
  final _navegador = GlobalKey<NavigatorState>();

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
      case 'receitas':
        _separador = 1;
        await _receitas?.carregar();
      case 'pessoa-nova' || 'receita-nova':
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = _navegador.currentContext;
          if (ctx == null || !ctx.mounted) return;
          if (widget.telaInicial == 'pessoa-nova') {
            _adicionarPessoa(ctx);
          } else {
            _fluxoReceita(ctx, _controlador!.perfil);
          }
        });
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
  ReceitasControlador? _receitas;
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
    _receitas?.dispose();
    _receitas = null;
    _separador = 0;
    if (mounted) setState(() => _modo = _Modo.entrar);
  }

  void _abrirPerfil(Perfil p) {
    _controlador?.dispose();
    _receitas?.dispose();
    _receitas = ReceitasControlador(
      repositorio: widget.repositorio,
      perfil: p,
      aoSessaoExpirada: _voltarAEntrar,
    )..carregar();
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
    if (escolhido == null || !context.mounted) return;
    if (escolhido.id == _novaPessoa.id) {
      _adicionarPessoa(context);
    } else if (escolhido.id != _controlador!.perfil.id) {
      _abrirPerfil(escolhido);
    }
  }

  /// "Criar conta": regista o cuidador, abre a sessão e oferece adicionar a primeira pessoa.
  void _criarConta(BuildContext context) {
    Navigator.of(context).push(
      rotaPagina<void>(
        Builder(
          builder: (ctx) => CriarContaEcra(
            aoEntrar: () => Navigator.of(ctx).maybePop(),
            aoApple: () => _aviso(
              ctx,
              'Registar com a Apple liga-se quando a conta Apple Developer estiver configurada.',
            ),
            aoGoogle: () => _aviso(
              ctx,
              'Registar com a Google liga-se quando o projeto Google estiver configurado.',
            ),
            aoCriar: (nome, email, senha) async {
              final erro = await widget.autenticacao.registar(
                nome,
                email,
                senha,
              );
              if (erro != null) return erro;
              try {
                _perfis = await widget.repositorio.perfis();
              } on ErroApi catch (e) {
                return e.codigo;
              }
              if (_perfis.isEmpty) {
                _modo = _Modo.semPessoas;
              } else {
                _abrirPerfil(_perfis.first);
                _modo = _Modo.cuidador;
              }
              if (mounted) setState(() {});
              if (!ctx.mounted) return null;
              Navigator.of(ctx).pushReplacement(
                rotaPagina<void>(
                  Builder(
                    builder: (c2) => SucessoContaEcra(
                      nome: nome,
                      aoAdicionarPessoa: () {
                        Navigator.of(c2).popUntil((r) => r.isFirst);
                        final raiz = _navegador.currentContext;
                        if (raiz != null && raiz.mounted) {
                          _adicionarPessoa(raiz);
                        }
                      },
                      aoDepois: () =>
                          Navigator.of(c2).popUntil((r) => r.isFirst),
                    ),
                  ),
                ),
              );
              return null;
            },
          ),
        ),
      ),
    );
  }

  /// "Adicionar receita": formulário, geração das tomas no servidor e resultado.
  void _fluxoReceita(BuildContext context, Perfil perfil) {
    FluxoReceita(
      repositorio: widget.repositorio,
      perfil: perfil,
      relogio: widget.relogio,
      aoVerHoje: () {
        _controlador?.carregar();
        _receitas?.carregar();
        setState(() => _separador = 0);
      },
    ).abrir(context);
  }

  /// "Adicionar pessoa": cria o perfil, passa a acompanhá-lo e mostra o resultado.
  void _adicionarPessoa(BuildContext context) {
    Navigator.of(context).push(
      rotaPagina<void>(
        Builder(
          builder: (ctx) => AdicionarPessoaEcra(
            aoCriar: (nova) async {
              try {
                final pessoa = await widget.repositorio.criarPessoa(nova);
                _perfis = await widget.repositorio.perfis();
                _modo = _Modo.cuidador;
                _separador = 0;
                _abrirPerfil(pessoa);
                if (!ctx.mounted) return null;
                Navigator.of(ctx).pushReplacement(
                  rotaPagina<void>(
                    Builder(
                      builder: (c2) => SucessoPessoaEcra(
                        pessoa: pessoa,
                        alarmesNaPessoa: nova.alarmesEm == AlarmesEm.pessoa,
                        aoLigarTelemovel: () => _aviso(
                          c2,
                          'O ecrã "Ligar o telemóvel" vem a seguir.',
                        ),
                        aoAdicionarReceita: () => _fluxoReceita(c2, pessoa),
                        aoConcluir: () =>
                            Navigator.of(c2).popUntil((r) => r.isFirst),
                      ),
                    ),
                  ),
                );
                return null;
              } on ErroApi catch (e) {
                return e.codigo;
              } catch (_) {
                return 'falha_ao_guardar';
              }
            },
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controlador?.dispose();
    _receitas?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = _escuro ? Tokens.escuroTema : Tokens.claroTema;
    return MaterialApp(
      navigatorKey: _navegador,
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
        return _SemPessoas(
          aoAdicionar: () => _adicionarPessoa(context),
          aoTerminarSessao: _terminarSessao,
        );
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
          aoCriarConta: () => _criarConta(context),
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
          1 => ReceitasEcra(
            controlador: _receitas!,
            aoAdicionar: () => _fluxoReceita(context, c!.perfil),
            aoPedirRenovacao: (r) => _aviso(
              context,
              'O pedido de renovação ao médico vem a seguir.',
            ),
          ),
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
              aoMudar: (i) {
                if (i == 1) _receitas?.carregar();
                setState(() => _separador = i);
              },
            ),
          ],
        );
    }
  }
}

/// Marca o "Adicionar pessoa" do seletor (não é uma pessoa verdadeira).
const _novaPessoa = Perfil(id: '__nova__', nome: '');

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
              Semantics(
                button: true,
                label: 'Adicionar pessoa',
                excludeSemantics: true,
                child: ListTile(
                  minTileHeight: 56,
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: t.linha, width: 2),
                    ),
                    child: Icon(Icons.add, color: t.primaria),
                  ),
                  title: Text(
                    'Adicionar pessoa',
                    style: Estilos.corpo(
                      t,
                      peso: FontWeight.w700,
                      cor: t.primaria,
                    ),
                  ),
                  onTap: () => Navigator.of(context).pop(_novaPessoa),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Entrou, mas ainda não há ninguém para acompanhar.
class _SemPessoas extends StatelessWidget {
  const _SemPessoas({
    required this.aoAdicionar,
    required this.aoTerminarSessao,
  });
  final VoidCallback aoAdicionar;
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
                    'Ainda não adicionou ninguém. Comece por adicionar a primeira pessoa.',
                    style: Estilos.corpo(t),
                  ),
                ),
                const SizedBox(height: 16),
                Botao(
                  texto: 'Adicionar pessoa',
                  icone: Icons.add,
                  altura: 56,
                  raio: 20,
                  tamanhoTexto: 17,
                  aoTocar: aoAdicionar,
                ),
                const SizedBox(height: 10),
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
