import 'package:amparo/dados/autenticacao.dart';

/// Autenticação falsa, só para os testes: aceita qualquer credencial.
class AutenticacaoMemoria implements Autenticacao {
  AutenticacaoMemoria({this.nomeFixo = 'Ana'});
  final String nomeFixo;
  bool _dentro = false;
  String? _nomeRegisto;

  @override
  String? get nome => _dentro ? (_nomeRegisto ?? nomeFixo) : null;

  @override
  Future<String?> entrar(String email, String senha) async {
    if (emailsPorVerificar.contains(email)) return 'email_nao_verificado';
    _dentro = true;
    return null;
  }

  /// Ligado, o registo só abre sessão depois de confirmar o email com [codigoDeVerificacao].
  bool exigirVerificacao = false;
  String codigoDeVerificacao = '482915';
  final emailsPorVerificar = <String>{};
  final reenvios = <String>[];
  final tentativasDeVerificacao = <String>[];

  @override
  Future<String?> registar(String nome, String email, String senha) async {
    _nomeRegisto = nome;
    if (exigirVerificacao) {
      emailsPorVerificar.add(email);
      return 'verificacao_necessaria';
    }
    _dentro = true;
    return null;
  }

  @override
  Future<String?> verificarEmail(String email, String codigo) async {
    tentativasDeVerificacao.add(codigo);
    if (codigo.replaceAll(' ', '') != codigoDeVerificacao) {
      return 'codigo_invalido';
    }
    emailsPorVerificar.remove(email);
    _dentro = true;
    return null;
  }

  @override
  Future<String?> reenviarVerificacao(String email) async {
    reenvios.add(email);
    return null;
  }

  final pedidosDeRecuperacao = <String>[];
  String tokenValido = '482915';
  String? senhaReposta;

  /// Contas Google já conhecidas pelo servidor falso; as outras precisam de consentimento.
  final contasGoogleExistentes = <String>{};
  final entradasGoogle = <({String idToken, bool aceitaTermos})>[];
  String? erroGoogle;

  @override
  Future<String?> entrarComGoogle(
    String idToken,
    String nonce, {
    String? nome,
    bool aceitaTermos = false,
  }) async {
    entradasGoogle.add((idToken: idToken, aceitaTermos: aceitaTermos));
    if (erroGoogle != null) return erroGoogle;
    if (!contasGoogleExistentes.contains(idToken) && !aceitaTermos) {
      return 'consentimento_necessario';
    }
    contasGoogleExistentes.add(idToken);
    _dentro = true;
    _nomeRegisto = nome ?? nomeFixo;
    return null;
  }

  @override
  Future<String?> pedirRecuperacao(String email) async {
    pedidosDeRecuperacao.add(email);
    return null;
  }

  final verificacoes = <String>[];

  @override
  Future<String?> verificarCodigo(String email, String codigo) async {
    verificacoes.add(codigo);
    return codigo.replaceAll(' ', '') == tokenValido ? null : 'token_invalido';
  }

  @override
  Future<String?> reporSenha(String email, String codigo, String senha) async {
    if (codigo.replaceAll(' ', '') != tokenValido) return 'token_invalido';
    senhaReposta = senha;
    return null;
  }

  final entradasApple = <String>[];

  @override
  Future<String?> entrarComApple(
    String idToken,
    String nonce, {
    String? nome,
    bool aceitaTermos = false,
  }) async {
    entradasApple.add(idToken);
    if (!contasGoogleExistentes.contains(idToken) && !aceitaTermos) {
      return 'consentimento_necessario';
    }
    contasGoogleExistentes.add(idToken);
    _dentro = true;
    _nomeRegisto = nome ?? nomeFixo;
    return null;
  }

  /// Uma conta criada só com a Apple ou a Google não tem palavra-passe.
  bool temSenha = true;
  String senhaDaConta = 'uma-senha-segura-123';
  bool contaApagada = false;

  @override
  Future<DadosConta> dadosConta() async =>
      DadosConta(temSenha: temSenha, criadaEm: DateTime(2026, 11, 18));

  @override
  Future<String> exportarDados() async =>
      '{"conta":{"nome":"${nome ?? ''}"},"pessoas":[]}';

  @override
  Future<String?> apagarConta({String? senha}) async {
    if (temSenha && senha != senhaDaConta) return 'senha_incorreta';
    contaApagada = true;
    _dentro = false;
    return null;
  }

  @override
  Future<bool> restaurar() async => _dentro;

  @override
  Future<void> sair() async => _dentro = false;
}
