import 'package:material_ui/material_ui.dart';

import 'package:intl/intl.dart';

import '../../dominio/modelos.dart';
import '../../estado/receitas_controlador.dart';
import '../../tema/tema.dart';
import '../../tema/tokens.dart';
import '../componentes/base.dart';
import '../componentes/estilo.dart';
import '../componentes/icones.dart';
import 'cuidador_hoje.dart' show itemQueSobe;
import 'som_alarme.dart' show EscolhaSomAlarme, SomAlarme, SomEmbutido;

/// "Receitas" (design: Receitas): o aviso do que está a acabar, as receitas em dia com a barra do que resta,
/// e "Adicionar receita".
class ReceitasEcra extends StatelessWidget {
  const ReceitasEcra({
    super.key,
    required this.controlador,
    required this.aoAdicionar,
    this.aoPedirRenovacao,
    this.aoAbrirReceita,
  });
  final ReceitasControlador controlador;
  final VoidCallback aoAdicionar;
  final void Function(Receita)? aoPedirRenovacao;

  /// Tocar numa receita: editar ou apagar.
  final void Function(Receita)? aoAbrirReceita;

  String _data(DateTime d) => DateFormat('dd/MM/yyyy').format(d);

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return ListenableBuilder(
      listenable: controlador,
      builder: (context, _) {
        final urgente = controlador.aAcabar;
        final emDia = controlador.emDia;
        final total = controlador.receitas.where((r) => r.ativa).length;
        // Como no design, cada bloco da página entra a subir, 0,08 s depois do anterior.
        final blocos = <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Receitas',
                  style: Estilos.titulo(t)
                      .copyWith(fontSize: 20, letterSpacing: -0.5),
                ),
              ),
              Text(
                '$total ${total == 1 ? 'medicamento' : 'medicamentos'} de ${controlador.perfil.nome}',
                style: Estilos.subtitulo(t),
              ),
            ],
          ),
          if (controlador.aCarregar)
            const Padding(
              padding: EdgeInsets.only(top: 20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (controlador.erro != null)
            Cartao(
              raio: 5,
              cor: t.mauSuave,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    controlador.erro == 'sem_rede'
                        ? 'Sem ligação. Verifique a internet e tente outra vez.'
                        : 'Não foi possível carregar as receitas.',
                    style: Estilos.corpo(
                      t,
                      peso: FontWeight.w800,
                      cor: t.mauTexto,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Botao(
                    texto: 'Tentar outra vez',
                    icone: Icons.refresh,
                    aoTocar: controlador.carregar,
                  ),
                ],
              ),
            )
          else ...[
            if (urgente != null)
              _AvisoAAcabar(
                receita: urgente,
                validade: urgente.validaAte == null
                    ? null
                    : _data(urgente.validaAte!),
                aoPedir: aoPedirRenovacao,
                aoAbrir: aoAbrirReceita,
              ),
            if (emDia.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      'Em dia',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: t.texto,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Cartao(
                    raio: 5,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        for (var i = 0; i < emDia.length; i++)
                          itemQueSobe(
                            i,
                            _LinhaReceita(
                              receita: emDia[i],
                              primeira: i == 0,
                              validade: emDia[i].validaAte == null
                                  ? null
                                  : _data(emDia[i].validaAte!),
                              aoAbrir: aoAbrirReceita,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              )
            else if (urgente == null)
              Cartao(
                raio: 5,
                child: Text('Ainda não há receitas.', style: Estilos.corpo(t)),
              ),
            // Cheio, com a cor principal: sobre o fundo escuro um botão da cor da superfície quase desaparecia.
            Botao(
              texto: 'Adicionar receita',
              icone: Icons.add,
              altura: 52,
              raio: 18,
              aoTocar: aoAdicionar,
            ),
          ],
        ];
        return SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 108),
            children: escalonar(blocos, espaco: 20),
          ),
        );
      },
    );
  }
}

class _AvisoAAcabar extends StatelessWidget {
  const _AvisoAAcabar({
    required this.receita,
    required this.validade,
    required this.aoPedir,
    this.aoAbrir,
  });
  final Receita receita;
  final String? validade;
  final void Function(Receita)? aoPedir;
  final void Function(Receita)? aoAbrir;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final dias = receita.diasRestantes!;
    final quando = dias == 0
        ? 'Acaba hoje'
        : 'Acaba em $dias ${dias == 1 ? 'dia' : 'dias'}';
    final restam = receita.unidadesRestantes;
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: t.avisoSuave,
          borderRadius: BorderRadius.circular(5),
          boxShadow: t.sombra,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Selo(
                  cor: t.aviso,
                  icone: Icons.priority_high,
                  corIcone: Tokens.sobreAviso,
                  tamanho: 28,
                ),
                const SizedBox(width: 8),
                Text(
                  quando,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: t.avisoTexto,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            InkWell(
              onTap: aoAbrir == null ? null : () => aoAbrir!(receita),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      receita.medicamento,
                      style: TextStyle(
                        fontSize: 20,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        color: t.texto,
                      ),
                    ),
                  ),
                  if (aoAbrir != null)
                    Icone(Icones.maisOpcoes, tamanho: 24, cor: t.avisoTexto),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              [
                if (restam != null)
                  'Restam $restam ${restam == 1 ? 'unidade' : 'unidades'}.',
                if (validade != null) 'Receita válida até $validade.',
              ].join(' '),
              style: TextStyle(
                fontSize: 15,
                height: 1.4,
                fontWeight: FontWeight.w500,
                color: t.avisoTexto,
              ),
            ),
            const SizedBox(height: 16),
            Botao(
              texto: 'Pedir renovação ao médico',
              altura: 52,
              raio: 18,
              aoTocar: aoPedir == null ? null : () => aoPedir!(receita),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinhaReceita extends StatelessWidget {
  const _LinhaReceita({
    required this.receita,
    required this.primeira,
    required this.validade,
    this.aoAbrir,
  });
  final Receita receita;
  final bool primeira;
  final String? validade;
  final void Function(Receita)? aoAbrir;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final dias = receita.diasRestantes;
    final fracao = receita.fracaoRestante;
    return Container(
      decoration: BoxDecoration(
        border: primeira ? null : Border(top: BorderSide(color: t.linha)),
      ),
      child: InkWell(
        onTap: aoAbrir == null ? null : () => aoAbrir!(receita),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      receita.medicamento,
                      style: Estilos.corpo(t, peso: FontWeight.w700),
                    ),
                  ),
                  if (dias != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Selo(
                          cor: t.ok,
                          icone: Icons.check,
                          corIcone: t.superficie,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$dias ${dias == 1 ? 'dia' : 'dias'}',
                          style: Estilos.corpo(t, cor: t.okTexto),
                        ),
                      ],
                    ),
                  if (aoAbrir != null) ...[
                    const SizedBox(width: 10),
                    Icone(Icones.maisOpcoes, tamanho: 24, cor: t.texto2),
                  ],
                ],
              ),
              if (fracao != null) ...[
                const SizedBox(height: 10),
                ExcludeSemantics(
                  // `mGrow`: a barra enche em 0,8 s, depois de 0,4 s.
                  child: AnimarComAtraso(
                    atraso: const Duration(milliseconds: 400),
                    duracao: const Duration(milliseconds: 800),
                    builder: (context, progresso) => ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: fracao * progresso,
                        minHeight: 8,
                        backgroundColor: t.superficie2,
                        color: t.primaria,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                validade != null
                    ? 'Válida até $validade'
                    : '${receita.dose} · ${receita.horario}',
                style: Estilos.corpo(t, peso: FontWeight.w500, cor: t.texto2),
              ),
              if (receita.naoChega) ...[
                const SizedBox(height: 8),
                Text(
                  'Só chega para $dias ${dias == 1 ? 'dia' : 'dias'}: '
                  'faltam cerca de ${receita.emFalta} '
                  '${receita.emFalta == 1 ? 'unidade' : 'unidades'} até ao fim da receita.',
                  style: Estilos.corpo(
                    t,
                    peso: FontWeight.w700,
                    cor: t.avisoTexto,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Mais (design: Mais): o cartão da pessoa, o histórico e as definições.
/// Só mostra valores que existem de verdade (nada de dados inventados); as linhas cujo ecrã ainda não
/// existe avisam que ainda não estão disponíveis.
class MaisEcra extends StatelessWidget {
  const MaisEcra({
    super.key,
    required this.perfil,
    required this.aoVerComoAPessoaVe,
    required this.aoTerminarSessao,
    required this.escuro,
    required this.aoMudarTema,
    this.cuidador,
    this.adesao,
    this.aoMudarDePerfil,
    this.proprio = false,
    this.aoTelemoveisLigados,
    this.aoHistorico,
    this.aoTamanhoTexto,
    this.somAlarme = const SomEmbutido(SomAlarme.sino),
    this.aoSomAlarme,
    this.aoAlertasCuidador,
    this.aoConta,
    this.aoAlarmesFiaveis,
    this.alarmesEmFalta,
    this.aoNumeroPessoa,
  });

  /// "Alertas ao cuidador": abre o ecrã de escolha de quando é avisado.
  final VoidCallback? aoAlertasCuidador;

  /// Tocar na linha da conta: "A sua conta" (exportar e apagar).
  final VoidCallback? aoConta;

  /// "Alarmes fiáveis": as permissões dos alarmes neste telemóvel.
  final VoidCallback? aoAlarmesFiaveis;

  /// Quantas permissões faltam ("2 em falta"). Nulo quando não se sabe (ou não há alarmes aqui).
  final int? alarmesEmFalta;

  /// "Número da Rosa": o telemóvel da pessoa, para o botão "Ligar". Só quando acompanha outra pessoa.
  final VoidCallback? aoNumeroPessoa;

  /// "Histórico de tomas": abre o ecrã do histórico.
  final VoidCallback? aoHistorico;

  /// "Tamanho do texto": abre o ecrã de escolha (Normal/Grande/Muito grande).
  final VoidCallback? aoTamanhoTexto;

  /// O som do alarme escolhido (mostra-se como valor da linha "Som do alarme").
  final EscolhaSomAlarme somAlarme;

  /// "Som do alarme": abre o ecrã de escolha.
  final VoidCallback? aoSomAlarme;

  /// "Telemóveis ligados": os telemóveis da pessoa, com o estado de cada um.
  final VoidCallback? aoTelemoveisLigados;
  final Perfil perfil;
  final VoidCallback aoVerComoAPessoaVe;
  final VoidCallback aoTerminarSessao;
  final bool escuro;
  final ValueChanged<bool> aoMudarTema;

  /// Quem usa a app (o cuidador que entrou).
  final String? cuidador;

  /// Percentagem de adesão dos últimos 7 dias, se já houver histórico.
  final int? adesao;
  final VoidCallback? aoMudarDePerfil;

  /// O perfil aberto é o do próprio cuidador (também toma medicação).
  final bool proprio;

  static String _tamanho(TamanhoTexto t) => switch (t) {
    TamanhoTexto.normal => 'Normal',
    TamanhoTexto.grande => 'Grande',
    TamanhoTexto.muitoGrande => 'Muito grande',
  };

  void _emBreve(BuildContext context, String o) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text('$o ainda não está disponível.')));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;

    Widget linha(
      IconeDados icone,
      String texto, {
      VoidCallback? aoTocar,
      Widget? fim,
      String? valor,
      bool primeira = false,
    }) => Container(
      decoration: BoxDecoration(
        border: primeira ? null : Border(top: BorderSide(color: t.linha)),
      ),
      child: Pressionavel(
        child: InkWell(
          onTap: aoTocar,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Row(
              children: [
                Icone(icone, tamanho: 24, cor: t.texto),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    texto,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: t.texto,
                    ),
                  ),
                ),
                if (valor != null)
                  Text(
                    valor,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: t.texto2,
                    ),
                  ),
                ?fim,
              ],
            ),
          ),
        ),
      ),
    );

    final filhos = <Widget>[
      Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Semantics(
          header: true,
          child: Text(
            'Configurações',
            style: TextStyle(
              fontSize: 20,
              height: 1.15,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: t.texto,
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Cartao(
          raio: 28,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (cuidador != null) ...[
                Semantics(
                  button: aoConta != null,
                  label: '$cuidador, a sua conta',
                  excludeSemantics: true,
                  child: InkWell(
                    onTap: aoConta,
                    borderRadius: BorderRadius.circular(16),
                    child: Row(
                      children: [
                        Avatar(
                          inicial: cuidador!.substring(0, 1).toUpperCase(),
                          tamanho: 40,
                          coral: true,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                cuidador!,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: t.texto,
                                ),
                              ),
                              Text(
                                'A sua conta · Cuidador',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: t.texto2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (aoConta != null)
                          Icone(Icones.setaDireita, tamanho: 24, cor: t.texto),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Container(height: 1, color: t.linha),
                const SizedBox(height: 14),
              ],
              Text(
                proprio ? 'A minha medicação' : 'A cuidar de',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: t.texto2,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Avatar(inicial: perfil.inicial, tamanho: 52),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          perfil.nome,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: t.texto,
                          ),
                        ),
                        Text(
                          proprio ? 'A sua medicação' : 'Pessoa acompanhada',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: t.texto2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (!proprio) ...[
                const SizedBox(height: 14),
                Botao(
                  texto: 'Ver como ${perfil.nome} vê',
                  altura: 48,
                  raio: 18,
                  tamanhoTexto: 15,
                  aoTocar: aoVerComoAPessoaVe,
                ),
              ],
            ],
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: t.superficie,
            borderRadius: BorderRadius.circular(24),
            boxShadow: t.sombra,
          ),
          child: Pressionavel(
            child: InkWell(
              onTap:
                  aoHistorico ??
                  () => _emBreve(context, 'O histórico de tomas'),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 60),
                child: Row(
                  children: [
                    Icone(Icones.historico, tamanho: 24, cor: t.texto),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Histórico de tomas',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: t.texto,
                        ),
                      ),
                    ),
                    if (adesao != null) ...[
                      Text(
                        '$adesao%',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: t.texto2,
                        ),
                      ),
                      const SizedBox(width: 14),
                    ],
                    Icone(Icones.setaDireita, tamanho: 24, cor: t.texto),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: t.superficie,
          borderRadius: BorderRadius.circular(24),
          boxShadow: t.sombra,
        ),
        child: Column(
          children: [
            linha(
              Icones.textoAa,
              'Tamanho do texto',
              valor: _tamanho(perfil.tamanhoTexto),
              aoTocar:
                  aoTamanhoTexto ??
                  () => _emBreve(context, 'O tamanho do texto'),
              primeira: true,
            ),
            linha(
              Icones.sino,
              'Som do alarme',
              valor: somAlarme.titulo,
              aoTocar:
                  aoSomAlarme ?? () => _emBreve(context, 'O som do alarme'),
            ),
            linha(
              Icones.escudo,
              'Alertas ao cuidador',
              aoTocar:
                  aoAlertasCuidador ??
                  () => _emBreve(context, 'Os alertas ao cuidador'),
            ),
            linha(
              Icones.alertaCirculo,
              'Alarmes fiáveis',
              aoTocar:
                  aoAlarmesFiaveis ??
                  () => _emBreve(context, 'Os alarmes fiáveis'),
              fim: alarmesEmFalta == null || alarmesEmFalta == 0
                  ? null
                  : Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: t.avisoSuave,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$alarmesEmFalta em falta',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: t.avisoTexto,
                        ),
                      ),
                    ),
            ),
            linha(
              Icones.telemovel,
              'Telemóveis ligados',
              aoTocar:
                  aoTelemoveisLigados ??
                  () => _emBreve(context, 'Os telemóveis ligados'),
            ),
            if (!proprio && aoNumeroPessoa != null)
              linha(
                Icones.telefone,
                'Número de ${perfil.nome}',
                valor: perfil.telefone ?? 'Adicionar',
                aoTocar: aoNumeroPessoa,
              ),
            linha(
              Icones.lua,
              'Modo escuro',
              valor: escuro ? 'Ligado' : 'Desligado',
              aoTocar: () => aoMudarTema(!escuro),
              fim: Padding(
                padding: const EdgeInsets.only(left: 14),
                child: Interruptor(ligado: escuro),
              ),
            ),
            linha(
              Icones.cadeado,
              'Biometria e PIN',
              aoTocar: () => _emBreve(context, 'A biometria e o PIN'),
            ),
            linha(
              Icones.utilizador,
              'Mudar de pessoa',
              aoTocar: aoMudarDePerfil,
            ),
            // Não está no design, mas sem isto não há como terminar a sessão.
            linha(Icones.sair, 'Terminar sessão', aoTocar: aoTerminarSessao),
          ],
        ),
      ),
    ];

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 108),
        children: [
          // Cada bloco entra a subir, 0,08 s depois do anterior, como no design.
          ...escalonar(filhos),
        ],
      ),
    );
  }
}
