import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

import '../../tema/tokens.dart';

// Os logótipos do design (Entrar.dc.html).
const _svgApple =
    '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path fill="#000000" d="M12.152 6.896c-.948 0-2.415-1.078-3.96-1.04-2.04.027-3.91 1.183-4.961 3.014-2.117 3.675-.546 9.103 1.519 12.09 1.013 1.454 2.208 3.09 3.792 3.039 1.52-.065 2.09-.987 3.935-.987 1.831 0 2.35.987 3.96.948 1.637-.026 2.676-1.48 3.676-2.948 1.156-1.688 1.636-3.325 1.662-3.415-.039-.013-3.182-1.221-3.22-4.857-.026-3.04 2.48-4.494 2.597-4.559-1.429-2.09-3.623-2.324-4.39-2.376-2-.156-3.675 1.09-4.61 1.09zM15.53 3.83c.843-1.012 1.4-2.427 1.245-3.83-1.207.052-2.662.805-3.532 1.818-.78.896-1.454 2.338-1.273 3.714 1.338.104 2.715-.688 3.559-1.701"/></svg>';

const _svgGoogle =
    '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path fill="#4285F4" d="M23.52 12.27c0-.85-.08-1.67-.22-2.45H12v4.64h6.46a5.52 5.52 0 0 1-2.4 3.62v3h3.88c2.27-2.09 3.58-5.17 3.58-8.81z"/><path fill="#34A853" d="M12 24c3.24 0 5.96-1.07 7.94-2.91l-3.88-3c-1.08.72-2.45 1.15-4.06 1.15-3.12 0-5.77-2.11-6.71-4.94H1.29v3.1A12 12 0 0 0 12 24z"/><path fill="#FBBC05" d="M5.29 14.3a7.2 7.2 0 0 1 0-4.6V6.6H1.29a12 12 0 0 0 0 10.8l4-3.1z"/><path fill="#EA4335" d="M12 4.75c1.76 0 3.34.61 4.58 1.8l3.43-3.43A11.5 11.5 0 0 0 12 0 12 12 0 0 0 1.29 6.6l4 3.1C6.23 6.86 8.88 4.75 12 4.75z"/></svg>';

/// "Entrar com a Apple" e "Entrar com a Google", lado a lado como no design.
/// A Apple exige que os dois apareçam juntos. O botão da Apple é branco com o logótipo preto.
class BotoesSso extends StatelessWidget {
  const BotoesSso({super.key, required this.aoApple, required this.aoGoogle});
  final VoidCallback aoApple;
  final VoidCallback aoGoogle;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Row(
      children: [
        Expanded(
          child: _Sso(
            rotulo: 'Apple',
            descricao: 'Entrar com Apple',
            svg: _svgApple,
            fundo: const Color(0xFFFFFFFF),
            cor: const Color(0xFF000000),
            aoTocar: aoApple,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _Sso(
            rotulo: 'Google',
            descricao: 'Entrar com Google',
            svg: _svgGoogle,
            fundo: t.superficie,
            cor: t.texto,
            contorno: t.linha,
            aoTocar: aoGoogle,
          ),
        ),
      ],
    );
  }
}

class _Sso extends StatelessWidget {
  const _Sso({
    required this.rotulo,
    required this.descricao,
    required this.svg,
    required this.fundo,
    required this.cor,
    required this.aoTocar,
    this.contorno,
  });
  final String rotulo;
  final String descricao;
  final String svg;
  final Color fundo;
  final Color cor;
  final Color? contorno;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: descricao,
      excludeSemantics: true,
      child: Material(
        color: fundo,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: contorno == null
              ? BorderSide.none
              : BorderSide(color: contorno!, width: 2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: aoTocar,
          child: SizedBox(
            height: 52,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SvgPicture.string(svg, width: 22, height: 22),
                const SizedBox(width: 10),
                Text(
                  rotulo,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: cor,
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
