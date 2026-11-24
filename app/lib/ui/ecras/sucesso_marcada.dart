import 'package:material_ui/material_ui.dart';

import '../../dominio/modelos.dart';
import '../../estado/hoje_controlador.dart';
import '../../tema/tokens.dart';
import '../componentes/animacao.dart';
import '../componentes/base.dart';
import '../componentes/icones.dart';
import 'cuidador_hoje.dart';

/// "Toma marcada" (design: Sucesso-Marcada). Mostra o que o servidor confirmou, diz que a pessoa vê a marcação
/// e oferece "Desfazer registo" (só dentro do minuto).
class SucessoMarcadaEcra extends StatelessWidget {
  const SucessoMarcadaEcra({
    super.key,
    required this.controlador,
    required this.tomaId,
    this.aoVoltar,
  });

  final HojeControlador controlador;
  final String tomaId;

  /// Por omissão, fecha este ecrã.
  final VoidCallback? aoVoltar;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return ListenableBuilder(
      listenable: controlador,
      builder: (context, _) {
        final toma = controlador.tomas.firstWhere((x) => x.id == tomaId);
        final hora = horaCurta(toma.tomadaEm ?? toma.agendada);
        final nome = controlador.perfil.nome;
        // O cuidador a tomar a sua própria medicação: não há mais ninguém a quem a marcação apareça.
        final proprio = eProprioCuidador(
          controlador.perfil,
          controlador.cuidador,
        );
        return SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                child: Column(
                  children: [
                    const AnimacaoLottie(
                      asset: 'assets/lottie/sucesso.json',
                      largura: 240,
                      altura: 240,
                      descricao: 'Concluído com sucesso',
                    ),
                    const SizedBox(height: 12),
                    Semantics(
                      header: true,
                      child: Text(
                        'Toma marcada',
                        style: TextStyle(
                          fontSize: 26,
                          height: 1.15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.65,
                          color: t.texto,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      proprio
                          ? '${toma.medicamento} registado às $hora.'
                          : '${toma.medicamento} registado às $hora, marcado por si.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                        color: t.texto2,
                      ),
                    ),
                    if (!proprio) ...[
                      const SizedBox(height: 18),
                      Cartao(
                        child: Row(
                          children: [
                            Avatar(
                              inicial: controlador.perfil.inicial,
                              tamanho: 48,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'A $nome vê esta marcação',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: t.texto,
                                    ),
                                  ),
                                  Text(
                                    'No ecrã dela, com o seu nome',
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
                      ),
                    ],
                    const Spacer(),
                    Botao(
                      texto: 'Voltar à página principal',
                      altura: 60,
                      raio: 22,
                      tamanhoTexto: 18,
                      aoTocar:
                          aoVoltar ?? () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(height: 8),
                    Botao(
                      texto: 'Desfazer registo',
                      iconeSvg: Icones.desfazer,
                      tamanhoIcone: 22,
                      altura: 52,
                      raio: 20,
                      fundo: Colors.transparent,
                      cor: t.texto,
                      contorno: t.linha,
                      aoTocar: () async {
                        final mensagens = ScaffoldMessenger.maybeOf(context);
                        final ok = await controlador.desfazer(toma);
                        if (ok) {
                          (aoVoltar ??
                              () => Navigator.of(context).maybePop())();
                        } else {
                          mensagens?.showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Já não é possível desfazer: passou mais de 1 minuto.',
                              ),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
