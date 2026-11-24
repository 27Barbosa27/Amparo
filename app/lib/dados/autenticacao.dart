import 'api.dart';

/// Entrar e sair. Só cuidadores têm conta.
abstract class Autenticacao {
  /// Devolve o código de erro estável (`credenciais_invalidas`, `demasiadas_tentativas`, `sem_rede`...) ou nulo se entrou.
  Future<String?> entrar(String email, String senha);

  /// Cria a conta de cuidador (com o consentimento) e abre a sessão. Devolve o código de erro
  /// (`email_ja_existe`, `pedido_invalido`, `sem_rede`...) ou nulo se correu bem.
  Future<String?> registar(String nome, String email, String senha);

  /// Tenta retomar a sessão guardada. Verdadeiro se há sessão válida.
  Future<bool> restaurar();

  /// Pede o email de recuperação. A resposta é sempre a mesma, exista a conta ou não: devolve só erros de
  /// rede ou de limite (`sem_rede`, `demasiadas_tentativas`), ou nulo.
  Future<String?> pedirRecuperacao(String email);

  /// Confirma o código do email SEM o gastar (conta as tentativas erradas): só depois de confirmado se
  /// deixa escolher a palavra-passe. Devolve `token_invalido`, `sem_rede`..., ou nulo se está certo.
  Future<String?> verificarCodigo(String email, String codigo);

  /// Define a nova palavra-passe com o código de 6 dígitos do email. Devolve `token_invalido` (errado,
  /// expirado, já usado ou esgotado), `pedido_invalido`, `sem_rede`..., ou nulo se correu bem.
  Future<String?> reporSenha(String email, String codigo, String senha);

  Future<void> sair();

  /// O nome do cuidador que entrou (para "Marcada por Ana").
  String? get nome;
}

class AutenticacaoApi implements Autenticacao {
  AutenticacaoApi(this._api);
  final ClienteApi _api;
  String? _nome;

  @override
  String? get nome => _nome;

  @override
  Future<String?> entrar(String email, String senha) async {
    try {
      final j = await _api.pedir(
        'POST',
        '/auth/login',
        corpo: {'email': email, 'senha': senha},
        autenticado: false,
      );
      await _api.sessao.guardar(
        acesso: j!['accessToken'] as String,
        renovacao: j['refreshToken'] as String,
      );
      _nome = (j['utilizador'] as Map)['nome'] as String?;
      return null;
    } on ErroApi catch (e) {
      return e.codigo;
    }
  }

  @override
  Future<String?> registar(String nome, String email, String senha) async {
    try {
      final j = await _api.pedir(
        'POST',
        '/auth/registo',
        corpo: {
          'email': email,
          'senha': senha,
          'nome': nome,
          'aceitaTermos': true,
        },
        autenticado: false,
      );
      await _api.sessao.guardar(
        acesso: j!['accessToken'] as String,
        renovacao: j['refreshToken'] as String,
      );
      _nome = (j['utilizador'] as Map)['nome'] as String? ?? nome;
      return null;
    } on ErroApi catch (e) {
      return e.codigo;
    }
  }

  @override
  Future<String?> pedirRecuperacao(String email) async {
    try {
      await _api.pedir(
        'POST',
        '/auth/recuperar',
        corpo: {'email': email.trim()},
        autenticado: false,
      );
      return null;
    } on ErroApi catch (e) {
      return e.codigo;
    }
  }

  @override
  Future<String?> verificarCodigo(String email, String codigo) async {
    try {
      await _api.pedir(
        'POST',
        '/auth/recuperar/verificar',
        corpo: {
          'email': email.trim(),
          'codigo': codigo.replaceAll(RegExp(r'\s'), ''),
        },
        autenticado: false,
      );
      return null;
    } on ErroApi catch (e) {
      return e.codigo;
    }
  }

  @override
  Future<String?> reporSenha(String email, String codigo, String senha) async {
    try {
      await _api.pedir(
        'POST',
        '/auth/repor',
        corpo: {
          'email': email.trim(),
          'codigo': codigo.replaceAll(RegExp(r'\s'), ''),
          'senha': senha,
        },
        autenticado: false,
      );
      return null;
    } on ErroApi catch (e) {
      return e.codigo;
    }
  }

  @override
  Future<bool> restaurar() async {
    if (_api.sessao.renovacao == null) return false;
    try {
      final j = await _api.pedir('GET', '/auth/me');
      _nome = (j?['utilizador'] as Map?)?['nome'] as String?;
      return true;
    } on ErroApi {
      return false;
    }
  }

  @override
  Future<void> sair() async {
    final renovacao = _api.sessao.renovacao;
    if (renovacao != null) {
      try {
        await _api.pedir(
          'POST',
          '/auth/logout',
          corpo: {'refreshToken': renovacao},
          autenticado: false,
        );
      } on ErroApi {
        // sem rede: a sessão local apaga-se na mesma
      }
    }
    await _api.sessao.limpar();
    _nome = null;
  }
}
