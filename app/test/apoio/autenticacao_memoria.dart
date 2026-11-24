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
    _dentro = true;
    return null;
  }

  @override
  Future<String?> registar(String nome, String email, String senha) async {
    _dentro = true;
    _nomeRegisto = nome;
    return null;
  }

  final pedidosDeRecuperacao = <String>[];
  String tokenValido = '482915';
  String? senhaReposta;

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

  @override
  Future<bool> restaurar() async => _dentro;

  @override
  Future<void> sair() async => _dentro = false;
}
