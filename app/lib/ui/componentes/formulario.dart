import 'package:material_ui/material_ui.dart';

import '../../tema/tokens.dart';
import 'base.dart';
import 'icones.dart';

/// Uma página empurrada (formulários e resultados): fundo em gradiente e área segura.
///
/// No design os ecrãs não deslizam: aparecem e os blocos sobem um a um (`mFadeUp`), por isso a rota só faz
/// um esbatimento rápido e deixa a entrada escalonada de cada ecrã fazer o resto.
Route<T> rotaPagina<T>(Widget conteudo) => PageRouteBuilder<T>(
  transitionDuration: const Duration(milliseconds: 220),
  reverseTransitionDuration: const Duration(milliseconds: 160),
  pageBuilder: (_, _, _) => Scaffold(
    body: FundoGradiente(child: SafeArea(child: conteudo)),
  ),
  transitionsBuilder: (_, animacao, _, filho) => FadeTransition(
    opacity: CurvedAnimation(parent: animacao, curve: Curves.easeOut),
    child: filho,
  ),
);

/// Cabeçalho dos formulários do design: botão de voltar de 48 px, título e subtítulo.
class CabecalhoFormulario extends StatelessWidget {
  const CabecalhoFormulario({
    super.key,
    required this.titulo,
    required this.subtitulo,
    this.espaco = 18,
  });
  final String titulo;
  final String subtitulo;

  /// Espaço entre o botão de voltar e o título (o `gap` da coluna do design).
  final double espaco;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
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
        ),
        SizedBox(height: espaco),
        Semantics(
          header: true,
          child: Text(
            titulo,
            style: TextStyle(
              fontSize: 22,
              height: 1.15,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.55,
              color: t.texto,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitulo,
          style: TextStyle(
            fontSize: 15,
            height: 1.45,
            fontWeight: FontWeight.w500,
            color: t.texto2,
          ),
        ),
      ],
    );
  }
}

/// Conteúdo que rola, com o rodapé (botões) encostado em baixo quando sobra espaço.
class CorpoComRodape extends StatelessWidget {
  const CorpoComRodape({
    super.key,
    required this.conteudo,
    required this.rodape,
    this.espacoRodape = 18,
    this.margemInferior = 24,
  });
  final List<Widget> conteudo;
  final List<Widget> rodape;

  /// O espaço mínimo entre o conteúdo e o rodapé encostado em baixo (o `gap` da coluna do design).
  final double espacoRodape;

  /// A margem de baixo do ecrã (24 ou 28 px, conforme o design).
  final double margemInferior;

  @override
  Widget build(BuildContext context) {
    // Rola quando o conteúdo é maior do que o ecrã e, quando sobra espaço, encosta o rodapé em baixo.
    return CustomScrollView(
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 12, 20, margemInferior),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...conteudo,
                const Spacer(),
                SizedBox(height: espacoRodape),
                ...rodape,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Campo de texto do design: rótulo por cima (15 px, 800), caixa de 56 px, cantos de 16 px.
class CampoTexto extends StatelessWidget {
  const CampoTexto({
    super.key,
    required this.rotulo,
    required this.controlador,
    this.dica,
    this.erro,
    this.teclado,
    this.aoMudar,
    this.maxLength = 100,
    this.altura = 56,
    this.espacoRotulo = 8,
    this.senha = false,
    this.ativo = true,
    this.sufixo,
    this.aoSubmeter,
    this.autofill,
  });
  final String rotulo;
  final TextEditingController controlador;
  final String? dica;

  /// Palavra-passe: o texto fica escondido e há um olho para o mostrar.
  final bool senha;

  /// Desativado: não se pode escrever (fica esbatido).
  final bool ativo;

  /// Um widget dentro do campo, à direita (por exemplo o visto de "confirmado").
  final Widget? sufixo;
  final VoidCallback? aoSubmeter;
  final Iterable<String>? autofill;

  /// Mensagem de erro por baixo do campo (o contorno fica a vermelho).
  final String? erro;
  final TextInputType? teclado;
  final ValueChanged<String>? aoMudar;
  final int maxLength;

  /// Altura da caixa (56 nos formulários de pessoa e receita, 52 no Entrar e no Registo).
  final double altura;
  final double espacoRotulo;

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
          rotulo,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: t.texto,
          ),
        ),
        SizedBox(height: espacoRotulo),
        SizedBox(
          height: altura,
          child: _CampoSenha(
            ativo: senha,
            construir: (escondido, olho) => TextField(
              controller: controlador,
              enabled: ativo,
              keyboardType: teclado,
              maxLength: maxLength,
              autocorrect: false,
              obscureText: escondido,
              enableSuggestions: !senha,
              autofillHints: autofill,
              textInputAction: aoSubmeter == null
                  ? TextInputAction.next
                  : TextInputAction.done,
              onSubmitted: aoSubmeter == null ? null : (_) => aoSubmeter!(),
              onChanged: aoMudar,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: t.texto,
              ),
              decoration: InputDecoration(
                counterText: '',
                hintText: dica,
                hintStyle: TextStyle(
                  color: t.texto2.withValues(alpha: .85),
                  fontWeight: FontWeight.w600,
                ),
                filled: true,
                fillColor: t.superficie,
                suffixIcon: olho ?? sufixo,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                border: borda(cor),
                enabledBorder: borda(cor),
                focusedBorder: borda(erro == null ? t.primaria : t.mau),
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

/// Guarda se a palavra-passe está visível e desenha o olho (só quando [ativo]).
class _CampoSenha extends StatefulWidget {
  const _CampoSenha({required this.ativo, required this.construir});
  final bool ativo;
  final Widget Function(bool escondido, Widget? olho) construir;

  @override
  State<_CampoSenha> createState() => _CampoSenhaState();
}

class _CampoSenhaState extends State<_CampoSenha> {
  bool _ver = false;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    if (!widget.ativo) return widget.construir(false, null);
    return widget.construir(
      !_ver,
      IconButton(
        tooltip: _ver ? 'Esconder palavra-passe' : 'Mostrar palavra-passe',
        onPressed: () => setState(() => _ver = !_ver),
        icon: Icone(
          _ver ? Icones.olhoRiscado : Icones.olho,
          tamanho: 22,
          cor: t.texto2,
        ),
      ),
    );
  }
}

/// Uma linha de botões de escolha (Normal / Grande / Muito grande, 7 dias / 1 mês / 3 meses...).
/// Só um fica ativo. Cada botão tem pelo menos 52 px de altura.
class GrelhaOpcoes<T> extends StatelessWidget {
  const GrelhaOpcoes({
    super.key,
    required this.titulo,
    required this.opcoes,
    required this.texto,
    required this.valor,
    required this.aoEscolher,
    this.colunas = 3,
  });
  final String titulo;
  final List<T> opcoes;
  final String Function(T) texto;
  final T valor;
  final ValueChanged<T> aoEscolher;
  final int colunas;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            titulo,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: t.texto,
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Linhas de `colunas` botões do mesmo tamanho (sem LayoutBuilder, que não aguenta o layout com rodapé).
        for (var inicio = 0; inicio < opcoes.length; inicio += colunas) ...[
          if (inicio > 0) const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var k = 0; k < colunas; k++) ...[
                  if (k > 0) const SizedBox(width: 10),
                  Expanded(
                    child: inicio + k < opcoes.length
                        ? _BotaoEscolha(
                            texto: texto(opcoes[inicio + k]),
                            ativo: opcoes[inicio + k] == valor,
                            aoTocar: () => aoEscolher(opcoes[inicio + k]),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _BotaoEscolha extends StatelessWidget {
  const _BotaoEscolha({
    required this.texto,
    required this.ativo,
    required this.aoTocar,
  });
  final String texto;
  final bool ativo;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Semantics(
      button: true,
      selected: ativo,
      label: texto,
      excludeSemantics: true,
      child: Material(
        color: ativo ? t.primariaSuave : t.superficie,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: ativo ? t.primaria : t.linha, width: 2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: aoTocar,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  texto,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: ativo ? FontWeight.w800 : FontWeight.w700,
                    color: ativo ? t.sobrePrimariaSuave : t.texto,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Cartão de escolha com título e explicação, e um círculo à direita (marcado ou vazio).
class CartaoOpcao extends StatelessWidget {
  const CartaoOpcao({
    super.key,
    required this.titulo,
    required this.descricao,
    required this.ativo,
    required this.aoTocar,
  });
  final String titulo;
  final String descricao;
  final bool ativo;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Semantics(
      button: true,
      selected: ativo,
      label: '$titulo. $descricao',
      excludeSemantics: true,
      child: Material(
        color: ativo ? t.primariaSuave : t.superficie,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: ativo ? t.primaria : t.linha, width: 2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: aoTocar,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: ativo ? t.sobrePrimariaSuave : t.texto,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        descricao,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: ativo ? t.sobrePrimariaSuave : t.texto2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ativo
                    ? Selo(
                        cor: t.primaria,
                        icone: Icons.check,
                        corIcone: t.sobrePrimaria,
                      )
                    : Container(
                        width: 24,
                        height: 24,
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
    );
  }
}
