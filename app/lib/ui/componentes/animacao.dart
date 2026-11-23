import 'package:lottie/lottie.dart';
import 'package:material_ui/material_ui.dart';

/// Animação Lottie do design (entrada, sucesso, erro).
/// Respeita "reduzir movimento" do sistema: nesse caso mostra só o último fotograma, sem animar.
class AnimacaoLottie extends StatefulWidget {
  const AnimacaoLottie({
    super.key,
    required this.asset,
    required this.largura,
    required this.altura,
    required this.descricao,
    this.repetir = false,
    this.ultimoFotograma,
  });

  final String asset;
  final double largura;
  final double altura;

  /// Texto para o leitor de ecrã.
  final String descricao;

  /// `true`: repete sem parar (a entrada). `false`: corre uma vez (sucesso, erro).
  final bool repetir;

  /// Fotograma onde parar (o design toca só até aqui). Nulo: até ao fim.
  final double? ultimoFotograma;

  @override
  State<AnimacaoLottie> createState() => _AnimacaoLottieState();
}

class _AnimacaoLottieState extends State<AnimacaoLottie>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  double _fim = 1;
  bool _carregada = false;

  void _iniciar() {
    if (!_carregada) return;
    final reduzir = MediaQuery.disableAnimationsOf(context);
    if (reduzir) {
      _c.stop();
      _c.value = _fim;
    } else if (widget.repetir) {
      if (!_c.isAnimating) _c.repeat();
    } else if (!_c.isAnimating && _c.value < _fim) {
      _c.animateTo(_fim);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _iniciar();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: widget.descricao,
      child: ExcludeSemantics(
        child: SizedBox(
          width: widget.largura,
          height: widget.altura,
          child: Lottie.asset(
            widget.asset,
            controller: _c,
            fit: BoxFit.contain,
            onLoaded: (composicao) {
              _c.duration = composicao.duration;
              final total = composicao.endFrame - composicao.startFrame;
              _fim = widget.ultimoFotograma == null
                  ? 1
                  : (widget.ultimoFotograma! / total).clamp(0.0, 1.0);
              _carregada = true;
              _iniciar();
            },
          ),
        ),
      ),
    );
  }
}
