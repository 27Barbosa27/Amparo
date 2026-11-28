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
import '../componentes/resultado.dart';

/// "há 5 minutos", "há 2 horas", "ontem, 08:12", "18 nov, 08:12". Só para mostrar quando falou com o servidor.
String haQuantoTempo(DateTime quando, DateTime agora) {
  final d = agora.difference(quando);
  if (d.inMinutes < 1) return 'agora mesmo';
  if (d.inMinutes < 60) {
    return 'há ${d.inMinutes} ${d.inMinutes == 1 ? 'minuto' : 'minutos'}';
  }
  if (d.inHours < 24 && quando.day == agora.day) {
    return 'há ${d.inHours} ${d.inHours == 1 ? 'hora' : 'horas'}';
  }
  final ontem = DateTime(agora.year, agora.month, agora.day - 1);
  final hora = DateFormat('HH:mm').format(quando);
  if (quando.year == ontem.year &&
      quando.month == ontem.month &&
      quando.day == ontem.day) {
    return 'ontem, $hora';
  }
  return '${DateFormat("d MMM", 'pt_PT').format(quando)}, $hora';
}

/// "Telemóveis da Rosa" (design: Dispositivos): quem recebe os alarmes e quando falou com o servidor. Os
/// números (alarmes agendados, permissões) são os que o próprio telemóvel reportou; sem eles mostra-se "—".
class DispositivosEcra extends StatefulWidget {
  const DispositivosEcra({
    super.key,
    required this.repositorio,
    required this.perfil,
    required this.aoLigarOutro,
    this.relogio = DateTime.now,
  });

  final Repositorio repositorio;
  final Perfil perfil;
  final VoidCallback aoLigarOutro;
  final DateTime Function() relogio;

  @override
  State<DispositivosEcra> createState() => _DispositivosEcraState();
}

class _DispositivosEcraState extends State<DispositivosEcra> {
  List<Dispositivo>? _lista;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _erro = null);
    try {
      final l = await widget.repositorio.dispositivos(widget.perfil.id);
      if (mounted) setState(() => _lista = l);
    } on ErroApi catch (e) {
      if (mounted) setState(() => _erro = e.codigo);
    } catch (_) {
      if (mounted) setState(() => _erro = 'falha_ao_carregar');
    }
  }

  Future<void> _desligar(Dispositivo d) async {
    final nome = widget.perfil.nome;
    final certo = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Desligar este telemóvel?'),
        content: Text(
          'Deixa de receber os alarmes e de ver as tomas de $nome. Para o voltar a ligar é preciso um código novo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Desligar'),
          ),
        ],
      ),
    );
    if (certo != true || !mounted) return;
    final mensagens = ScaffoldMessenger.maybeOf(context);
    try {
      await widget.repositorio.desligarDispositivo(widget.perfil.id, d.id);
      mensagens?.showSnackBar(
        const SnackBar(content: Text('Telemóvel desligado.')),
      );
      await _carregar();
    } on ErroApi catch (e) {
      mensagens?.showSnackBar(
        SnackBar(
          content: Text(
            e.codigo == 'sem_rede'
                ? 'Sem ligação à internet. Verifique a ligação e tente outra vez.'
                : 'Não foi possível desligar o telemóvel. Tente outra vez.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final nome = widget.perfil.nome;
    final lista = _lista;
    final blocos = <Widget>[
      CabecalhoFormulario(
        titulo: 'Telemóveis de $nome',
        subtitulo: 'Quem recebe os alarmes e quando falou com o servidor.',
        espaco: 16,
      ),
      if (_erro != null)
        Cartao(
          child: Text(
            _erro == 'sem_rede'
                ? 'Sem ligação à internet. Verifique a ligação e tente outra vez.'
                : 'Não foi possível ver os telemóveis. Tente outra vez.',
            style: Estilos.corpo(t),
          ),
        )
      else if (lista == null)
        const Center(child: CircularProgressIndicator())
      else if (lista.isEmpty)
        Cartao(
          child: Text(
            'Ainda não há nenhum telemóvel ligado a $nome.',
            style: Estilos.corpo(t),
          ),
        )
      else
        for (final d in lista)
          _CartaoDispositivo(
            dispositivo: d,
            agora: widget.relogio(),
            aoDesligar: () => _desligar(d),
          ),
      if (lista != null && lista.isNotEmpty)
        Text(
          'Se perder um telemóvel, desligue-o aqui e o acesso acaba de imediato.',
          style: TextStyle(
            fontSize: 15,
            height: 1.45,
            fontWeight: FontWeight.w500,
            color: t.texto2,
          ),
        ),
    ];
    return CorpoComRodape(
      margemInferior: 28,
      conteudo: escalonar(blocos, espaco: 16),
      rodape: [
        if (_erro != null)
          Botao(
            texto: 'Tentar outra vez',
            altura: 60,
            raio: 22,
            tamanhoTexto: 18,
            aoTocar: _carregar,
          )
        else
          Botao(
            texto: lista == null || lista.isEmpty
                ? 'Ligar o telemóvel de $nome'
                : 'Ligar outro telemóvel',
            altura: 60,
            raio: 22,
            tamanhoTexto: 18,
            aoTocar: widget.aoLigarOutro,
          ),
      ],
    );
  }
}

class _CartaoDispositivo extends StatelessWidget {
  const _CartaoDispositivo({
    required this.dispositivo,
    required this.agora,
    required this.aoDesligar,
  });
  final Dispositivo dispositivo;
  final DateTime agora;
  final VoidCallback aoDesligar;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final d = dispositivo;
    final p = d.permissoes;
    Widget linha(String rotulo, String valor, {Color? cor}) => Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              rotulo,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: t.texto2,
              ),
            ),
          ),
          Text(
            valor,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: cor ?? t.texto,
            ),
          ),
        ],
      ),
    );
    return Cartao(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: t.primariaSuave,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Icone(
                    Icones.telemovel,
                    tamanho: 24,
                    cor: t.sobrePrimariaSuave,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.nome ?? 'Telemóvel',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: t.texto,
                      ),
                    ),
                    Text(
                      'Ligado a ${DateFormat("d MMM", 'pt_PT').format(d.ligadoDesde)}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: t.texto2,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: t.okSuave,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Ligado',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: t.okTexto,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: t.linha),
          linha(
            'Última ligação',
            d.ultimaLigacao == null
                ? 'Ainda não'
                : haQuantoTempo(d.ultimaLigacao!, agora),
          ),
          linha(
            'Alarmes agendados',
            d.alarmesAgendados == null
                ? '—'
                : d.alarmesAgendados == 0
                ? 'Nenhum'
                : '${d.alarmesAgendados} ${d.alarmesAgendados == 1 ? 'próximo' : 'próximos'}',
          ),
          linha(
            'Permissões de alarme',
            p == null
                ? '—'
                : p.emFalta == 0
                ? 'Tudo pronto'
                : '${p.emFalta} em falta',
            cor: p != null && p.emFalta > 0 ? t.avisoTexto : null,
          ),
          const SizedBox(height: 14),
          Botao(
            texto: 'Desligar este telemóvel',
            altura: 52,
            raio: 20,
            fundo: t.mauSuave,
            cor: t.mauTexto,
            aoTocar: aoDesligar,
          ),
        ],
      ),
    );
  }
}

/// "Número da Rosa" (design: Telefone-Pessoa): o telemóvel da pessoa, para o botão "Ligar" da página Hoje.
class TelefonePessoaEcra extends StatefulWidget {
  const TelefonePessoaEcra({
    super.key,
    required this.perfil,
    required this.aoGuardar,
  });

  final Perfil perfil;

  /// Nulo apaga o número. Devolve o código de erro ou nulo se ficou guardado.
  final Future<String?> Function(String? telefone) aoGuardar;

  @override
  State<TelefonePessoaEcra> createState() => _TelefonePessoaEcraState();
}

class _TelefonePessoaEcraState extends State<TelefonePessoaEcra> {
  late final _telefone = TextEditingController(
    text: widget.perfil.telefone ?? '',
  );
  bool _aGuardar = false;
  String? _erro;

  @override
  void dispose() {
    _telefone.dispose();
    super.dispose();
  }

  Future<void> _guardar(String? valor) async {
    if (valor != null && !telefoneValido(valor)) {
      setState(
        () => _erro =
            'Escreva só os números do telemóvel, por exemplo 912 345 678.',
      );
      return;
    }
    setState(() {
      _aGuardar = true;
      _erro = null;
    });
    final erro = await widget.aoGuardar(valor?.trim());
    if (!mounted) return;
    if (erro == null) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _aGuardar = false;
      _erro = erro == 'sem_rede'
          ? 'Sem ligação à internet. Verifique a ligação e tente outra vez.'
          : 'Não foi possível guardar. Tente outra vez.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final nome = widget.perfil.nome;
    return CorpoComRodape(
      margemInferior: 28,
      conteudo: escalonar([
        CabecalhoFormulario(
          titulo: 'Número de $nome',
          subtitulo:
              'Para lhe ligar com um toque, a partir da página Hoje. Fica guardado cifrado e só quem cuida de $nome o vê.',
        ),
        CampoTexto(
          rotulo: 'Telemóvel de $nome',
          controlador: _telefone,
          dica: '912 345 678',
          teclado: TextInputType.phone,
          maxLength: 18,
          erro: _erro,
          ativo: !_aGuardar,
          aoSubmeter: () {
            if (!_aGuardar) _guardar(_telefone.text);
          },
        ),
        if (widget.perfil.telefone != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _aGuardar ? null : () => _guardar(null),
              icon: Icone(Icones.lixo, tamanho: 20, cor: t.mau),
              label: Text(
                'Apagar o número',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: t.mau,
                ),
              ),
            ),
          ),
      ], espaco: 18),
      rodape: [
        Botao(
          texto: _aGuardar ? 'A guardar…' : 'Guardar',
          altura: 60,
          raio: 22,
          tamanhoTexto: 18,
          aoTocar: _aGuardar ? null : () => _guardar(_telefone.text),
        ),
        const SizedBox(height: 6),
        AcaoTexto(
          texto: 'Cancelar',
          aoTocar: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }
}
