import 'package:material_ui/material_ui.dart';

import 'package:intl/intl.dart';

import '../../dominio/modelos.dart';
import '../../estado/receitas_controlador.dart';
import '../../tema/tema.dart';
import '../../tema/tokens.dart';
import '../componentes/base.dart';

/// "Receitas" (design: Receitas): o aviso do que está a acabar, as receitas em dia com a barra do que resta,
/// e "Adicionar receita".
class ReceitasEcra extends StatelessWidget {
  const ReceitasEcra({
    super.key,
    required this.controlador,
    required this.aoAdicionar,
    this.aoPedirRenovacao,
  });
  final ReceitasControlador controlador;
  final VoidCallback aoAdicionar;
  final void Function(Receita)? aoPedirRenovacao;

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
        return SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
            children: [
              Semantics(
                header: true,
                child: Text('Receitas', style: Estilos.titulo(t)),
              ),
              Text(
                '$total ${total == 1 ? 'medicamento' : 'medicamentos'} de ${controlador.perfil.nome}',
                style: Estilos.subtitulo(t),
              ),
              const SizedBox(height: 20),
              if (controlador.aCarregar)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (controlador.erro != null)
                Cartao(
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
                if (urgente != null) ...[
                  _AvisoAAcabar(
                    receita: urgente,
                    validade: urgente.validaAte == null
                        ? null
                        : _data(urgente.validaAte!),
                    aoPedir: aoPedirRenovacao,
                  ),
                  const SizedBox(height: 24),
                ],
                if (emDia.isNotEmpty) ...[
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
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        for (var i = 0; i < emDia.length; i++)
                          _LinhaReceita(
                            receita: emDia[i],
                            primeira: i == 0,
                            validade: emDia[i].validaAte == null
                                ? null
                                : _data(emDia[i].validaAte!),
                          ),
                      ],
                    ),
                  ),
                ] else if (urgente == null)
                  Cartao(
                    child: Text(
                      'Ainda não há receitas.',
                      style: Estilos.corpo(t),
                    ),
                  ),
                const SizedBox(height: 16),
                Material(
                  color: t.superficie,
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: aoAdicionar,
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: t.sombra,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add, size: 24, color: t.texto),
                          const SizedBox(width: 10),
                          Text(
                            'Adicionar receita',
                            style: Estilos.corpo(t, peso: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
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
  });
  final Receita receita;
  final String? validade;
  final void Function(Receita)? aoPedir;

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
          borderRadius: BorderRadius.circular(28),
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
            Text(
              receita.medicamento,
              style: TextStyle(
                fontSize: 20,
                height: 1.2,
                fontWeight: FontWeight.w800,
                color: t.texto,
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
  });
  final Receita receita;
  final bool primeira;
  final String? validade;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final dias = receita.diasRestantes;
    final fracao = receita.fracaoRestante;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        border: primeira ? null : Border(top: BorderSide(color: t.linha)),
      ),
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
                    Selo(cor: t.ok, icone: Icons.check, corIcone: t.superficie),
                    const SizedBox(width: 6),
                    Text('$dias dias', style: Estilos.corpo(t, cor: t.okTexto)),
                  ],
                ),
            ],
          ),
          if (fracao != null) ...[
            const SizedBox(height: 10),
            ExcludeSemantics(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: fracao,
                  minHeight: 8,
                  backgroundColor: t.superficie2,
                  color: t.primaria,
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
        ],
      ),
    );
  }
}

/// Mais: ver como a pessoa vê, tema e terminar sessão.
class MaisEcra extends StatelessWidget {
  const MaisEcra({
    super.key,
    required this.aoVerComoAPessoaVe,
    required this.aoTerminarSessao,
    required this.escuro,
    required this.aoMudarTema,
  });
  final VoidCallback aoVerComoAPessoaVe;
  final VoidCallback aoTerminarSessao;
  final bool escuro;
  final ValueChanged<bool> aoMudarTema;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    Widget linha(
      IconData icone,
      String texto, {
      VoidCallback? aoTocar,
      Widget? fim,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: t.superficie,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: aoTocar,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: t.sombra,
            ),
            child: Row(
              children: [
                Icon(icone, color: t.primaria),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    texto,
                    style: Estilos.corpo(t, peso: FontWeight.w700),
                  ),
                ),
                ?fim,
              ],
            ),
          ),
        ),
      ),
    );

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
        children: [
          Semantics(
            header: true,
            child: Text('Mais', style: Estilos.titulo(t)),
          ),
          const SizedBox(height: 18),
          linha(
            Icons.visibility_outlined,
            'Ver como a pessoa vê',
            aoTocar: aoVerComoAPessoaVe,
          ),
          linha(
            Icons.dark_mode_outlined,
            'Tema escuro',
            fim: Switch(value: escuro, onChanged: aoMudarTema),
          ),
          linha(Icons.logout, 'Terminar sessão', aoTocar: aoTerminarSessao),
        ],
      ),
    );
  }
}
