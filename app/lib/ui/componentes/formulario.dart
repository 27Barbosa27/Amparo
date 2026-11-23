import 'package:material_ui/material_ui.dart';

import '../../tema/tokens.dart';
import 'base.dart';

/// Uma página empurrada (formulários e resultados): fundo em gradiente e área segura.
Route<T> rotaPagina<T>(Widget conteudo) => MaterialPageRoute<T>(
  builder: (_) => Scaffold(
    body: FundoGradiente(child: SafeArea(child: conteudo)),
  ),
);

/// Cabeçalho dos formulários do design: botão de voltar de 48 px, título e subtítulo.
class CabecalhoFormulario extends StatelessWidget {
  const CabecalhoFormulario({
    super.key,
    required this.titulo,
    required this.subtitulo,
  });
  final String titulo;
  final String subtitulo;

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
                child: Icon(Icons.chevron_left, size: 28, color: t.texto),
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Semantics(
          header: true,
          child: Text(
            titulo,
            style: TextStyle(
              fontSize: 22,
              height: 1.15,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.44,
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
  });
  final List<Widget> conteudo;
  final List<Widget> rodape;

  @override
  Widget build(BuildContext context) {
    // Rola quando o conteúdo é maior do que o ecrã e, quando sobra espaço, encosta o rodapé em baixo.
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          sliver: SliverFillRemaining(
            hasScrollBody: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...conteudo,
                const Spacer(),
                const SizedBox(height: 18),
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
  });
  final String rotulo;
  final TextEditingController controlador;
  final String? dica;

  /// Mensagem de erro por baixo do campo (o contorno fica a vermelho).
  final String? erro;
  final TextInputType? teclado;
  final ValueChanged<String>? aoMudar;
  final int maxLength;

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
        const SizedBox(height: 8),
        SizedBox(
          height: 56,
          child: TextField(
            controller: controlador,
            keyboardType: teclado,
            maxLength: maxLength,
            autocorrect: false,
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
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              border: borda(cor),
              enabledBorder: borda(cor),
              focusedBorder: borda(erro == null ? t.primaria : t.mau),
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
