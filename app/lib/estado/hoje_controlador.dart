import 'package:material_ui/material_ui.dart';

import '../dados/alarmes.dart';
import '../dados/api.dart';
import '../dados/repositorio.dart';
import '../dominio/modelos.dart';

typedef Relogio = DateTime Function();

/// O estado do ecrã "Hoje" de um perfil: as tomas, o resumo e as ações (marcar, saltar, desfazer).
class HojeControlador extends ChangeNotifier {
  HojeControlador({
    required this.repositorio,
    required this.perfil,
    required this.relogio,
    this.cuidador,
    this.aoSessaoExpirada,
    this.alarmes = const ServicoAlarmesNulo(),
    this.agendarAlarmes = true,
    this.aposCarregar,
  });

  final Repositorio repositorio;
  final Perfil perfil;
  final Relogio relogio;

  /// Alarmes locais das tomas: reagendados sempre que as tomas deste perfil são recarregadas.
  final ServicoAlarmes alarmes;

  /// Falso quando os alarmes deste perfil tocam noutro telemóvel (o da pessoa): aqui não se agenda nada.
  final bool agendarAlarmes;

  /// Depois de cada carregamento bem-sucedido (o telemóvel da pessoa conta ao servidor como estão os alarmes).
  final Future<void> Function()? aposCarregar;

  /// Quem está a usar a app, quando é um cuidador. Nulo no telemóvel da pessoa.
  final String? cuidador;

  /// Chamado quando a sessão expirou e não deu para a renovar (volta ao ecrã de Entrar).
  final VoidCallback? aoSessaoExpirada;

  List<Toma> _tomas = const [];
  List<DiaAdesao> _semana = const [];
  String? _nomeCuidador;
  bool _aCarregar = true;
  String? _erro;
  bool _falhouCarregar = false;

  List<Toma> get tomas => _tomas;
  bool get aCarregar => _aCarregar;
  List<DiaAdesao> get semana => _semana;

  /// Quem cuida da pessoa (para "Ligar à Ana" no modo simples).
  String? get nomeCuidador => _nomeCuidador;

  /// Código estável do último erro (ver "Erros" no plano), ou nulo.
  String? get erro => _erro;

  /// Verdadeiro se a última tentativa de carregar as tomas falhou.
  bool get falhouCarregar => _falhouCarregar;

  DateTime get agora => relogio();

  ResumoDia get resumo => ResumoDia.de(_tomas, agora);

  /// A toma a pôr em destaque no modo simples: a mais antiga atrasada, senão a próxima por tomar.
  Toma? get emDestaque {
    final pendentes =
        _tomas.where((t) => t.estado == EstadoToma.pendente).toList()
          ..sort((a, b) => a.agendada.compareTo(b.agendada));
    return pendentes.isEmpty ? null : pendentes.first;
  }

  Future<void> carregar() async {
    _aCarregar = true;
    _erro = null;
    _falhouCarregar = false;
    notifyListeners();
    try {
      _tomas = await repositorio.tomasDeHoje(perfil.id, agora);
      _tomas = [..._tomas]..sort((a, b) => a.agendada.compareTo(b.agendada));
      _semana = await repositorio.ultimos7Dias(perfil.id, agora);
      _nomeCuidador = await repositorio.nomeDoCuidador(perfil.id);
      if (agendarAlarmes) await alarmes.agendarParaTomas(perfil.id, _tomas);
      await aposCarregar?.call().catchError((_) {});
    } on ErroApi catch (e) {
      _falhouCarregar = true;
      _erro = e.codigo;
      if (e.codigo == 'sessao_expirada') aoSessaoExpirada?.call();
    } catch (_) {
      _falhouCarregar = true;
      _erro = 'falha_ao_carregar';
    }
    _aCarregar = false;
    notifyListeners();
  }

  Future<bool> _executar(Future<Toma> Function() acao) async {
    _erro = null;
    try {
      final nova = await acao();
      _tomas = [for (final t in _tomas) t.id == nova.id ? nova : t];
      if (agendarAlarmes) await alarmes.agendarParaTomas(perfil.id, _tomas);
      notifyListeners();
      return true;
    } on RegistoNaoPermitido catch (e) {
      _erro = e.motivo;
    } on ErroApi catch (e) {
      _erro = e.codigo;
      if (e.codigo == 'sessao_expirada') aoSessaoExpirada?.call();
    } catch (_) {
      _erro = 'falha_ao_guardar';
    }
    notifyListeners();
    return false;
  }

  Future<bool> marcarTomada(Toma t, {DateTime? hora}) => _executar(
    () => repositorio.marcarTomada(
      perfil.id,
      t.id,
      agora,
      hora: hora,
      porCuidador: cuidador,
    ),
  );

  Future<bool> saltar(Toma t) => _executar(
    () => repositorio.saltar(perfil.id, t.id, agora, porCuidador: cuidador),
  );

  Future<bool> desfazer(Toma t) =>
      _executar(() => repositorio.desfazer(perfil.id, t.id, agora));
}
