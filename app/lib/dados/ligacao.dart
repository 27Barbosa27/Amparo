import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../dominio/modelos.dart';
import 'api.dart';
import 'repositorio.dart';
import 'repositorio_api.dart';

/// O telemóvel de uma pessoa acompanhada: liga-se com um código de 6 dígitos (sem conta) e passa a ter um
/// token de dispositivo que só alcança o perfil dela.
abstract class LigacaoDispositivo {
  /// Troca o código pelo token. Devolve o perfil ligado, ou um código de erro (`codigo_invalido`,
  /// `demasiadas_tentativas`, `sem_rede`...).
  Future<({Perfil? perfil, String? erro})> ligar(String codigo);

  /// O perfil a que este telemóvel já está ligado, se estiver.
  Future<Perfil?> restaurar();

  /// Os dados deste telemóvel (só existe depois de ligar ou restaurar).
  Repositorio? get repositorio;

  Future<void> desligar();
}

class LigacaoApi implements LigacaoDispositivo {
  LigacaoApi(this._base, [FlutterSecureStorage? armazem])
    : _armazem = armazem ?? const FlutterSecureStorage();

  final ClienteApi _base;
  final FlutterSecureStorage _armazem;
  static const _chave = 'amparo.dispositivo';
  RepositorioApi? _repo;

  @override
  Repositorio? get repositorio => _repo;

  Perfil _perfil(Map<String, dynamic> p) => Perfil(
    id: p['id'] as String,
    nome: p['pseudonimo'] as String,
    tamanhoTexto: TamanhoTexto.daApi(p['tamanhoTexto']),
  );

  void _usar(String token) {
    final sessao = SessaoMemoria()..acesso = token;
    _repo = RepositorioApi(ClienteApi(base: _base.base, sessao: sessao));
  }

  @override
  Future<({Perfil? perfil, String? erro})> ligar(String codigo) async {
    try {
      final j = await _base.pedir(
        'POST',
        '/pairing/redeem',
        corpo: {'codigo': codigo},
        autenticado: false,
      );
      final token = j!['token'] as String;
      final perfil = j['perfil'] as Map<String, dynamic>;
      try {
        await _armazem.write(
          key: _chave,
          value: jsonEncode({'token': token, 'perfil': perfil}),
        );
      } catch (_) {
        // sem armazenamento seguro: fica ligado só até fechar a app
      }
      _usar(token);
      return (perfil: _perfil(perfil), erro: null);
    } on ErroApi catch (e) {
      return (perfil: null, erro: e.codigo);
    }
  }

  @override
  Future<Perfil?> restaurar() async {
    try {
      final guardado = await _armazem.read(key: _chave);
      if (guardado == null) return null;
      final j = jsonDecode(guardado) as Map<String, dynamic>;
      _usar(j['token'] as String);
      return _perfil(j['perfil'] as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> desligar() async {
    _repo = null;
    try {
      await _armazem.delete(key: _chave);
    } catch (_) {}
  }
}
