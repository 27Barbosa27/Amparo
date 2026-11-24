import '../../dominio/modelos.dart';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

/// Os ícones do design, com os mesmos caminhos SVG (viewBox 24, traço arredondado), para ficarem
/// iguais aos do artefacto em vez dos do Material.
class IconeDados {
  const IconeDados(this.corpo);

  /// Os elementos SVG (`<path .../>`, `<circle .../>`), sem `<svg>` à volta.
  final String corpo;
}

class Icones {
  Icones._();

  // O tipo de medicação: comprimido, líquido/gotas, injeção e "outro".
  static const comprimido = IconeDados(
    '<g transform="rotate(-45 12 12)"><rect x="2.5" y="7.5" width="19" height="9" rx="4.5"/><path d="M12 7.5v9"/></g>',
  );
  static const gota = IconeDados(
    '<path d="M12 3s6 6.5 6 11a6 6 0 0 1-12 0c0-4.5 6-11 6-11z"/>',
  );
  static const seringa = IconeDados(
    '<path d="M18 2l4 4M20 4l-3 3M15 5l4 4-9 9-4-4zM6 14l-3 3M3 21l3-3"/>',
  );
  static const caixa = IconeDados(
    '<rect x="4" y="4" width="16" height="16" rx="4"/><path d="M12 8v8M8 12h8"/>',
  );

  static const maisOpcoes = IconeDados(
    '<circle cx="5" cy="12" r="1.4"/><circle cx="12" cy="12" r="1.4"/><circle cx="19" cy="12" r="1.4"/>',
  );
  static const lapis = IconeDados(
    '<path d="M4 20h4L19 9l-4-4L4 16z"/><path d="M13.5 6.5l4 4"/>',
  );
  static const lixo = IconeDados(
    '<path d="M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3"/>',
  );
  static const visto = IconeDados('<path d="M5 12.5l4.5 4.5L19 7.5"/>');
  static const alerta = IconeDados(
    '<path d="M12 6.5v7"/><path d="M12 17.5v.01"/>',
  );
  static const relogio = IconeDados('<path d="M12 6.5V12l3 2"/>');
  static const relogioCirculo = IconeDados(
    '<circle cx="12" cy="12" r="9"/><path d="M12 7.5V12l3 2"/>',
  );
  static const setaDireita = IconeDados('<path d="M9 6l6 6-6 6"/>');
  static const setaBaixo = IconeDados('<path d="M6 9l6 6 6-6"/>');
  static const voltar = IconeDados('<path d="M15 6l-6 6 6 6"/>');
  static const x = IconeDados('<path d="M7 7l10 10M17 7L7 17"/>');
  static const telefone = IconeDados(
    '<path d="M5 4h4l2 5-3 2a11 11 0 0 0 5 5l2-3 5 2v4a2 2 0 0 1-2 2A17 17 0 0 1 3 6a2 2 0 0 1 2-2"/>',
  );
  static const sino = IconeDados(
    '<path d="M6 16v-5a6 6 0 1 1 12 0v5l1.5 2h-15z"/><path d="M10 21h4"/>',
  );
  static const olho = IconeDados(
    '<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>',
  );
  static const olhoRiscado = IconeDados(
    '<path d="M3 3l18 18"/><path d="M10.6 5.1A10.5 10.5 0 0 1 12 5c6.5 0 10 7 10 7a17 17 0 0 1-3.2 4.1M6.5 6.6C3.6 8.5 2 12 2 12s3.5 7 10 7a10 10 0 0 0 4.1-.9"/><path d="M9.9 9.9a3 3 0 0 0 4.2 4.2"/>',
  );
  static const calendario = IconeDados(
    '<rect x="3.5" y="5" width="17" height="15.5" rx="3"/><path d="M3.5 10h17M8 3v4M16 3v4"/>',
  );
  static const documento = IconeDados(
    '<path d="M7 3h7l5 5v11a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z"/><path d="M14 3v5h5M9 13h6M9 17h4"/>',
  );
  static const historico = IconeDados(
    '<path d="M3 12a9 9 0 1 0 3-6.7"/><path d="M3 4v5h5"/><path d="M12 8v4l3 2"/>',
  );
  static const textoAa = IconeDados(
    '<path d="M3 19l5-13 5 13M5 15h6"/><path d="M14.5 19l3-7.5 3 7.5M15.5 17h4"/>',
  );
  static const escudo = IconeDados(
    '<path d="M12 3l7 3v5c0 4.5-3 8-7 10-4-2-7-5.5-7-10V6z"/>',
  );
  static const escudoVisto = IconeDados(
    '<path d="M12 3l7 3v5c0 4.5-3 8-7 10-4-2-7-5.5-7-10V6z"/><path d="M9 12l2 2 4-4"/>',
  );
  static const semNuvem = IconeDados(
    '<path d="m2 2 20 20"/><path d="M5.782 5.782A7 7 0 0 0 9 19h8.5a4.5 4.5 0 0 0 1.307-.193"/><path d="M21.532 16.5A4.5 4.5 0 0 0 17.5 10h-1.79A7.008 7.008 0 0 0 10 5.07"/>',
  );
  static const desfazer = IconeDados(
    '<path d="M9 14L4 9l5-5"/><path d="M4 9h10.5a5.5 5.5 0 0 1 0 11H11"/>',
  );
  static const alertaCirculo = IconeDados(
    '<circle cx="12" cy="12" r="9"/><path d="M12 7v6M12 16.5v.01"/>',
  );
  static const telemovel = IconeDados(
    '<rect x="7" y="2" width="10" height="20" rx="2.5"/><path d="M11 18h2"/>',
  );
  static const lua = IconeDados(
    '<path d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z"/>',
  );
  static const cadeado = IconeDados(
    '<rect x="5" y="11" width="14" height="10" rx="2.5"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>',
  );
  static const utilizador = IconeDados(
    '<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>',
  );
  static const sair = IconeDados(
    '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><path d="M16 17l5-5-5-5M21 12H9"/>',
  );
  static const roda = IconeDados(
    '<path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z"/><circle cx="12" cy="12" r="3"/>',
  );
}

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// Desenha um [IconeDados] com o traço e a cor dadas (como `stroke="currentColor"` do design).
class Icone extends StatelessWidget {
  const Icone(
    this.dados, {
    super.key,
    required this.tamanho,
    required this.cor,
    this.traco = 2,
  });
  final IconeDados dados;
  final double tamanho;
  final Color cor;

  /// `stroke-width` do design (2, 2.4, 2.6 ou 3, conforme o sítio).
  final double traco;

  @override
  Widget build(BuildContext context) {
    final svg =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" '
        'stroke="${_hex(cor)}" stroke-opacity="${(cor.a).toStringAsFixed(3)}" '
        'stroke-width="$traco" stroke-linecap="round" stroke-linejoin="round">${dados.corpo}</svg>';
    return ExcludeSemantics(
      child: SvgPicture.string(svg, width: tamanho, height: tamanho),
    );
  }
}

/// Círculo de estado do design (24 px por omissão), com o ícone dentro.
class SeloIcone extends StatelessWidget {
  const SeloIcone({
    super.key,
    required this.cor,
    required this.dados,
    required this.corIcone,
    this.tamanho = 24,
    this.tamanhoIcone = 16,
    this.traco = 3,
    this.contorno,
  });
  final Color cor;
  final IconeDados dados;
  final Color corIcone;
  final double tamanho;
  final double tamanhoIcone;
  final double traco;
  final Color? contorno;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: tamanho,
      height: tamanho,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: cor,
        border: contorno == null ? null : Border.all(color: contorno!),
      ),
      child: Icone(dados, tamanho: tamanhoIcone, cor: corIcone, traco: traco),
    ),
  );
}

/// O ícone do design que melhor mostra o tipo de medicação.
IconeDados iconeDoTipo(String dose) => switch (TipoMedicacao.daDose(dose)) {
  TipoMedicacao.comprimido || TipoMedicacao.capsula => Icones.comprimido,
  TipoMedicacao.liquido || TipoMedicacao.gotas => Icones.gota,
  TipoMedicacao.injecao => Icones.seringa,
  _ => Icones.caixa,
};
