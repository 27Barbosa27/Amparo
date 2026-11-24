import 'dart:ui';

import 'package:material_ui/material_ui.dart';

import '../../tema/tokens.dart';
import 'estilo.dart';
import 'icones.dart';

class DestinoNav {
  const DestinoNav(this.rotulo, this.icone);
  final String rotulo;
  final IconeDados icone;
}

/// A barra de navegação em "ilha" do design: flutua em baixo, vidro fosco, o separador ativo mostra o nome.
/// O vidro é o do `nav[aria-label='Navegação principal']` do estilo clay-minimal: superfície a 58%,
/// desfoque de 20 px e sombra grande por baixo (sem o contorno branco do design).
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
    const raio = 36.0;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 22),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(raio),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 36,
                offset: Offset(0, 16),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(raio),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              // Sem contorno nem brilho branco no topo: só o vidro.
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: t.superficie.withValues(alpha: .58),
                  borderRadius: BorderRadius.circular(raio),
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
                          key: ValueKey(
                            'nav-${destinos[i].rotulo.toLowerCase()}',
                          ),
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
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    super.key,
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
    return Pressionavel(
      child: Semantics(
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
              padding: EdgeInsets.only(
                left: ativo ? 14 : 12,
                right: ativo ? 18 : 12,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icone(
                    destino.icone,
                    tamanho: 24,
                    cor: ativo ? t.sobrePrimaria : t.texto2,
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
      ),
    );
  }
}
