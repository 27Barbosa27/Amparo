import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../dados/api.dart';
import '../../dados/repositorio.dart';
import '../../dominio/modelos.dart';
import '../../tema/tema.dart';
import '../../tema/tokens.dart';
import '../componentes/base.dart';
import '../componentes/estilo.dart';
import '../componentes/formulario.dart';
import '../componentes/icones.dart';
import 'cuidador_hoje.dart' show horaCurta, itemQueSobe;

/// "Histórico de tomas": como correram os últimos 7 ou 30 dias. Em cima a adesão e os números do período; por
/// baixo, dia a dia (do mais recente para o mais antigo), cada toma com o seu resultado.
class HistoricoTomasEcra extends StatefulWidget {
  const HistoricoTomasEcra({
    super.key,
    required this.repositorio,
    required this.perfil,
    this.cuidador,
    this.relogio = DateTime.now,
  });

  final Repositorio repositorio;
  final Perfil perfil;

  /// Quem usa a app (para não escrever "Marcada por" quando foi a própria pessoa).
  final String? cuidador;
  final DateTime Function() relogio;

  @override
  State<HistoricoTomasEcra> createState() => _HistoricoTomasEcraState();
}

class _HistoricoTomasEcraState extends State<HistoricoTomasEcra> {
  int _dias = 7;
  List<Toma> _tomas = const [];
  bool _aCarregar = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _aCarregar = true;
      _erro = null;
    });
    final agora = widget.relogio();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    try {
      final tomas = await widget.repositorio.historico(
        widget.perfil.id,
        hoje.subtract(Duration(days: _dias - 1)),
        hoje.add(const Duration(days: 1)),
      );
      if (!mounted) return;
      setState(() {
        _tomas = tomas;
        _aCarregar = false;
      });
    } on ErroApi catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = e.codigo;
        _aCarregar = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _erro = 'falha_ao_carregar';
        _aCarregar = false;
      });
    }
  }

  void _mudarPeriodo(int dias) {
    if (dias == _dias) return;
    setState(() => _dias = dias);
    _carregar();
  }

  String _tituloDoDia(DateTime dia, DateTime hoje) {
    final d = DateTime(dia.year, dia.month, dia.day);
    if (d == hoje) return 'Hoje';
    if (d == hoje.subtract(const Duration(days: 1))) return 'Ontem';
    final s = DateFormat("EEEE, d 'de' MMMM", 'pt_PT').format(d);
    return s[0].toUpperCase() + s.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final agora = widget.relogio();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    final resumo = ResumoHistorico.de(_tomas, agora);
    final proprio = eProprioCuidador(widget.perfil, widget.cuidador);

    // Os dias, do mais recente para o mais antigo (só os que têm tomas).
    final porDia = <DateTime, List<Toma>>{};
    for (final toma in _tomas) {
      final d = DateTime(
        toma.agendada.year,
        toma.agendada.month,
        toma.agendada.day,
      );
      porDia.putIfAbsent(d, () => []).add(toma);
    }
    final dias = porDia.keys.toList()..sort((a, b) => b.compareTo(a));

    final blocos = <Widget>[
      CabecalhoFormulario(
        titulo: 'Histórico de tomas',
        subtitulo: proprio
            ? 'Como correram as suas tomas.'
            : 'Como correram as tomas de ${widget.perfil.nome}.',
        espaco: 14,
      ),
      GrelhaOpcoes<int>(
        titulo: 'Período',
        opcoes: const [7, 30],
        texto: (d) => 'Últimos $d dias',
        valor: _dias,
        aoEscolher: _mudarPeriodo,
      ),
      if (_aCarregar)
        const Padding(
          padding: EdgeInsets.only(top: 30),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (_erro != null)
        Cartao(
          raio: 5,
          cor: t.mauSuave,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _erro == 'sem_rede'
                    ? 'Sem ligação. Verifique a internet e tente outra vez.'
                    : 'Não foi possível carregar o histórico.',
                style: Estilos.corpo(t, peso: FontWeight.w800, cor: t.mauTexto),
              ),
              const SizedBox(height: 12),
              Botao(
                texto: 'Tentar outra vez',
                icone: Icons.refresh,
                aoTocar: _carregar,
              ),
            ],
          ),
        )
      else ...[
        _CartaoAdesao(resumo: resumo, dias: _dias),
        if (dias.isEmpty)
          Cartao(
            raio: 5,
            child: Text(
              'Ainda não há tomas neste período.',
              style: Estilos.corpo(t),
            ),
          )
        else
          for (final (i, dia) in dias.indexed)
            itemQueSobe(
              i,
              _Dia(
                titulo: _tituloDoDia(dia, hoje),
                tomas: porDia[dia]!,
                agora: agora,
                proprio: proprio,
              ),
            ),
      ],
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: escalonar(blocos, espaco: 16),
    );
  }
}

/// A adesão do período, grande, e os números por baixo.
class _CartaoAdesao extends StatelessWidget {
  const _CartaoAdesao({required this.resumo, required this.dias});
  final ResumoHistorico resumo;
  final int dias;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final adesao = resumo.adesao;
    Widget numero(int n, String rotulo, Color cor) => Expanded(
      child: Column(
        children: [
          Text(
            '$n',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: cor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            rotulo,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: t.texto2,
            ),
          ),
        ],
      ),
    );
    return Cartao(
      raio: 5,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Semantics(
        container: true,
        label: adesao == null
            ? 'Ainda sem histórico'
            : 'Adesão de $adesao por cento nos últimos $dias dias',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  adesao == null ? '—' : '$adesao%',
                  style: TextStyle(
                    fontSize: 40,
                    height: 1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                    color: adesao == null ? t.texto2 : t.texto,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      adesao == null
                          ? 'Ainda sem histórico'
                          : 'de adesão nos últimos $dias dias',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: t.texto2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: t.linha)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  numero(resumo.tomadas, 'tomadas', t.okTexto),
                  numero(resumo.saltadas, 'saltadas', t.texto),
                  numero(resumo.esquecidas, 'esquecidas', t.mauTexto),
                  if (resumo.porConfirmar > 0)
                    numero(resumo.porConfirmar, 'por confirmar', t.avisoTexto),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Um dia: o título, quantas foram tomadas e as tomas, cada uma com a hora e o resultado.
class _Dia extends StatelessWidget {
  const _Dia({
    required this.titulo,
    required this.tomas,
    required this.agora,
    required this.proprio,
  });
  final String titulo;
  final List<Toma> tomas;
  final DateTime agora;
  final bool proprio;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final feitas = tomas
        .where((x) => x.resultado(agora) == ResultadoToma.tomada)
        .length;
    final ordenadas = [...tomas]
      ..sort((a, b) => a.agendada.compareTo(b.agendada));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    titulo,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: t.texto,
                    ),
                  ),
                ),
              ),
              Text(
                '$feitas/${tomas.length} tomadas',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: t.texto2,
                ),
              ),
            ],
          ),
        ),
        Cartao(
          raio: 5,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            children: [
              for (final (i, toma) in ordenadas.indexed)
                _LinhaToma(
                  toma: toma,
                  agora: agora,
                  proprio: proprio,
                  primeira: i == 0,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LinhaToma extends StatelessWidget {
  const _LinhaToma({
    required this.toma,
    required this.agora,
    required this.proprio,
    required this.primeira,
  });
  final Toma toma;
  final DateTime agora;
  final bool proprio;
  final bool primeira;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final resultado = toma.resultado(agora);
    final (Widget selo, String texto, Color cor) = switch (resultado) {
      ResultadoToma.tomada => (
        SeloIcone(cor: t.ok, dados: Icones.visto, corIcone: t.superficie),
        'Tomada às ${horaCurta(toma.tomadaEm ?? toma.agendada)}',
        t.okTexto,
      ),
      ResultadoToma.saltada => (
        SeloIcone(
          cor: t.superficie2,
          dados: const IconeDados('<path d="M7 12h10"/>'),
          corIcone: t.texto2,
          contorno: t.linha,
          tamanhoIcone: 14,
          traco: 2.6,
        ),
        'Saltada',
        t.texto2,
      ),
      ResultadoToma.esquecida => (
        SeloIcone(cor: t.mau, dados: Icones.x, corIcone: t.superficie),
        'Não foi tomada',
        t.mauTexto,
      ),
      ResultadoToma.porConfirmar => (
        SeloIcone(
          cor: t.aviso,
          dados: Icones.alerta,
          corIcone: Tokens.sobreAviso,
        ),
        'Por confirmar',
        t.avisoTexto,
      ),
      ResultadoToma.porTomar => (
        SeloIcone(
          cor: t.superficie2,
          dados: Icones.relogio,
          corIcone: t.texto2,
          contorno: t.linha,
          tamanhoIcone: 14,
          traco: 2.6,
        ),
        'Por tomar',
        t.texto2,
      ),
    };
    final detalhe = [
      if (toma.dose.isNotEmpty) toma.dose,
      if (resultado == ResultadoToma.tomada &&
          toma.registadaPor != null &&
          !proprio)
        'Marcada por ${toma.registadaPor}',
    ].join(' · ');
    return Semantics(
      container: true,
      label: '${horaCurta(toma.agendada)}, ${toma.medicamento}. $texto',
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          border: primeira ? null : Border(top: BorderSide(color: t.linha)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 48,
              child: Text(
                horaCurta(toma.agendada),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: t.texto,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    toma.medicamento,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                      color: t.texto,
                    ),
                  ),
                  if (detalhe.isNotEmpty)
                    Text(
                      detalhe,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: t.texto2,
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    texto,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: cor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            selo,
          ],
        ),
      ),
    );
  }
}
