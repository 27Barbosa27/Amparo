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

  @override
  Future<bool> restaurar() async => _dentro;

  @override
  Future<void> sair() async => _dentro = false;
}
