import 'package:material_ui/material_ui.dart';

import 'tokens.dart';

/// Tipografia do design: Plus Jakarta Sans (ficheiro em assets/fonts, declarado no pubspec).
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
    // A família tem de ir no `textTheme` (o `fontFamily` do tema só vale para o tema por omissão).
    textTheme: Typography.material2021().black.apply(
      bodyColor: t.texto,
      displayColor: t.texto,
      fontFamily: familiaTexto,
      fontFamilyFallback: fontesAlternativas,
    ),
  );
}

/// Os estilos de texto do design: base de 15 px, títulos de 22 px.
class Estilos {
  Estilos._();

  static TextStyle titulo(Tokens t) => TextStyle(
    fontSize: 22,
    height: 1.15,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.55,
    color: t.texto,
  );
  static TextStyle subtitulo(Tokens t) => TextStyle(
    fontSize: 15,
    height: 1.5,
    fontWeight: FontWeight.w500,
    color: t.texto2,
  );
  static TextStyle corpo(
    Tokens t, {
    FontWeight peso = FontWeight.w600,
    Color? cor,
    double altura = 1.4,
  }) => TextStyle(
    fontSize: 15,
    height: altura,
    fontWeight: peso,
    color: cor ?? t.texto,
  );
}
