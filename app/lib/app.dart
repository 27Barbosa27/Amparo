import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:material_ui/material_ui.dart';

import 'dados/alarmes.dart';
import 'dados/api.dart';
import 'dados/autenticacao.dart';
import 'dados/google.dart';
import 'dados/ligacao.dart';
import 'dados/repositorio.dart';
import 'dominio/modelos.dart';
import 'estado/hoje_controlador.dart';
import 'estado/receitas_controlador.dart';
import 'tema/tema.dart';
import 'tema/tokens.dart';
import 'ui/componentes/base.dart';
import 'ui/componentes/formulario.dart';
import 'ui/componentes/estilo.dart';
import 'ui/componentes/resultado.dart';
import 'ui/componentes/icones.dart';
import 'ui/componentes/ilha_navegacao.dart';
import 'ui/ecras/adicionar_pessoa.dart';
import 'ui/ecras/alertas_cuidador.dart';
import 'ui/ecras/criar_conta.dart';
import 'ui/ecras/cuidador_hoje.dart';
import 'ui/ecras/entrar.dart';
import 'ui/ecras/historico_tomas.dart';
import 'ui/ecras/idoso_hoje.dart';
import 'ui/ecras/ligar_telemovel.dart';
import 'ui/ecras/outros.dart';
import 'ui/ecras/receita_nova.dart';
import 'ui/ecras/recuperar_senha.dart';
import 'ui/ecras/verificar_email.dart';
import 'ui/ecras/som_alarme.dart';
import 'ui/ecras/sucesso_marcada.dart';
import 'ui/ecras/tamanho_texto.dart';

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
    this.ligacao,
    this.google,
    this.alarmes = const ServicoAlarmesNulo(),
  });

  /// "Entrar com a Google". Nulo: o botão avisa que ainda não está disponível.
  final EntradaGoogle? google;

  /// O telemóvel de uma pessoa acompanhada (liga-se com um código, sem conta). Nulo: não se oferece.
  final LigacaoDispositivo? ligacao;

  /// Alarmes locais das tomas (docs/plano.md secção 3.3). `ServicoAlarmesNulo` por omissão: web e testes.
  final ServicoAlarmes alarmes;

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

enum _Modo {
  aArrancar,
  entrar,
  semPessoas,
  cuidador,
  previewPessoa,
  sucesso,
  dispositivo,
}

class _AmparoAppState extends State<AmparoApp> {
  late bool _escuro = widget.escuroInicial;

  /// Sem campo no perfil (nem design próprio): fica só nesta sessão, como o modo escuro.
  /// Se for importado, os bytes também ficam só em memória (nunca vão para a API).
  EscolhaSomAlarme _somAlarme = const SomEmbutido(SomAlarme.sino);
  List<SomImportado> _sonsImportados = [];

  /// Só para abrir ecrãs empurrados em desenvolvimento (`TELA=pessoa-nova`, `receita-nova`).
  final _navegador = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    // No browser a credencial chega pelo botão do próprio Google.
    _googleEventos = widget.google?.eventos.listen(_credencialGoogle);
    _arrancar();
  }

  StreamSubscription<CredencialGoogle>? _googleEventos;

  /// Nos telemóveis: abre a folha de contas da Google e entra com o que ela devolver.
  Future<void> _entrarComGoogle(BuildContext context) async {
    final google = widget.google;
    if (google == null || !google.configurado) {
      _aviso(
        context,
        'Entrar com a Google ainda não está configurado (falta o ID de cliente).',
      );
      return;
    }
    final r = await google.entrar();
    if (r.credencial != null) {
      await _credencialGoogle(r.credencial!);
    } else if (r.erro != null && r.erro != 'cancelado') {
      final ctx = _navegador.currentContext;
      if (ctx != null && ctx.mounted) _aviso(ctx, _mensagemGoogle(r.erro!));
    }
  }

  static String _mensagemGoogle(String codigo) => switch (codigo) {
    'sem_rede' =>
      'Sem ligação à internet. Verifique a ligação e tente outra vez.',
    'demasiadas_tentativas' =>
      'Demasiadas tentativas. Espere um pouco e tente outra vez.',
    'provedor_nao_configurado' =>
      'A entrada com a Google ainda não está ligada no servidor.',
    'google_indisponivel' =>
      'A entrada com a Google não está disponível neste dispositivo.',
    _ => 'Não foi possível entrar com a Google. Tente outra vez.',
  };

  /// Entra no servidor com o ID token. Numa conta nova pede primeiro o consentimento (dados de saúde).
  Future<void> _credencialGoogle(
    CredencialGoogle c, {
    bool aceitaTermos = false,
  }) async {
    final erro = await widget.autenticacao.entrarComGoogle(
      c.idToken,
      c.nonce,
      nome: c.nome,
      aceitaTermos: aceitaTermos,
    );
    final ctx = _navegador.currentContext;
    if (!mounted || ctx == null || !ctx.mounted) return;
    if (erro == 'consentimento_necessario') {
      final aceite = await showDialog<bool>(
        context: ctx,
        builder: (d) => AlertDialog(
          title: const Text('Criar conta com a Google'),
          content: const Text(
            'Ainda não existe uma conta Amparo para este email. Para a criar, tem de aceitar os Termos, a Política de Privacidade e o tratamento dos dados de saúde para gerir as tomas.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(d).pop(false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.of(d).pop(true),
              child: const Text('Aceitar e criar conta'),
            ),
          ],
        ),
      );
      if (aceite == true) await _credencialGoogle(c, aceitaTermos: true);
      return;
    }
    if (erro != null) {
      _aviso(ctx, _mensagemGoogle(erro));
      return;
    }
    try {
      await _abrirSessao();
    } on ErroApi catch (e) {
      if (ctx.mounted) _aviso(ctx, _mensagemGoogle(e.codigo));
      return;
    }
    _navegador.currentState?.popUntil((r) => r.isFirst);
  }

  /// Retoma a sessão guardada, se houver; em desenvolvimento pode abrir direto num ecrã.
  Future<void> _arrancar() async {
    try {
      final dev =
          widget.telaInicial.isNotEmpty &&
          widget.telaInicial != 'entrar' &&
          widget.telaInicial != 'registo' &&
          widget.telaInicial != 'entrar-erro';
      // Um telemóvel já ligado a uma pessoa abre direto no modo simples dela.
      final ligado = await widget.ligacao?.restaurar();
      if (ligado != null) {
        _abrirDispositivo(ligado);
        if (mounted) setState(() {});
        return;
      }
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
        if (widget.telaInicial == 'registo') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final ctx = _navegador.currentContext;
            if (ctx != null && ctx.mounted) _criarConta(ctx);
          });
        }
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
      case 'mais':
        _separador = 2;
      case 'sucesso-conta' || 'sucesso-pessoa':
        // Só para ver o ecrã (capturas): os botões não fazem nada.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = _navegador.currentContext;
          if (ctx == null || !ctx.mounted) return;
          Navigator.of(ctx).push(
            rotaPagina<void>(
              widget.telaInicial == 'sucesso-conta'
                  ? SucessoContaEcra(
                      nome: widget.autenticacao.nome ?? 'Ana',
                      aoAdicionarPessoa: () {},
                      aoDepois: () {},
                    )
                  : SucessoPessoaEcra(
                      pessoa: _controlador!.perfil,
                      aoLigarTelemovel: () {},
                      aoAdicionarReceita: () {},
                      aoConcluir: () {},
                    ),
            ),
          );
        });
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

  void _abrirDispositivo(Perfil perfil) {
    _controlador?.dispose();
    _controlador = HojeControlador(
      repositorio: widget.ligacao!.repositorio!,
      perfil: perfil,
      relogio: widget.relogio,
      aoSessaoExpirada: _desligarDispositivo,
      alarmes: widget.alarmes,
    )..carregar();
    _modo = _Modo.dispositivo;
  }

  /// O cuidador desligou este telemóvel (ou o token deixou de valer): volta ao início.
  Future<void> _desligarDispositivo() async {
    await widget.ligacao?.desligar();
    _voltarAEntrar();
  }

  /// "Tenho um código": liga este telemóvel a uma pessoa.
  void _terCodigo(BuildContext context) {
    final ligacao = widget.ligacao;
    if (ligacao == null) {
      _aviso(context, 'Ligar com um código ainda não está disponível.');
      return;
    }
    Navigator.of(context).push(
      rotaPagina<void>(
        CodigoEcra(
          aoLigar: (codigo) async {
            final r = await ligacao.ligar(codigo);
            if (r.perfil == null) return r.erro ?? 'falha_ao_ligar';
            final pessoa = r.perfil!;
            _abrirDispositivo(pessoa);
            if (mounted) setState(() {});
            _navegador.currentState?.pushReplacement(
              rotaPagina<void>(
                SucessoPessoaLigadoEcra(
                  pessoa: pessoa,
                  aoContinuar: () =>
                      _navegador.currentState?.popUntil((r) => r.isFirst),
                ),
              ),
            );
            return null;
          },
        ),
      ),
    );
  }

  /// "Ligar o telemóvel": mostra o código para a pessoa escrever no telemóvel dela.
  void _ligarTelemovel(BuildContext context, Perfil pessoa) {
    Navigator.of(context).push(
      rotaPagina<void>(
        LigarTelemovelEcra(
          repositorio: widget.repositorio,
          perfil: pessoa,
          relogio: widget.relogio,
          aoConcluir: () => _navegador.currentState?.popUntil((r) => r.isFirst),
        ),
      ),
    );
  }

  /// "Tamanho do texto": funciona tanto para a pessoa acompanhada como para o perfil próprio do cuidador.
  void _tamanhoTexto(BuildContext context) {
    final perfil = _controlador!.perfil;
    Navigator.of(context).push(
      rotaPagina<void>(
        TamanhoTextoEcra(
          perfil: perfil,
          proprio: eProprioCuidador(perfil, widget.autenticacao.nome),
          aoGuardar: (tamanho) async {
            try {
              final atualizado = await widget.repositorio.atualizarTamanhoTexto(
                perfil.id,
                tamanho,
              );
              _perfis = [
                for (final p in _perfis)
                  p.id == atualizado.id ? atualizado : p,
              ];
              _abrirPerfil(atualizado);
              return null;
            } on ErroApi catch (e) {
              return e.codigo;
            } catch (_) {
              return 'falha_ao_guardar';
            }
          },
        ),
      ),
    );
  }

  /// Entra pela API (ou pelos dados falsos) e abre a primeira pessoa. Devolve o código de erro, se houver.
  Future<String?> _entrar(String email, String senha) async {
    final erro = await widget.autenticacao.entrar(email, senha);
    // A palavra-passe está certa mas o email nunca foi confirmado: o servidor reenviou o código.
    if (erro == 'email_nao_verificado') {
      _verificarEmail(email);
      return null;
    }
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
      alarmes: widget.alarmes,
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

  /// "Esqueci-me da palavra-passe": pede o email; o servidor envia a ligação.
  void _recuperarSenha(BuildContext context) {
    Navigator.of(context).push(
      rotaPagina<void>(
        Builder(
          builder: (ctx) => RecuperarSenhaEcra(
            aoPedir: widget.autenticacao.pedirRecuperacao,
            aoTenhoCodigo: (email) => _novaSenha(ctx, email),
          ),
        ),
      ),
    );
  }

  void _novaSenha(BuildContext context, String email) {
    Navigator.of(context).push(
      rotaPagina<void>(
        Builder(
          builder: (ctx) => NovaSenhaEcra(
            email: email,
            aoVerificar: widget.autenticacao.verificarCodigo,
            aoRepor: widget.autenticacao.reporSenha,
            aoConcluir: () =>
                _navegador.currentState?.popUntil((r) => r.isFirst),
            aoReenviar: widget.autenticacao.pedirRecuperacao,
          ),
        ),
      ),
    );
  }

  /// Depois de a conta abrir sessão (com ou sem verificação): carrega as pessoas e mostra "Conta criada".
  Future<String?> _concluirRegisto(String nome) async {
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
    _navegador.currentState?.pushReplacement(
      rotaPagina<void>(
        Builder(
          builder: (c2) => SucessoContaEcra(
            nome: nome,
            aoAdicionarPessoa: () {
              Navigator.of(c2).popUntil((r) => r.isFirst);
              final raiz = _navegador.currentContext;
              if (raiz != null && raiz.mounted) _adicionarPessoa(raiz);
            },
            aoDepois: () => Navigator.of(c2).popUntil((r) => r.isFirst),
            aoSoParaMim: () {
              Navigator.of(c2).popUntil((r) => r.isFirst);
              final raiz = _navegador.currentContext;
              if (raiz != null && raiz.mounted) _usarSoParaMim(raiz);
            },
          ),
        ),
      ),
    );
    return null;
  }

  /// "Confirme o seu email": o código de 6 números que o servidor enviou. Vem de um registo novo (`nome`)
  /// ou de uma tentativa de entrar com a conta por confirmar.
  void _verificarEmail(String email, {String? nome, bool substituir = false}) {
    final ecra = rotaPagina<void>(
      VerificarEmailEcra(
        email: email,
        aoReenviar: widget.autenticacao.reenviarVerificacao,
        aoVerificar: (codigo) async {
          final erro = await widget.autenticacao.verificarEmail(email, codigo);
          if (erro != null) return erro;
          if (nome != null) return _concluirRegisto(nome);
          try {
            await _abrirSessao();
          } on ErroApi catch (e) {
            return e.codigo;
          }
          _navegador.currentState?.popUntil((r) => r.isFirst);
          return null;
        },
      ),
    );
    final nav = _navegador.currentState;
    if (substituir) {
      nav?.pushReplacement(ecra);
    } else {
      nav?.push(ecra);
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
            aoGoogle: () => _entrarComGoogle(ctx),
            googleWeb: widget.google?.botaoWeb(),
            aoCriar: (nome, email, senha) async {
              final erro = await widget.autenticacao.registar(
                nome,
                email,
                senha,
              );
              // O servidor mandou um código para o email: a conta só abre depois de o confirmar.
              if (erro == 'verificacao_necessaria') {
                _verificarEmail(email, nome: nome, substituir: true);
                return null;
              }
              if (erro != null) return erro;
              return _concluirRegisto(nome);
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
      // Assim que a receita fica criada, as listas passam a mostrá-la, mesmo que se saia do fluxo a meio.
      aoCriada: () {
        _controlador?.carregar();
        _receitas?.carregar();
      },
      aoVerHoje: () {
        _controlador?.carregar();
        _receitas?.carregar();
        setState(() => _separador = 0);
      },
    ).abrir(context);
  }

  /// Tocar numa receita: editar ou apagar.
  Future<void> _abrirReceita(BuildContext context, Receita r) async {
    final acao = await showModalBottomSheet<_AcaoReceita>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (c) => _FolhaReceita(receita: r),
    );
    if (acao == null || !context.mounted) return;
    switch (acao) {
      case _AcaoReceita.editar:
        _editarReceita(context, r);
      case _AcaoReceita.apagar:
        await _apagarReceita(context, r);
    }
  }

  void _editarReceita(BuildContext context, Receita r) {
    final perfil = _controlador!.perfil;
    Navigator.of(context).push(
      rotaPagina<void>(
        Builder(
          builder: (ctx) => ReceitaNovaEcra(
            perfil: perfil,
            editar: r,
            aoContinuar: (c, nova) async {
              try {
                await widget.repositorio.alterarReceita(perfil.id, r, nova);
              } on ErroApi catch (e) {
                if (c.mounted) {
                  _aviso(c, ErroGuardarEcra.mensagem(e.codigo));
                }
                return;
              } catch (_) {
                if (c.mounted) {
                  _aviso(c, ErroGuardarEcra.mensagem('falha_ao_guardar'));
                }
                return;
              }
              _receitas?.carregar();
              _controlador?.carregar();
              if (!c.mounted) return;
              Navigator.of(c).pop();
              _aviso(context, 'Receita guardada.');
            },
          ),
        ),
      ),
    );
  }

  Future<void> _apagarReceita(BuildContext context, Receita r) async {
    final certo = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Apagar ${r.medicamento}?'),
        content: const Text(
          'A receita e as tomas que ainda faltam deixam de aparecer. Isto não se pode desfazer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (certo != true || !context.mounted) return;
    try {
      await widget.repositorio.apagarReceita(_controlador!.perfil.id, r.id);
    } on ErroApi catch (e) {
      if (context.mounted) _aviso(context, ErroGuardarEcra.mensagem(e.codigo));
      return;
    } catch (_) {
      if (context.mounted) {
        _aviso(context, ErroGuardarEcra.mensagem('falha_ao_guardar'));
      }
      return;
    }
    _receitas?.carregar();
    _controlador?.carregar();
    if (context.mounted) _aviso(context, 'Receita apagada.');
  }

  /// "Usar só para mim": cria o perfil do próprio cuidador de uma vez, sem formulários (os alarmes tocam
  /// no seu telemóvel). Mais tarde pode sempre acompanhar mais pessoas.
  Future<void> _usarSoParaMim(BuildContext context) async {
    final nome = (widget.autenticacao.nome ?? '').trim();
    try {
      final eu = await widget.repositorio.criarPessoa(
        NovaPessoa(
          nome: nome.isEmpty ? 'Eu' : nome,
          alarmesEm: AlarmesEm.cuidador,
          tamanhoTexto: TamanhoTexto.normal,
        ),
      );
      _perfis = await widget.repositorio.perfis();
      _modo = _Modo.cuidador;
      _separador = 0;
      _abrirPerfil(eu);
    } on ErroApi catch (e) {
      if (context.mounted) _aviso(context, ErroGuardarEcra.mensagem(e.codigo));
    } catch (_) {
      if (context.mounted) {
        _aviso(context, ErroGuardarEcra.mensagem('falha_ao_guardar'));
      }
    }
  }

  /// "Adicionar pessoa": cria o perfil, passa a acompanhá-lo e mostra o resultado.
  void _adicionarPessoa(BuildContext context) {
    Navigator.of(context).push(
      rotaPagina<void>(
        Builder(
          builder: (ctx) => AdicionarPessoaEcra(
            nomeCuidador: widget.autenticacao.nome,
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
                        aoLigarTelemovel: () => _ligarTelemovel(c2, pessoa),
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
    _googleEventos?.cancel();
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
      // O CSS reparte a folga da altura de linha por igual em cima e em baixo; o Flutter, por omissão, não.
      builder: (context, child) => DefaultTextHeightBehavior(
        textHeightBehavior: const TextHeightBehavior(
          leadingDistribution: TextLeadingDistribution.even,
        ),
        child: child!,
      ),
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
          aoSoParaMim: () => _usarSoParaMim(context),
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
          aoGoogle: () => _entrarComGoogle(context),
          googleWeb: widget.google?.botaoWeb(),
          aoTerCodigo: () => _terCodigo(context),
          aoCriarConta: () => _criarConta(context),
          aoEsquecerSenha: () => _recuperarSenha(context),
        );
      case _Modo.sucesso:
        return SucessoMarcadaEcra(
          controlador: c!,
          tomaId: _tomaDoSucesso ?? '',
          aoVoltar: () => setState(() => _modo = _Modo.cuidador),
        );
      case _Modo.dispositivo:
        return IdosoHoje(controlador: c!);
      case _Modo.previewPessoa:
        return IdosoHoje(
          controlador: c!,
          aoSairDaPreVisualizacao: () => setState(() => _modo = _Modo.cuidador),
        );
      case _Modo.cuidador:
        // Sem "modo simples" próprio: quem cuida de si mesmo só usa estes ecrãs, por isso o
        // tamanho de texto que escolheu tem de se aplicar aqui (e não só ao IdosoHoje).
        final proprio = eProprioCuidador(
          _controlador!.perfil,
          widget.autenticacao.nome,
        );
        final destinos = const [
          DestinoNav('Principal', Icones.calendario),
          DestinoNav('Receitas', Icones.documento),
          DestinoNav('Configurações', Icones.roda),
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
            aoAbrirReceita: (r) => _abrirReceita(context, r),
          ),
          _ => MaisEcra(
            perfil: _controlador!.perfil,
            proprio: proprio,
            cuidador: widget.autenticacao.nome,
            adesao: percentagemAdesao(_controlador!.semana),
            aoMudarDePerfil: () => _trocarPerfil(context),
            aoTelemoveisLigados: () =>
                _ligarTelemovel(context, _controlador!.perfil),
            aoTamanhoTexto: () => _tamanhoTexto(context),
            aoHistorico: () => Navigator.of(context).push(
              rotaPagina<void>(
                HistoricoTomasEcra(
                  repositorio: widget.repositorio,
                  perfil: _controlador!.perfil,
                  cuidador: widget.autenticacao.nome,
                  relogio: widget.relogio,
                ),
              ),
            ),
            escuro: _escuro,
            aoMudarTema: (v) => setState(() => _escuro = v),
            somAlarme: _somAlarme,
            aoSomAlarme: () => Navigator.of(context).push(
              rotaPagina<void>(
                SomAlarmeEcra(
                  atual: _somAlarme,
                  importados: _sonsImportados,
                  aoGuardar: (s, importados) => setState(() {
                    _somAlarme = s;
                    _sonsImportados = importados;
                  }),
                ),
              ),
            ),
            aoAlertasCuidador: () => Navigator.of(context).push(
              rotaPagina<void>(
                AlertasCuidadorEcra(
                  repositorio: widget.repositorio,
                  perfil: _controlador!.perfil,
                  proprio: proprio,
                ),
              ),
            ),
            aoVerComoAPessoaVe: () =>
                setState(() => _modo = _Modo.previewPessoa),
            aoTerminarSessao: _terminarSessao,
          ),
        };
        final conteudo = Stack(
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
        return proprio
            ? EscalarTexto(
                escala: _controlador!.perfil.tamanhoTexto.escala,
                child: conteudo,
              )
            : conteudo;
    }
  }
}

enum _AcaoReceita { editar, apagar }

/// A folha de uma receita: editar ou apagar (o mesmo vidro da folha "Trocar de pessoa").
class _FolhaReceita extends StatelessWidget {
  const _FolhaReceita({required this.receita});
  final Receita receita;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    const raio = Radius.circular(32);
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: raio),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          decoration: BoxDecoration(
            color: t.superficie.withValues(alpha: .58),
            borderRadius: const BorderRadius.vertical(top: raio),
          ),
          child: Semantics(
            container: true,
            label: 'Receita ${receita.medicamento}',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: t.linha,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Semantics(
                  header: true,
                  child: Text(
                    receita.medicamento,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: t.texto,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${receita.dose} · ${receita.horario}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: t.texto2,
                  ),
                ),
                const SizedBox(height: 16),
                Botao(
                  texto: 'Editar receita',
                  iconeSvg: Icones.lapis,
                  altura: 52,
                  raio: 18,
                  aoTocar: () => Navigator.of(context).pop(_AcaoReceita.editar),
                ),
                const SizedBox(height: 10),
                Botao(
                  texto: 'Apagar receita',
                  iconeSvg: Icones.lixo,
                  altura: 52,
                  raio: 18,
                  fundo: t.mauSuave,
                  cor: t.mauTexto,
                  aoTocar: () => Navigator.of(context).pop(_AcaoReceita.apagar),
                ),
                const SizedBox(height: 6),
                AcaoTexto(
                  texto: 'Fechar',
                  aoTocar: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
    const raio = Radius.circular(32);
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: raio),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          decoration: BoxDecoration(
            color: t.superficie.withValues(alpha: .58),
            borderRadius: const BorderRadius.vertical(top: raio),
          ),
          child: Semantics(
            container: true,
            label: 'Trocar de pessoa',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: t.linha,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Semantics(
                  header: true,
                  child: Text(
                    'Trocar de pessoa',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: t.texto,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                for (final p in perfis) ...[
                  _LinhaPessoa(
                    perfil: p,
                    ativa: p.id == atual.id,
                    aoTocar: () => Navigator.of(context).pop(p),
                  ),
                  const SizedBox(height: 10),
                ],
                Pressionavel(
                  child: Semantics(
                    button: true,
                    label: 'Adicionar pessoa',
                    excludeSemantics: true,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => Navigator.of(context).pop(_novaPessoa),
                      child: CustomPaint(
                        painter: _ContornoTracejado(cor: t.linha, raio: 20),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 60),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icone(
                                const IconeDados(
                                  '<path d="M12 5v14M5 12h14"/>',
                                ),
                                tamanho: 24,
                                cor: t.texto,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Adicionar pessoa',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: t.texto,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                AcaoTexto(
                  texto: 'Fechar',
                  aoTocar: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Uma pessoa na folha: a ativa fica verde-azulada com o visto, as outras mostram um anel vazio.
class _LinhaPessoa extends StatelessWidget {
  const _LinhaPessoa({
    required this.perfil,
    required this.ativa,
    required this.aoTocar,
  });
  final Perfil perfil;
  final bool ativa;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Pressionavel(
      child: Semantics(
        button: true,
        selected: ativa,
        label: perfil.nome,
        excludeSemantics: true,
        child: Material(
          color: ativa ? t.primariaSuave : t.superficie2,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: aoTocar,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 68),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: ativa ? t.superficie : t.av2,
                      ),
                      child: Text(
                        perfil.inicial,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: ativa ? t.texto : t.sobreAv2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        perfil.nome,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: ativa ? t.sobrePrimariaSuave : t.texto,
                        ),
                      ),
                    ),
                    if (ativa)
                      SeloIcone(
                        cor: t.primaria,
                        dados: Icones.visto,
                        corIcone: t.sobrePrimaria,
                        tamanho: 26,
                        traco: 2.6,
                      )
                    else
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: t.texto2, width: 2),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// O contorno tracejado de 2 px do botão "Adicionar pessoa" (`border: 2px dashed`).
class _ContornoTracejado extends CustomPainter {
  const _ContornoTracejado({required this.cor, required this.raio});
  final Color cor;
  final double raio;

  @override
  void paint(Canvas canvas, Size size) {
    final caminho = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(1),
          Radius.circular(raio),
        ),
      );
    final pincel = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = cor;
    for (final metrica in caminho.computeMetrics()) {
      for (var d = 0.0; d < metrica.length; d += 10) {
        canvas.drawPath(
          metrica.extractPath(d, math.min(d + 6, metrica.length)),
          pincel,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_ContornoTracejado antigo) =>
      antigo.cor != cor || antigo.raio != raio;
}

/// Entrou, mas ainda não há ninguém para acompanhar.
class _SemPessoas extends StatelessWidget {
  const _SemPessoas({
    required this.aoSoParaMim,
    required this.aoAdicionar,
    required this.aoTerminarSessao,
  });
  final VoidCallback aoSoParaMim;
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
                  child: Text(
                    'Para quem é o Amparo?',
                    style: Estilos.titulo(t),
                  ),
                ),
                const SizedBox(height: 12),
                Cartao(
                  child: Text(
                    'Pode usá-lo só para si, para os seus medicamentos, ou acompanhar outra pessoa. Pode fazer as duas coisas.',
                    style: Estilos.corpo(t),
                  ),
                ),
                const SizedBox(height: 16),
                Botao(
                  texto: 'Usar só para mim',
                  icone: Icons.person,
                  altura: 56,
                  raio: 20,
                  tamanhoTexto: 17,
                  aoTocar: aoSoParaMim,
                ),
                const SizedBox(height: 10),
                Botao(
                  texto: 'Acompanhar outra pessoa',
                  icone: Icons.add,
                  altura: 56,
                  raio: 20,
                  tamanhoTexto: 17,
                  fundo: t.primariaSuave,
                  cor: t.sobrePrimariaSuave,
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
