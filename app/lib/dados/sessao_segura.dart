import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api.dart';

/// Guarda os tokens no armazenamento seguro do sistema (Keychain no iOS, Keystore no Android, o cofre do
/// Windows). Os valores lêem-se uma vez ao arrancar ([carregar]) e ficam em memória, por isso o resto da
/// app continua a usá-los de forma síncrona. Se o armazenamento falhar, a sessão vive só em memória.
class SessaoSegura implements SessaoStore {
  SessaoSegura([FlutterSecureStorage? armazem])
    : _armazem = armazem ?? const FlutterSecureStorage();

  final FlutterSecureStorage _armazem;
  static const _chaveAcesso = 'amparo.acesso';
  static const _chaveRenovacao = 'amparo.renovacao';

  @override
  String? acesso;
  @override
  String? renovacao;

  /// Lê a sessão guardada (chamar antes de arrancar a app).
  Future<void> carregar() async {
    try {
      acesso = await _armazem.read(key: _chaveAcesso);
      renovacao = await _armazem.read(key: _chaveRenovacao);
    } catch (_) {
      acesso = null;
      renovacao = null;
    }
  }

  @override
  Future<void> guardar({
    required String acesso,
    required String renovacao,
  }) async {
    this.acesso = acesso;
    this.renovacao = renovacao;
    try {
      await _armazem.write(key: _chaveAcesso, value: acesso);
      await _armazem.write(key: _chaveRenovacao, value: renovacao);
    } catch (_) {
      // sem armazenamento seguro: a sessão fica só em memória
    }
  }

  @override
  Future<void> limpar() async {
    acesso = null;
    renovacao = null;
    try {
      await _armazem.delete(key: _chaveAcesso);
      await _armazem.delete(key: _chaveRenovacao);
    } catch (_) {}
  }
}
