import 'dart:ui';

import 'package:material_ui/material_ui.dart';

import '../../tema/tokens.dart';

class DestinoNav {
  const DestinoNav(this.rotulo, this.icone);
  final String rotulo;
  final IconData icone;
}

/// A barra de navegação em "ilha" do design: flutua em baixo, vidro fosco, o separador ativo mostra o nome.
class IlhaNavegacao extends StatelessWidget {
  const IlhaNavegacao({
    super.key,
    required this.destinos,
    required this.atual,
    required this.aoMudar,
  });
  final List<DestinoNav> destinos;
  final int atual;
  final ValueChanged<int> aoMudar;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 22),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(36),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: t.superficie.withValues(alpha: .72),
                borderRadius: BorderRadius.circular(36),
                border: Border.all(color: t.linha),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x6B000000),
                    blurRadius: 34,
                    offset: Offset(0, 14),
                  ),
                ],
              ),
              child: Semantics(
                container: true,
                label: 'Navegação principal',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < destinos.length; i++) ...[
                      if (i > 0) const SizedBox(width: 6),
                      _Item(
                        destino: destinos[i],
                        ativo: i == atual,
                        aoTocar: () => aoMudar(i),
                      ),
                    ],
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

class _Item extends StatelessWidget {
  const _Item({
    required this.destino,
    required this.ativo,
    required this.aoTocar,
  });
  final DestinoNav destino;
  final bool ativo;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Semantics(
      button: true,
      selected: ativo,
      label: destino.rotulo,
      excludeSemantics: true,
      child: Material(
        color: ativo ? t.primaria : Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: aoTocar,
          child: Container(
            height: 48,
            constraints: const BoxConstraints(minWidth: 48),
            padding: EdgeInsets.symmetric(horizontal: ativo ? 16 : 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  destino.icone,
                  size: 24,
                  color: ativo ? t.sobrePrimaria : t.texto2,
                ),
                if (ativo) ...[
                  const SizedBox(width: 8),
                  Text(
                    destino.rotulo,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: t.sobrePrimaria,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
