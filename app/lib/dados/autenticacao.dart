import 'dart:convert';

import 'api.dart';

class DadosConta {
  const DadosConta({required this.temSenha, this.criadaEm});

  /// Falso numa conta criada só com a Apple ou a Google.
  final bool temSenha;
  final DateTime? criadaEm;
}

/// Entrar e sair. Só cuidadores têm conta.
abstract class Autenticacao {
  /// Devolve o código de erro estável (`credenciais_invalidas`, `demasiadas_tentativas`, `sem_rede`...) ou nulo se entrou.
  Future<String?> entrar(String email, String senha);

  /// Cria a conta de cuidador (com o consentimento). O servidor envia um código para o email: devolve
  /// `verificacao_necessaria` (a conta só abre sessão depois de o confirmar), ou o código de erro
  /// (`email_ja_existe`, `pedido_invalido`, `sem_rede`...), ou nulo se já abriu sessão.
  Future<String?> registar(String nome, String email, String senha);

  /// Confirma o email com o código de 6 números e abre a sessão. Devolve `codigo_invalido` (errado, expirado,
  /// usado ou esgotado), `sem_rede`..., ou nulo se correu bem.
  Future<String?> verificarEmail(String email, String codigo);

  /// Pede outro código de verificação (resposta sempre igual, exista a conta ou não).
  Future<String?> reenviarVerificacao(String email);

  /// Entra (ou cria a conta) com o ID token da Google. Se a conta é nova e `aceitaTermos` é falso, devolve
  /// `consentimento_necessario`: a app pede o consentimento e repete. Outros erros: `provedor_invalido`,
  /// `provedor_nao_configurado`, `sem_rede`...
  Future<String?> entrarComGoogle(
    String idToken,
    String nonce, {
    String? nome,
    bool aceitaTermos = false,
  });

  /// O mesmo que [entrarComGoogle], com o ID token da Apple. O nome só vem da Apple na primeira vez.
  Future<String?> entrarComApple(
    String idToken,
    String nonce, {
    String? nome,
    bool aceitaTermos = false,
  });

  /// "A sua conta": desde quando existe e se tem palavra-passe (senão, foi criada com a Apple ou a Google).
  Future<DadosConta> dadosConta();

  /// Portabilidade (RGPD): a conta e as pessoas de quem é responsável ("owner"), num só JSON legível.
  Future<String> exportarDados();

  /// Apaga a conta. Com palavra-passe pede-a ([senha]); sem ela, a confirmação explícita. Devolve
  /// `senha_incorreta`, `sem_rede`..., ou nulo se apagou (e a sessão local também).
  Future<String?> apagarConta({String? senha});

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
  Future<String?> entrarComGoogle(
    String idToken,
    String nonce, {
    String? nome,
    bool aceitaTermos = false,
  }) => _entrarExterno(
    'google',
    idToken,
    nonce,
    nome: nome,
    aceitaTermos: aceitaTermos,
  );

  @override
  Future<String?> entrarComApple(
    String idToken,
    String nonce, {
    String? nome,
    bool aceitaTermos = false,
  }) => _entrarExterno(
    'apple',
    idToken,
    nonce,
    nome: nome,
    aceitaTermos: aceitaTermos,
  );

  Future<String?> _entrarExterno(
    String provedor,
    String idToken,
    String nonce, {
    String? nome,
    bool aceitaTermos = false,
  }) async {
    try {
      final j = await _api.pedir(
        'POST',
        '/auth/$provedor',
        corpo: {
          'idToken': idToken,
          'nonce': nonce,
          if (nome != null && nome.trim().isNotEmpty) 'nome': nome.trim(),
          if (aceitaTermos) 'aceitaTermos': true,
        },
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
      // Com a verificação do email ligada o servidor não abre sessão: manda um código para o email.
      if (j!['verificacaoNecessaria'] == true) return 'verificacao_necessaria';
      await _api.sessao.guardar(
        acesso: j['accessToken'] as String,
        renovacao: j['refreshToken'] as String,
      );
      _nome = (j['utilizador'] as Map)['nome'] as String? ?? nome;
      return null;
    } on ErroApi catch (e) {
      return e.codigo;
    }
  }

  @override
  Future<String?> verificarEmail(String email, String codigo) async {
    try {
      final j = await _api.pedir(
        'POST',
        '/auth/verificar-email',
        corpo: {
          'email': email.trim(),
          'codigo': codigo.replaceAll(RegExp(r'\s'), ''),
        },
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
  Future<String?> reenviarVerificacao(String email) async {
    try {
      await _api.pedir(
        'POST',
        '/auth/reenviar-verificacao',
        corpo: {'email': email.trim()},
        autenticado: false,
      );
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
  Future<DadosConta> dadosConta() async {
    final u = (await _api.pedir('GET', '/auth/me'))!['utilizador'] as Map;
    return DadosConta(
      temSenha: u['temSenha'] != false,
      criadaEm: u['criadoEm'] == null
          ? null
          : DateTime.parse(u['criadoEm'] as String).toLocal(),
    );
  }

  @override
  Future<String> exportarDados() async {
    final conta = (await _api.pedir('GET', '/auth/me/exportacao'))!;
    // Os perfis de que é "owner" exportam-se inteiros (receitas, tomas...); nos outros só aparece o acesso.
    final pessoas = <Map<String, dynamic>>[];
    for (final p in (conta['perfis'] as List? ?? const [])) {
      if ((p as Map)['papel'] != 'owner') continue;
      final dados = await _api.pedir('GET', '/profiles/${p['id']}/exportacao');
      if (dados != null) pessoas.add(dados);
    }
    return const JsonEncoder.withIndent('  ')
        .convert({...conta, 'pessoas': pessoas});
  }

  @override
  Future<String?> apagarConta({String? senha}) async {
    try {
      await _api.pedir(
        'DELETE',
        '/auth/me',
        corpo: senha == null ? {'confirmar': true} : {'senha': senha},
      );
    } on ErroApi catch (e) {
      return e.codigo;
    }
    await _api.sessao.limpar();
    _nome = null;
    return null;
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
