import 'package:material_ui/material_ui.dart';

import '../../tema/tokens.dart';
import 'animacao.dart';
import 'base.dart';
import 'estilo.dart';

/// O esqueleto dos ecrãs de resultado do design (Sucesso-*, Erro-*): margens de 48/20/24, a animação com
/// o título e o texto em cima, um cartão opcional, e as ações encostadas em baixo (`margin-top: auto`).
class EcraResultado extends StatelessWidget {
  const EcraResultado({
    super.key,
    required this.topo,
    required this.acoes,
    this.cartao,
  });
  final Widget topo;
  final Widget? cartao;
  final List<Widget> acoes;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: CustomScrollView(
            slivers: [
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 48, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      EntradaSobe(child: topo),
                      if (cartao != null) ...[
                        const SizedBox(height: 18),
                        EntradaSobe(
                          atraso: const Duration(milliseconds: 80),
                          child: cartao!,
                        ),
                      ],
                      const Spacer(),
                      const SizedBox(height: 18),
                      EntradaSobe(
                        atraso: const Duration(milliseconds: 160),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < acoes.length; i++) ...[
                              if (i > 0) const SizedBox(height: 8),
                              acoes[i],
                            ],
                          ],
                        ),
                      ),
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

/// A parte de cima: a animação (240x260), o título (26 px, aparece depois da animação) e o texto.
class TopoResultado extends StatelessWidget {
  const TopoResultado({
    super.key,
    required this.titulo,
    required this.texto,
    this.animacao,
    this.corTexto,
  });
  final String titulo;
  final String texto;

  /// Por omissão, o visto do sucesso. Os erros passam a sua animação.
  final Widget? animacao;
  final Color? corTexto;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Column(
      children: [
        animacao ??
            const AnimacaoLottie(
              asset: 'assets/lottie/sucesso.json',
              largura: 240,
              altura: 240,
              descricao: 'Concluído com sucesso',
            ),
        const SizedBox(height: 12),
        // `.rise`: o título aparece 1 s depois, a subir 8 px.
        EntradaSobe(
          atraso: const Duration(seconds: 1),
          duracao: const Duration(milliseconds: 500),
          deslocamento: 8,
          child: Semantics(
            header: true,
            child: Text(
              titulo,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 26,
                height: 1.15,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.65,
                color: t.texto,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          texto,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            height: 1.45,
            fontWeight: FontWeight.w500,
            color: corTexto ?? t.texto2,
          ),
        ),
      ],
    );
  }
}

/// O cartão do resultado: 18 px de margem, cantos de 24.
class CartaoResultado extends StatelessWidget {
  const CartaoResultado({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Cartao(raio: 24, padding: const EdgeInsets.all(18), child: child);
}

/// A ação secundária do design: só texto (48 px, 15 px, 600), sem contorno.
class AcaoTexto extends StatelessWidget {
  const AcaoTexto({super.key, required this.texto, required this.aoTocar});
  final String texto;
  final VoidCallback? aoTocar;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Pressionavel(
      child: Semantics(
        button: true,
        label: texto,
        excludeSemantics: true,
        child: InkWell(
          onTap: aoTocar,
          child: SizedBox(
            height: 48,
            child: Center(
              child: Text(
                texto,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: t.texto,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
