import 'package:amparo/dados/ligacao.dart';
import 'package:amparo/dados/repositorio.dart';
import 'package:amparo/dominio/modelos.dart';

import 'repositorio_memoria.dart';

/// A ligação do telemóvel de uma pessoa, falsa, só para os testes.
class LigacaoMemoria implements LigacaoDispositivo {
  LigacaoMemoria({required this.agora, this.codigoCerto = '482915'});
  final DateTime agora;
  final String codigoCerto;
  Perfil? _perfil;
  RepositorioMemoria? _repo;
  int tentativas = 0;

  @override
  Repositorio? get repositorio => _repo;

  @override
  Future<({Perfil? perfil, String? erro})> ligar(String codigo) async {
    tentativas++;
    if (codigo != codigoCerto) return (perfil: null, erro: 'codigo_invalido');
    _perfil = const Perfil(id: 'maria', nome: 'Maria');
    _repo = RepositorioMemoria(agora: agora);
    return (perfil: _perfil, erro: null);
  }

  @override
  Future<Perfil?> restaurar() async => _perfil;

  @override
  Future<void> desligar() async {
    _perfil = null;
    _repo = null;
  }
}
