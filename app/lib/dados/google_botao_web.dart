import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as web;

/// No browser o Google só permite entrar pelo botão que ele próprio desenha (Google Identity Services).
Widget? botaoGoogleWeb() => web.renderButton(
  configuration: web.GSIButtonConfiguration(
    type: web.GSIButtonType.standard,
    theme: web.GSIButtonTheme.outline,
    size: web.GSIButtonSize.large,
    text: web.GSIButtonText.continueWith,
    shape: web.GSIButtonShape.rectangular,
    minimumWidth: 400,
    locale: 'pt-PT',
  ),
);
