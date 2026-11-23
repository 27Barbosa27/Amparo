import 'package:material_ui/material_ui.dart';

import '../dados/api.dart';
import '../dados/repositorio.dart';
import '../dominio/modelos.dart';

/// O estado do ecrã "Receitas" de uma pessoa.
class ReceitasControlador extends ChangeNotifier {
  ReceitasControlador({
    required this.repositorio,
    required this.perfil,
    this.aoSessaoExpirada,
  });

  final Repositorio repositorio;
  final Perfil perfil;
  final VoidCallback? aoSessaoExpirada;

  List<Receita> _receitas = const [];
  bool _aCarregar = true;
  String? _erro;

  List<Receita> get receitas => _receitas;
  bool get aCarregar => _aCarregar;

  /// Código estável do último erro (`sem_rede`...), ou nulo.
  String? get erro => _erro;

  /// A receita mais urgente: a primeira cujos dias que restam chegaram ao limite do aviso.
  Receita? get aAcabar {
    final lista = _receitas.where((r) => r.ativa && r.aAcabar()).toList()
      ..sort((a, b) => a.diasRestantes!.compareTo(b.diasRestantes!));
    return lista.isEmpty ? null : lista.first;
  }

  /// As restantes receitas ativas ("Em dia").
  List<Receita> get emDia {
    final urgente = aAcabar;
    return [
      for (final r in _receitas)
        if (r.ativa && r.id != urgente?.id) r,
    ];
  }

  Future<void> carregar() async {
    _aCarregar = true;
    _erro = null;
    notifyListeners();
    try {
      _receitas = await repositorio.receitas(perfil.id);
    } on ErroApi catch (e) {
      _erro = e.codigo;
      if (e.codigo == 'sessao_expirada') aoSessaoExpirada?.call();
    } catch (_) {
      _erro = 'falha_ao_carregar';
    }
    _aCarregar = false;
    notifyListeners();
  }
}
