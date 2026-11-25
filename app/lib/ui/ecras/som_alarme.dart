import 'package:material_ui/material_ui.dart';

import '../../tema/tokens.dart';
import '../componentes/base.dart';
import '../componentes/formulario.dart';

/// Os sons disponíveis para o alarme de uma toma.
enum SomAlarme {
  sino('Sino', 'O som por omissão: claro e fácil de reconhecer.'),
  campainha('Campainha', 'Um toque mais tradicional.'),
  despertador('Despertador', 'Mais intenso, para quem dorme profundamente.'),
  suave('Suave', 'Mais discreto, para ambientes partilhados.');

  const SomAlarme(this.titulo, this.descricao);
  final String titulo;
  final String descricao;
}

/// "Som do alarme": escolhe o som que toca quando chega a hora de uma toma.
class SomAlarmeEcra extends StatefulWidget {
  const SomAlarmeEcra({super.key, required this.atual, required this.aoGuardar});

  final SomAlarme atual;
  final ValueChanged<SomAlarme> aoGuardar;

  @override
  State<SomAlarmeEcra> createState() => _SomAlarmeEcraState();
}

class _SomAlarmeEcraState extends State<SomAlarmeEcra> {
  late SomAlarme _escolha = widget.atual;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return CorpoComRodape(
      conteudo: [
        const CabecalhoFormulario(
          titulo: 'Som do alarme',
          subtitulo: 'O som que toca quando chega a hora de uma toma.',
        ),
        const SizedBox(height: 18),
        for (final som in SomAlarme.values) ...[
          if (som != SomAlarme.values.first) const SizedBox(height: 10),
          CartaoOpcao(
            titulo: som.titulo,
            descricao: som.descricao,
            ativo: _escolha == som,
            aoTocar: () => setState(() => _escolha = som),
          ),
        ],
      ],
      rodape: [
        Botao(
          texto: 'Guardar',
          icone: Icons.check,
          altura: 60,
          raio: 22,
          tamanhoTexto: 18,
          aoTocar: () {
            widget.aoGuardar(_escolha);
            Navigator.of(context).maybePop();
          },
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: SizedBox(
            height: 48,
            child: Center(
              child: Text(
                'Cancelar',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: t.texto,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
