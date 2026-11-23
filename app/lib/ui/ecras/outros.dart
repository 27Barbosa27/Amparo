import 'package:material_ui/material_ui.dart';

import '../../estado/hoje_controlador.dart';
import '../../tema/tema.dart';
import '../../tema/tokens.dart';
import '../componentes/base.dart';

/// Receitas: por agora lista os medicamentos do dia. O ecrã completo (adicionar receita, horários,
/// validade e stock) vem a seguir, quando a app falar com a API.
class ReceitasEcra extends StatelessWidget {
  const ReceitasEcra({super.key, required this.controlador});
  final HojeControlador controlador;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return ListenableBuilder(
      listenable: controlador,
      builder: (context, _) {
        final nomes = <String>{
          for (final x in controlador.tomas) x.medicamento,
        }.toList()..sort();
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
                'Medicamentos de ${controlador.perfil.nome}',
                style: Estilos.subtitulo(t),
              ),
              const SizedBox(height: 18),
              if (nomes.isEmpty)
                Cartao(
                  child: Text(
                    'Ainda não há receitas.',
                    style: Estilos.corpo(t),
                  ),
                ),
              for (final n in nomes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Cartao(
                    child: Text(
                      n,
                      style: Estilos.corpo(t, peso: FontWeight.w700),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
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
