import '../dominio/modelos.dart';

/// A fronteira entre a app e os dados. Só há uma versão em produção ([RepositorioApi]); os testes
/// usam uma versão falsa que vive em `test/`.
abstract class Repositorio {
  Future<List<Perfil>> perfis();

  /// Adiciona uma pessoa acompanhada. O cuidador declara que tem a autorização dela (o backend exige-o).
  Future<Perfil> criarPessoa(NovaPessoa pessoa);

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

  /// As receitas da pessoa, com os dias que restam e a validade.
  Future<List<Receita>> receitas(String perfilId);

  /// Cria o medicamento e a receita. As tomas geram-se em segundo plano: seguir com [estadoGeracao].
  Future<Receita> criarReceita(
    String perfilId,
    NovaReceita receita,
    DateTime agora,
  );

  /// Edita o medicamento (nome) e a receita (dose e horário); as tomas futuras ainda por registar refazem-se.
  Future<void> alterarReceita(
    String perfilId,
    Receita antiga,
    NovaReceita nova,
  );

  /// Apaga a receita e as tomas dela.
  Future<void> apagarReceita(String perfilId, String receitaId);

  Future<EstadoGeracao> estadoGeracao(String perfilId, String receitaId);

  /// Os últimos 7 dias (o último é hoje), para o cartão de adesão.
  Future<List<DiaAdesao>> ultimos7Dias(String perfilId, DateTime agora);

  /// Um código novo (vale 15 minutos, uso único) para ligar o telemóvel da pessoa.
  Future<CodigoLigacao> criarCodigoLigacao(String perfilId);

  Future<EstadoCodigo> estadoCodigo(String perfilId, String codigoId);

  /// Quem cuida da pessoa, para o botão "Ligar à Ana".
  Future<String?> nomeDoCuidador(String perfilId);
}

class RegistoNaoPermitido implements Exception {
  const RegistoNaoPermitido(this.motivo);
  final String motivo;
  @override
  String toString() => 'RegistoNaoPermitido: $motivo';
}
