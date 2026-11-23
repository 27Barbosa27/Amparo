import 'package:material_ui/material_ui.dart';

import 'tokens.dart';

/// Tipografia do design: Plus Jakarta Sans. O ficheiro da fonte ainda não está nos assets,
/// por isso, até estar, o sistema usa a fonte do aparelho (ver README da app).
const familiaTexto = 'Plus Jakarta Sans';
const fontesAlternativas = ['Segoe UI', 'Roboto', 'SF Pro Text', 'sans-serif'];

ThemeData criarTema(Tokens t) {
  final esquema = ColorScheme(
    brightness: t.escuro ? Brightness.dark : Brightness.light,
    primary: t.primaria,
    onPrimary: t.sobrePrimaria,
    secondary: t.primariaSuave,
    onSecondary: t.sobrePrimariaSuave,
    error: t.mau,
    onError: t.escuro ? const Color(0xFF3F1010) : const Color(0xFFFFFFFF),
    surface: t.superficie,
    onSurface: t.texto,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: esquema,
    scaffoldBackgroundColor: Colors.transparent,
    fontFamily: familiaTexto,
    fontFamilyFallback: fontesAlternativas,
    extensions: [t],
    splashFactory: NoSplash.splashFactory,
    textTheme: Typography.material2021().black.apply(
      bodyColor: t.texto,
      displayColor: t.texto,
    ),
  );
}

/// Os estilos de texto do design: base de 15 px, títulos de 22 px.
class Estilos {
  Estilos._();

  static TextStyle titulo(Tokens t) => TextStyle(
    fontSize: 22,
    height: 1.15,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.44,
    color: t.texto,
  );
  static TextStyle subtitulo(Tokens t) =>
      TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: t.texto2);
  static TextStyle corpo(
    Tokens t, {
    FontWeight peso = FontWeight.w600,
    Color? cor,
  }) => TextStyle(
    fontSize: 15,
    height: 1.4,
    fontWeight: peso,
    color: cor ?? t.texto,
  );
}
