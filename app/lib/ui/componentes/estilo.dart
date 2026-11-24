import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// O estilo "clay-minimal" do design (bloco `/* style:clay-minimal */` de cada ecrã do artefacto):
/// relevo nos elementos decorativos, efeito ao tocar e entrada escalonada.

/// Sombras interiores do relevo (`inset 6px 7px 12px` branco e `inset -7px -9px 14px` preto).
class _SombraInterior {
  const _SombraInterior(this.dx, this.dy, this.desfoque, this.cor);
  final double dx;
  final double dy;
  final double desfoque;
  final Color cor;
}

const _sombrasInteriores = [
  _SombraInterior(6, 7, 12, Color(0x80FFFFFF)),
  _SombraInterior(-7, -9, 14, Color(0x66000000)),
];

class _PintorInterior extends CustomPainter {
  const _PintorInterior({required this.raio, required this.sombras});
  final double raio;
  final List<_SombraInterior> sombras;

  @override
  void paint(Canvas canvas, Size size) {
    final forma = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(raio),
    );
    canvas.save();
    canvas.clipRRect(forma);
    for (final s in sombras) {
      // A sombra interior é a área de fora da forma deslocada: um retângulo grande com a forma
      // deslocada como buraco (regra par-ímpar), esbatido e cortado pela forma original.
      final fora = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect((Offset.zero & size).inflate(s.desfoque * 3 + 40))
        ..addRRect(forma.shift(Offset(s.dx, s.dy)));
      canvas.drawPath(
        fora,
        Paint()
          ..color = s.cor
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s.desfoque / 2),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PintorInterior antigo) =>
      antigo.raio != raio || antigo.sombras != sombras;
}

/// Caixa com relevo, como os avatares, o círculo do alarme e a caixa da cápsula do design:
/// cor de fundo, dois brilhos radiais por cima, sombras interiores e uma sombra grande por baixo.
class Relevo extends StatelessWidget {
  const Relevo({
    super.key,
    required this.largura,
    required this.altura,
    required this.cor,
    this.raio,
    this.child,
  });
  final double largura;
  final double altura;
  final Color cor;

  /// Nulo: círculo (`border-radius: 50%`).
  final double? raio;
  final Widget? child;

  /// O raio de um `radial-gradient(circle at x% y%, ..., transparente fim%)` do CSS, em unidades
  /// do lado menor (como o Flutter quer), com o tamanho "canto mais distante" do CSS.
  double _raioCss(double cx, double cy, double fim) {
    final canto = math.sqrt(
      math.pow(math.max(cx, 1 - cx) * largura, 2) +
          math.pow(math.max(cy, 1 - cy) * altura, 2),
    );
    return canto * fim / math.min(largura, altura);
  }

  @override
  Widget build(BuildContext context) {
    final r = raio ?? math.min(largura, altura) / 2;
    final forma = BorderRadius.circular(r);
    return SizedBox(
      width: largura,
      height: altura,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: forma,
          boxShadow: const [
            BoxShadow(
              color: Color(0x73000000),
              blurRadius: 30,
              offset: Offset(0, 18),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: forma,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: cor),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.4, -0.56),
                    radius: _raioCss(.30, .22, .52),
                    colors: const [Color(0x6BFFFFFF), Color(0x00FFFFFF)],
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.56, 0.76),
                    radius: _raioCss(.78, .88, .58),
                    colors: const [Color(0x38000000), Color(0x00000000)],
                  ),
                ),
              ),
              CustomPaint(
                painter: _PintorInterior(raio: r, sombras: _sombrasInteriores),
              ),
              if (child != null) Center(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// `a:active, button:active { transform: scale(.96); filter: brightness(1.08) }` com
/// `transition: .15s ease`: o efeito ao tocar de todos os botões e ligações do design.
class Pressionavel extends StatefulWidget {
  const Pressionavel({super.key, required this.child, this.ativo = true});
  final Widget child;
  final bool ativo;

  @override
  State<Pressionavel> createState() => _PressionavelState();
}

class _PressionavelState extends State<Pressionavel> {
  bool _premido = false;

  void _mudar(bool v) {
    if (!widget.ativo || _premido == v) return;
    setState(() => _premido = v);
  }

  static const _brilho = ColorFilter.matrix(<double>[
    1.08, 0, 0, 0, 0, //
    0, 1.08, 0, 0, 0, //
    0, 0, 1.08, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _mudar(true),
      onPointerUp: (_) => _mudar(false),
      onPointerCancel: (_) => _mudar(false),
      child: AnimatedScale(
        scale: _premido ? .96 : 1,
        duration: const Duration(milliseconds: 150),
        curve: Curves.ease,
        child: ColorFiltered(
          colorFilter: _premido
              ? _brilho
              : const ColorFilter.mode(Color(0x00000000), BlendMode.dst),
          child: widget.child,
        ),
      ),
    );
  }
}

/// `mFadeUp`: o elemento sobe 14 px e aparece (0,55 s, `ease-out`), depois de [atraso].
class EntradaSobe extends StatefulWidget {
  const EntradaSobe({
    super.key,
    required this.child,
    this.atraso = Duration.zero,
    this.duracao = const Duration(milliseconds: 550),
    this.deslocamento = 14,
  });
  final Widget child;
  final Duration atraso;
  final Duration duracao;
  final double deslocamento;

  @override
  State<EntradaSobe> createState() => _EntradaSobeState();
}

class _EntradaSobeState extends State<EntradaSobe>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.atraso + widget.duracao,
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: Interval(
      widget.atraso.inMilliseconds /
          (widget.atraso + widget.duracao).inMilliseconds,
      1,
      curve: Curves.easeOut,
    ),
  );
  bool _iniciada = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_iniciada) return;
    _iniciada = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (context, filho) => Opacity(
        opacity: _t.value,
        child: Transform.translate(
          offset: Offset(0, widget.deslocamento * (1 - _t.value)),
          child: filho,
        ),
      ),
    );
  }
}

/// Os filhos diretos de um ecrã entram em cascata (0,08 s de intervalo entre eles, como no design).
/// [espaco] é o `gap` da coluna, posto entre eles sem contar para o atraso.
List<Widget> escalonar(
  List<Widget> filhos, {
  double espaco = 0,
  Duration intervalo = const Duration(milliseconds: 80),
}) => [
  for (var i = 0; i < filhos.length; i++) ...[
    if (i > 0 && espaco > 0) SizedBox(height: espaco),
    EntradaSobe(atraso: intervalo * math.min(i, 7), child: filhos[i]),
  ],
];

/// `mFloat`: sobe e desce 4 px em 4,5 s, sem parar (os círculos grandes e a caixa de 68 px).
class Flutuar extends StatefulWidget {
  const Flutuar({super.key, required this.child});
  final Widget child;

  @override
  State<Flutuar> createState() => _FlutuarState();
}

class _FlutuarState extends State<Flutuar> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4500),
  );
  bool _iniciada = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_iniciada) return;
    _iniciada = true;
    if (!MediaQuery.disableAnimationsOf(context)) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, filho) {
        // 0% 0, 50% -4 px, 100% 0, com `ease-in-out` em cada metade.
        final metade = _c.value < .5 ? _c.value * 2 : (1 - _c.value) * 2;
        return Transform.translate(
          offset: Offset(0, -4 * Curves.easeInOut.transform(metade)),
          child: filho,
        );
      },
    );
  }
}

/// Uma animação de 0 a 1 que começa depois de [atraso] (`animation: ... both` do CSS): o construtor
/// recebe o progresso já com a curva aplicada. Com "reduzir movimento" fica logo no fim.
class AnimarComAtraso extends StatefulWidget {
  const AnimarComAtraso({
    super.key,
    required this.builder,
    this.atraso = Duration.zero,
    this.duracao = const Duration(milliseconds: 500),
    this.curva = Curves.easeOut,
  });
  final Widget Function(BuildContext context, double t) builder;
  final Duration atraso;
  final Duration duracao;
  final Curve curva;

  @override
  State<AnimarComAtraso> createState() => _AnimarComAtrasoState();
}

class _AnimarComAtrasoState extends State<AnimarComAtraso>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.atraso + widget.duracao,
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: Interval(
      widget.atraso.inMilliseconds /
          (widget.atraso + widget.duracao).inMilliseconds,
      1,
      curve: widget.curva,
    ),
  );
  bool _iniciada = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_iniciada) return;
    _iniciada = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _t,
    builder: (c, _) => widget.builder(c, _t.value),
  );
}

/// `mGrow`: a barra cresce da esquerda para a direita (`transform: scaleX(0)` → 1).
class BarraQueCresce extends StatelessWidget {
  const BarraQueCresce({
    super.key,
    required this.child,
    this.atraso = Duration.zero,
    this.duracao = const Duration(milliseconds: 500),
  });
  final Widget child;
  final Duration atraso;
  final Duration duracao;

  @override
  Widget build(BuildContext context) => AnimarComAtraso(
    atraso: atraso,
    duracao: duracao,
    builder: (context, t) => Transform(
      alignment: Alignment.centerLeft,
      transform: Matrix4.diagonal3Values(t, 1, 1),
      child: child,
    ),
  );
}
