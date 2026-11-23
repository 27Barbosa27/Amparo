import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'dados/repositorio_memoria.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('pt_PT');
  // Dados falsos até a app falar com a API (backend/).
  const tela = String.fromEnvironment('TELA');
  runApp(
    AmparoApp(
      repositorio: RepositorioMemoria(agora: DateTime.now()),
      telaInicial: tela,
    ),
  );
}
