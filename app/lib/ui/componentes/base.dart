import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../tema/tokens.dart';
import 'estilo.dart';
import 'icones.dart';

/// O interruptor do design: 52x32, ligado = verde-azulado com a bola à direita, desligado = contorno.
class Interruptor extends StatelessWidget {
  const Interruptor({super.key, required this.ligado});
  final bool ligado;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return ExcludeSemantics(
      child: Container(
        width: 52,
        height: 32,
        padding: const EdgeInsets.all(3),
        alignment: ligado ? Alignment.centerRight : Alignment.centerLeft,
        decoration: BoxDecoration(
          color: ligado ? t.primaria : t.superficie2,
          borderRadius: BorderRadius.circular(16),
          border: ligado ? null : Border.all(color: t.texto2, width: 2),
        ),
        child: Container(
          width: ligado ? 26 : 22,
          height: ligado ? 26 : 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: ligado ? t.sobrePrimaria : t.texto2,
          ),
        ),
      ),
    );
  }
}

/// O fundo em gradiente do design (escuro em cima, mais claro em baixo).
class FundoGradiente extends StatelessWidget {
  const FundoGradiente({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: t.fundo,
          stops: Tokens.paragensFundo,
        ),
      ),
      child: child,
    );
  }
}

/// Cartão de superfície com a sombra do design.
class Cartao extends StatelessWidget {
  const Cartao({
    super.key,
    required this.child,
    this.cor,
    this.raio = 24,
    this.padding = const EdgeInsets.all(18),
  });
  final Widget child;
  final Color? cor;
  final double raio;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: cor ?? t.superficie,
        borderRadius: BorderRadius.circular(raio),
        boxShadow: t.sombra,
      ),
      child: child,
    );
  }
}

/// Botão do design: altura mínima de 44 px (alvo de toque), cantos de 16 px.
class Botao extends StatelessWidget {
  const Botao({
    super.key,
    required this.texto,
    required this.aoTocar,
    this.icone,
    this.iconeSvg,
    this.tamanhoIcone,
    this.tracoIcone = 2,
    this.fundo,
    this.cor,
    this.contorno,
    this.altura = 44,
    this.raio = 16,
    this.tamanhoTexto = 15,
  });

  final String texto;
  final VoidCallback? aoTocar;
  final IconData? icone;

  /// Um ícone do design (SVG), em vez do `icone` do Material.
  final IconeDados? iconeSvg;
  final double? tamanhoIcone;
  final double tracoIcone;
  final Color? fundo;
  final Color? cor;
  final Color? contorno;
  final double altura;
  final double raio;
  final double tamanhoTexto;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final corTexto = cor ?? t.sobrePrimaria;
    return Pressionavel(
      ativo: aoTocar != null,
      child: Semantics(
        button: true,
        enabled: aoTocar != null,
        label: texto,
        excludeSemantics: true,
        child: Material(
          color: fundo ?? t.primaria,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(raio),
            side: contorno == null
                ? BorderSide.none
                : BorderSide(color: contorno!, width: 2),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(raio),
            // Vibração leve: confirma o toque a quem não olha para o ecrã.
            onTap: aoTocar == null
                ? null
                : () {
                    HapticFeedback.lightImpact();
                    aoTocar!();
                  },
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: altura),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (iconeSvg != null) ...[
                      Icone(
                        iconeSvg!,
                        tamanho: tamanhoIcone ?? tamanhoTexto + 8,
                        cor: corTexto,
                        traco: tracoIcone,
                      ),
                      const SizedBox(width: 10),
                    ] else if (icone != null) ...[
                      Icon(icone, size: tamanhoTexto + 8, color: corTexto),
                      const SizedBox(width: 10),
                    ],
                    Flexible(
                      child: Text(
                        texto,
                        style: TextStyle(
                          fontSize: tamanhoTexto,
                          fontWeight: FontWeight.w800,
                          color: corTexto,
                        ),
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

/// Círculo com a inicial da pessoa.
class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    required this.inicial,
    this.tamanho = 32,
    this.coral = false,
  });
  final String inicial;
  final double tamanho;
  final bool coral;

  /// O design só dá relevo (clay) aos círculos de 48, 52 e 56 px.
  bool get _comRelevo => tamanho == 48 || tamanho == 52 || tamanho == 56;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final cor = coral ? t.av2 : t.primariaSuave;
    final letra = Text(
      inicial,
      style: TextStyle(
        fontSize: tamanho * .46,
        fontWeight: FontWeight.w800,
        color: coral ? t.sobreAv2 : t.sobrePrimariaSuave,
      ),
    );
    return ExcludeSemantics(
      child: _comRelevo
          ? Relevo(largura: tamanho, altura: tamanho, cor: cor, child: letra)
          : Container(
              width: tamanho,
              height: tamanho,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: cor),
              child: letra,
            ),
    );
  }
}

/// Bolinha de estado: ok, aviso ou neutra, com o ícone dentro.
class Selo extends StatelessWidget {
  const Selo({
    super.key,
    required this.cor,
    required this.icone,
    required this.corIcone,
    this.tamanho = 24,
    this.contorno,
  });
  final Color cor;
  final IconData icone;
  final Color corIcone;
  final double tamanho;
  final Color? contorno;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: tamanho,
      height: tamanho,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: cor,
        border: contorno == null ? null : Border.all(color: contorno!),
      ),
      child: Icon(icone, size: tamanho * .62, color: corIcone),
    ),
  );
}
