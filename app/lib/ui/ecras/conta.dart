import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../dados/api.dart';
import '../../dados/autenticacao.dart';
import '../../tema/tokens.dart';
import '../componentes/base.dart';
import '../componentes/estilo.dart';
import '../componentes/formulario.dart';
import '../componentes/icones.dart';
import '../componentes/resultado.dart';

/// Guarda um ficheiro onde a pessoa escolher (no browser, descarrega-o). Falso se cancelou.
typedef GuardarFicheiro = Future<bool> Function(String nome, Uint8List bytes);

Future<bool> guardarComSeletor(String nome, Uint8List bytes) async {
  final uri = await FilePicker.saveFile(
    fileName: nome,
    bytes: bytes,
    mimeType: 'application/json',
  );
  // No browser o ficheiro descarrega-se e não há caminho para devolver.
  return kIsWeb || uri != null;
}

const _iconeDescarregar = IconeDados(
  '<path d="M12 4v11M7 10l5 5 5-5M5 20h14"/>',
);

/// "A sua conta" (design: Conta): exportar os dados (portabilidade, RGPD) e apagar a conta.
class ContaEcra extends StatefulWidget {
  const ContaEcra({
    super.key,
    required this.autenticacao,
    required this.aoApagar,
    this.guardar = guardarComSeletor,
    this.relogio = DateTime.now,
  });

  final Autenticacao autenticacao;

  /// Abre "Apagar a conta" (precisa de saber se a conta tem palavra-passe).
  final void Function(BuildContext context, DadosConta conta) aoApagar;
  final GuardarFicheiro guardar;
  final DateTime Function() relogio;

  @override
  State<ContaEcra> createState() => _ContaEcraState();
}

class _ContaEcraState extends State<ContaEcra> {
  DadosConta? _conta;
  bool _aExportar = false;

  @override
  void initState() {
    super.initState();
    widget.autenticacao
        .dadosConta()
        .then((c) {
          if (mounted) setState(() => _conta = c);
        })
        .catchError((_) {});
  }

  void _aviso(String texto) =>
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(texto)));

  Future<void> _exportar() async {
    setState(() => _aExportar = true);
    try {
      final json = await widget.autenticacao.exportarDados();
      final dia = DateFormat('yyyy-MM-dd').format(widget.relogio());
      final guardado = await widget.guardar(
        'amparo-dados-$dia.json',
        Uint8List.fromList(utf8.encode(json)),
      );
      if (guardado) _aviso('Os seus dados foram guardados num ficheiro.');
    } on ErroApi catch (e) {
      _aviso(
        e.codigo == 'sem_rede'
            ? 'Sem ligação à internet. Verifique a ligação e tente outra vez.'
            : 'Não foi possível exportar os dados. Tente outra vez.',
      );
    } catch (_) {
      _aviso('Não foi possível guardar o ficheiro. Tente outra vez.');
    }
    if (mounted) setState(() => _aExportar = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final nome = widget.autenticacao.nome ?? '';
    final conta = _conta;
    final desde = conta?.criadaEm == null
        ? 'Cuidador'
        : 'Cuidador · desde ${DateFormat("d MMM y", 'pt_PT').format(conta!.criadaEm!)}';
    return CorpoComRodape(
      margemInferior: 28,
      conteudo: escalonar([
        const CabecalhoFormulario(
          titulo: 'A sua conta',
          subtitulo: 'Os seus dados são seus: pode levá-los consigo ou apagá-los quando quiser.',
          espaco: 16,
        ),
        Cartao(
          child: Row(
            children: [
              Avatar(
                inicial: nome.isEmpty
                    ? '?'
                    : nome.substring(0, 1).toUpperCase(),
                tamanho: 48,
                coral: true,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nome,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: t.texto,
                      ),
                    ),
                    Text(
                      desde,
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
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: t.superficie,
            borderRadius: BorderRadius.circular(24),
            boxShadow: t.sombra,
          ),
          child: Column(
            children: [
              _LinhaConta(
                icone: _iconeDescarregar,
                titulo: _aExportar
                    ? 'A preparar o ficheiro…'
                    : 'Exportar os meus dados',
                texto: 'Um ficheiro com a conta e as pessoas de quem é responsável',
                cor: t.texto,
                aoTocar: _aExportar ? null : _exportar,
                primeira: true,
              ),
              _LinhaConta(
                icone: Icones.lixo,
                titulo: 'Apagar a conta',
                texto: 'Apaga a conta e os dados que só $nome guarda',
                cor: t.mau,
                aoTocar: conta == null
                    ? null
                    : () => widget.aoApagar(context, conta),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: t.superficie2,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            'O ficheiro tem as receitas e as tomas. Guarde-o num sítio seguro e não o partilhe.',
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              fontWeight: FontWeight.w500,
              color: t.texto2,
            ),
          ),
        ),
      ], espaco: 16),
      rodape: const [],
    );
  }
}

class _LinhaConta extends StatelessWidget {
  const _LinhaConta({
    required this.icone,
    required this.titulo,
    required this.texto,
    required this.cor,
    required this.aoTocar,
    this.primeira = false,
  });
  final IconeDados icone;
  final String titulo;
  final String texto;
  final Color cor;
  final VoidCallback? aoTocar;
  final bool primeira;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      decoration: BoxDecoration(
        border: primeira ? null : Border(top: BorderSide(color: t.linha)),
      ),
      child: Pressionavel(
        child: Semantics(
          button: true,
          label: titulo,
          hint: texto,
          excludeSemantics: true,
          child: InkWell(
            onTap: aoTocar,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Icone(icone, tamanho: 24, cor: cor),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            titulo,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: cor,
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
                    Icone(Icones.setaDireita, tamanho: 24, cor: cor),
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

/// "Apagar a conta?" (design: Apagar-Conta). Com palavra-passe pede-a outra vez; numa conta só da Apple ou da
/// Google basta o botão (o servidor pede a confirmação explícita).
class ApagarContaEcra extends StatefulWidget {
  const ApagarContaEcra({
    super.key,
    required this.nome,
    required this.temSenha,
    required this.aoApagar,
  });

  final String nome;
  final bool temSenha;

  /// Devolve o código de erro (`senha_incorreta`, `sem_rede`...) ou nulo se a conta foi apagada.
  final Future<String?> Function(String? senha) aoApagar;

  @override
  State<ApagarContaEcra> createState() => _ApagarContaEcraState();
}

class _ApagarContaEcraState extends State<ApagarContaEcra> {
  final _senha = TextEditingController();
  bool _aApagar = false;
  String? _erro;

  @override
  void dispose() {
    _senha.dispose();
    super.dispose();
  }

  Future<void> _apagar() async {
    if (widget.temSenha && _senha.text.isEmpty) {
      setState(() => _erro = 'Escreva a sua palavra-passe para confirmar.');
      return;
    }
    setState(() {
      _aApagar = true;
      _erro = null;
    });
    final erro = await widget.aoApagar(widget.temSenha ? _senha.text : null);
    if (!mounted) return;
    setState(() {
      _aApagar = false;
      _erro = switch (erro) {
        null => null,
        'senha_incorreta' => 'A palavra-passe não está certa.',
        'sem_rede' =>
          'Sem ligação à internet. Verifique a ligação e tente outra vez.',
        _ => 'Não foi possível apagar a conta. Tente outra vez.',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    Widget item(String texto) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('•  ', style: TextStyle(fontSize: 15, color: t.mauTexto)),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(
                fontSize: 15,
                height: 1.4,
                fontWeight: FontWeight.w500,
                color: t.mauTexto,
              ),
            ),
          ),
        ],
      ),
    );
    return CorpoComRodape(
      margemInferior: 28,
      conteudo: escalonar([
        Align(
          alignment: Alignment.centerLeft,
          child: Semantics(
            button: true,
            label: 'Voltar',
            excludeSemantics: true,
            child: Material(
              color: t.superficie,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => Navigator.of(context).maybePop(),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Center(
                    child: Icone(Icones.voltar, tamanho: 24, cor: t.texto),
                  ),
                ),
              ),
            ),
          ),
        ),
        Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: t.mauSuave,
              ),
              child: Center(child: Icone(Icones.lixo, tamanho: 36, cor: t.mau)),
            ),
            const SizedBox(height: 12),
            Semantics(
              header: true,
              child: Text(
                'Apagar a conta?',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.44,
                  color: t.texto,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Isto não se pode desfazer.',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: t.texto2,
              ),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          decoration: BoxDecoration(
            color: t.mauSuave,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'O que é apagado',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: t.mauTexto,
                ),
              ),
              const SizedBox(height: 4),
              item('A sua conta'),
              item(
                'As pessoas que só ${widget.nome} acompanha, com as receitas, as tomas e os telemóveis ligados',
              ),
              item(
                'Nas pessoas que partilha com outro cuidador, só sai ${widget.nome}',
              ),
            ],
          ),
        ),
        if (widget.temSenha)
          CampoTexto(
            rotulo: 'Para confirmar, escreva a sua palavra-passe',
            controlador: _senha,
            senha: true,
            erro: _erro,
            ativo: !_aApagar,
            aoSubmeter: () {
              if (!_aApagar) _apagar();
            },
          )
        else if (_erro != null)
          Text(
            _erro!,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: t.mauTexto,
            ),
          ),
      ], espaco: 16),
      rodape: [
        Botao(
          texto: _aApagar ? 'A apagar…' : 'Apagar a conta',
          altura: 60,
          raio: 22,
          tamanhoTexto: 18,
          fundo: t.mau,
          cor: t.superficie,
          aoTocar: _aApagar ? null : _apagar,
        ),
        const SizedBox(height: 6),
        AcaoTexto(
          texto: 'Cancelar',
          aoTocar: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }
}
