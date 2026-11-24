import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Um erro da API com o código estável do plano (`credenciais_invalidas`, `sem_rede`, `toma_ja_registada`...).
class ErroApi implements Exception {
  const ErroApi(this.codigo, [this.estado = 0]);

  final String codigo;

  /// Estado HTTP (0 quando nem chegou a haver resposta).
  final int estado;

  @override
  String toString() => 'ErroApi($codigo, $estado)';
}

/// Onde ficam os tokens. Por agora só em memória; o armazenamento seguro do sistema
/// (Keychain/Keystore) liga-se aqui quando o Modo de Programador do Windows estiver ligado.
abstract class SessaoStore {
  String? get acesso;
  String? get renovacao;
  Future<void> guardar({required String acesso, required String renovacao});
  Future<void> limpar();
}

class SessaoMemoria implements SessaoStore {
  @override
  String? acesso;
  @override
  String? renovacao;

  @override
  Future<void> guardar({
    required String acesso,
    required String renovacao,
  }) async {
    this.acesso = acesso;
    this.renovacao = renovacao;
  }

  @override
  Future<void> limpar() async {
    acesso = null;
    renovacao = null;
  }
}

/// Fala com o backend: JSON, `Authorization: Bearer`, `X-Profile-Id`, e renova a sessão uma vez quando o
/// token de acesso expira (o refresh token é de uso único, por isso há só uma renovação de cada vez).
class ClienteApi {
  ClienteApi({
    required this.base,
    required this.sessao,
    http.Client? cliente,
    this.tempoLimite = const Duration(seconds: 20),
  }) : _http = cliente ?? http.Client();

  final Uri base;
  final SessaoStore sessao;
  final Duration tempoLimite;
  final http.Client _http;
  Future<bool>? _renovacaoEmCurso;

  Uri _uri(String caminho, Map<String, String>? query) => base.replace(
    path: '${base.path}$caminho'.replaceAll('//', '/'),
    queryParameters: query,
  );

  Future<http.Response> _enviar(
    String metodo,
    String caminho, {
    Map<String, Object?>? corpo,
    String? perfilId,
    Map<String, String>? query,
    bool autenticado = true,
    Map<String, String>? cabecalhos,
  }) async {
    final pedido = http.Request(metodo, _uri(caminho, query));
    pedido.headers['content-type'] = 'application/json';
    pedido.headers['accept'] = 'application/json';
    if (autenticado && sessao.acesso != null) {
      pedido.headers['authorization'] = 'Bearer ${sessao.acesso}';
    }
    if (perfilId != null) pedido.headers['x-profile-id'] = perfilId;
    if (cabecalhos != null) pedido.headers.addAll(cabecalhos);
    if (corpo != null) pedido.body = jsonEncode(corpo);
    try {
      return await http.Response.fromStream(
        await _http.send(pedido).timeout(tempoLimite),
      );
    } on TimeoutException {
      throw const ErroApi('sem_rede');
    } on http.ClientException {
      throw const ErroApi('sem_rede');
    }
  }

  /// Faz o pedido e devolve o JSON (ou nulo se a resposta for vazia). Lança [ErroApi] se falhar.
  Future<Map<String, dynamic>?> pedir(
    String metodo,
    String caminho, {
    Map<String, Object?>? corpo,
    String? perfilId,
    Map<String, String>? query,
    bool autenticado = true,
    Map<String, String>? cabecalhos,
  }) async {
    var r = await _enviar(
      metodo,
      caminho,
      corpo: corpo,
      perfilId: perfilId,
      query: query,
      autenticado: autenticado,
      cabecalhos: cabecalhos,
    );
    if (autenticado &&
        r.statusCode == 401 &&
        sessao.renovacao != null &&
        _codigo(r) == 'nao_autenticado') {
      if (await _renovar()) {
        r = await _enviar(
          metodo,
          caminho,
          corpo: corpo,
          perfilId: perfilId,
          query: query,
          cabecalhos: cabecalhos,
        );
      } else {
        throw const ErroApi('sessao_expirada', 401);
      }
    } else if (autenticado &&
        r.statusCode == 401 &&
        sessao.acesso != null &&
        sessao.renovacao == null &&
        _codigo(r) == 'nao_autenticado') {
      // O telemóvel de uma pessoa (só tem token de dispositivo) foi desligado pelo cuidador.
      throw const ErroApi('sessao_expirada', 401);
    }
    if (r.statusCode >= 200 && r.statusCode < 300) {
      if (r.body.isEmpty) return null;
      final json = jsonDecode(r.body);
      return json is Map<String, dynamic> ? json : null;
    }
    throw ErroApi(_codigo(r) ?? 'erro_servidor', r.statusCode);
  }

  String? _codigo(http.Response r) {
    try {
      final j = jsonDecode(r.body);
      return j is Map ? j['erro'] as String? : null;
    } catch (_) {
      return null;
    }
  }

  /// Troca o refresh token por um par novo. Pedidos em simultâneo esperam pela mesma renovação.
  Future<bool> _renovar() => _renovacaoEmCurso ??= _fazerRenovacao()
      .whenComplete(() => _renovacaoEmCurso = null);

  Future<bool> _fazerRenovacao() async {
    try {
      final r = await _enviar(
        'POST',
        '/auth/refresh',
        corpo: {'refreshToken': sessao.renovacao},
        autenticado: false,
      );
      if (r.statusCode != 200) {
        await sessao.limpar();
        return false;
      }
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      await sessao.guardar(
        acesso: j['accessToken'] as String,
        renovacao: j['refreshToken'] as String,
      );
      return true;
    } on ErroApi {
      return false; // sem rede: mantém a sessão, tenta de novo depois
    }
  }

  void fechar() => _http.close();
}
