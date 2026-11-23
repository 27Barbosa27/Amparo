import '../dominio/modelos.dart';

/// A fronteira entre a app e os dados. Hoje há só a versão com dados falsos ([RepositorioMemoria]);
/// a seguir entra a versão que fala com a API (`backend/`), sem mexer nos ecrãs.
abstract class Repositorio {
  Future<List<Perfil>> perfis();

  /// As tomas do dia (da meia-noite à meia-noite local) de `agora`.
  Future<List<Toma>> tomasDeHoje(String perfilId, DateTime agora);

  /// `hora` é a hora real da toma ("Agora", "Há 1 hora", "À hora prevista", "Outra hora"). Por omissão, agora.
  /// `porCuidador` é o nome de quem registou, se foi um cuidador.
  Future<Toma> marcarTomada(
    String perfilId,
    String tomaId,
    DateTime agora, {
    DateTime? hora,
    String? porCuidador,
  });

  Future<Toma> saltar(
    String perfilId,
    String tomaId,
    DateTime agora, {
    String? porCuidador,
  });

  /// Só funciona até 1 minuto depois do registo.
  Future<Toma> desfazer(String perfilId, String tomaId, DateTime agora);

  /// Os últimos 7 dias (o último é hoje), para o cartão de adesão.
  Future<List<DiaAdesao>> ultimos7Dias(String perfilId, DateTime agora);

  /// Quem cuida da pessoa, para o botão "Ligar à Ana".
  Future<String?> nomeDoCuidador(String perfilId);
}

class RegistoNaoPermitido implements Exception {
  const RegistoNaoPermitido(this.motivo);
  final String motivo;
  @override
  String toString() => 'RegistoNaoPermitido: $motivo';
}
