import 'package:material_ui/material_ui.dart';

/// As cores do design (docs/design.md), tiradas dos temas `.t-dark` e `.t-light` dos ecrãs.
/// Tudo o que a UI pinta vem daqui, nunca de cores soltas nos ecrãs.
@immutable
class Tokens extends ThemeExtension<Tokens> {
  const Tokens({
    required this.fundo,
    required this.superficie,
    required this.superficie2,
    required this.texto,
    required this.texto2,
    required this.primaria,
    required this.sobrePrimaria,
    required this.heroi,
    required this.sobreHeroi,
    required this.sobreHeroi2,
    required this.primariaSuave,
    required this.sobrePrimariaSuave,
    required this.linha,
    required this.ok,
    required this.okSuave,
    required this.okTexto,
    required this.aviso,
    required this.avisoSuave,
    required this.avisoTexto,
    required this.mau,
    required this.mauSuave,
    required this.mauTexto,
    required this.av2,
    required this.sobreAv2,
    required this.escuro,
  });

  /// Gradiente de fundo (de cima para baixo), com as paragens do design.
  final List<Color> fundo;
  final Color superficie;
  final Color superficie2;
  final Color texto;
  final Color texto2;
  final Color primaria;
  final Color sobrePrimaria;
  final Color heroi;
  final Color sobreHeroi;
  final Color sobreHeroi2;
  final Color primariaSuave;
  final Color sobrePrimariaSuave;
  final Color linha;
  final Color ok;
  final Color okSuave;
  final Color okTexto;
  final Color aviso;
  final Color avisoSuave;
  final Color avisoTexto;
  final Color mau;
  final Color mauSuave;
  final Color mauTexto;
  final Color av2;
  final Color sobreAv2;
  final bool escuro;

  /// Texto sobre a cor de aviso cheia (o design usa sempre este tom escuro).
  static const sobreAviso = Color(0xFF1C1917);

  static const List<double> paragensFundo = [0, 0.45, 1];

  static const escuroTema = Tokens(
    fundo: [Color(0xFF070C16), Color(0xFF0A1220), Color(0xFF12303D)],
    superficie: Color(0xFF121B2C),
    superficie2: Color(0xFF1A2539),
    texto: Color(0xFFF1F5F9),
    texto2: Color(0xFFB8C4D4),
    primaria: Color(0xFF2DD4BF),
    sobrePrimaria: Color(0xFF042F2E),
    heroi: Color(0xFF0F3D3A),
    sobreHeroi: Color(0xFFFFFFFF),
    sobreHeroi2: Color(0xFFC8F3EA),
    primariaSuave: Color(0xFF123F3B),
    sobrePrimariaSuave: Color(0xFFCCFBF1),
    linha: Color(0xFF243149),
    ok: Color(0xFF4ADE80),
    okSuave: Color(0xFF0F3A22),
    okTexto: Color(0xFFDCFCE7),
    aviso: Color(0xFFFBBF24),
    avisoSuave: Color(0xFF3D2406),
    avisoTexto: Color(0xFFFEF3C7),
    mau: Color(0xFFF87171),
    mauSuave: Color(0xFF3F1010),
    mauTexto: Color(0xFFFEE2E2),
    av2: Color(0xFF4A2A22),
    sobreAv2: Color(0xFFFFD6C8),
    escuro: true,
  );

  static const claroTema = Tokens(
    fundo: [Color(0xFFD5EAE5), Color(0xFFE8F3F0), Color(0xFFF7FBFA)],
    superficie: Color(0xFFFFFFFF),
    superficie2: Color(0xFFEAF1F3),
    texto: Color(0xFF0F172A),
    texto2: Color(0xFF3B4A5E),
    primaria: Color(0xFF0F766E),
    sobrePrimaria: Color(0xFFFFFFFF),
    heroi: Color(0xFF0B4F4A),
    sobreHeroi: Color(0xFFFFFFFF),
    sobreHeroi2: Color(0xFFD5F5EF),
    primariaSuave: Color(0xFFCCFBF1),
    sobrePrimariaSuave: Color(0xFF0B3B37),
    linha: Color(0xFFDDE5EA),
    ok: Color(0xFF15803D),
    okSuave: Color(0xFFDCFCE7),
    okTexto: Color(0xFF14532D),
    aviso: Color(0xFFD97706),
    avisoSuave: Color(0xFFFEF3C7),
    avisoTexto: Color(0xFF78350F),
    mau: Color(0xFFDC2626),
    mauSuave: Color(0xFFFEE2E2),
    mauTexto: Color(0xFF7F1D1D),
    av2: Color(0xFFFFE2D8),
    sobreAv2: Color(0xFF7A2E14),
    escuro: false,
  );

  /// Sombra dos cartões (a do design, `--shadow`).
  List<BoxShadow> get sombra => escuro
      ? const [
          BoxShadow(
            color: Color(0x38000000),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 22,
            offset: Offset(0, 8),
          ),
        ]
      : const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
          BoxShadow(
            color: Color(0x0F0F172A),
            blurRadius: 22,
            offset: Offset(0, 8),
          ),
        ];

  @override
  Tokens copyWith() => this;

  @override
  Tokens lerp(ThemeExtension<Tokens>? other, double t) =>
      t < 0.5 ? this : (other as Tokens? ?? this);
}

extension TokensNoContexto on BuildContext {
  Tokens get t => Theme.of(this).extension<Tokens>()!;
}
