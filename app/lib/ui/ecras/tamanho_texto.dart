import 'package:material_ui/material_ui.dart';

import '../../dominio/modelos.dart';
import '../../tema/tokens.dart';
import '../componentes/base.dart';
import '../componentes/estilo.dart';
import '../componentes/formulario.dart';
import '../componentes/icones.dart';

/// "Tamanho do texto" (design: Tamanho-do-texto): Normal/Grande/Muito grande, com pré-visualização.
/// Serve tanto para a pessoa acompanhada ("Aplica-se ao modo simples de `nome`.") como para quem
/// só tem perfil próprio ("Aplica-se à sua app.").
class TamanhoTextoEcra extends StatefulWidget {
  const TamanhoTextoEcra({
    super.key,
    required this.perfil,
    required this.proprio,
    required this.aoGuardar,
  });

  final Perfil perfil;

  /// O perfil aberto é o do próprio cuidador (também toma medicação): muda a frase do subtítulo.
  final bool proprio;

  /// Devolve o código de erro ("sem_rede"...) ou nulo se guardou bem.
  final Future<String?> Function(TamanhoTexto) aoGuardar;

  @override
  State<TamanhoTextoEcra> createState() => _TamanhoTextoEcraState();
}

class _TamanhoTextoEcraState extends State<TamanhoTextoEcra> {
  late TamanhoTexto _escolha = widget.perfil.tamanhoTexto;
  bool _aGuardar = false;
  String? _erro;

  static String _texto(TamanhoTexto t) => switch (t) {
    TamanhoTexto.normal => 'Normal',
    TamanhoTexto.grande => 'Grande',
    TamanhoTexto.muitoGrande => 'Muito grande',
  };

  Future<void> _guardar() async {
    setState(() {
      _aGuardar = true;
      _erro = null;
    });
    final erro = await widget.aoGuardar(_escolha);
    if (!mounted) return;
    if (erro == null) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _aGuardar = false;
      _erro = erro == 'sem_rede'
          ? 'Sem ligação à internet. Tente outra vez quando houver rede.'
          : 'Não foi possível guardar. Tente outra vez.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return CorpoComRodape(
      conteudo: [
        CabecalhoFormulario(
          titulo: 'Tamanho do texto',
          subtitulo: widget.proprio
              ? 'Aplica-se à sua app.'
              : 'Aplica-se ao modo simples de ${widget.perfil.nome}.',
        ),
        const SizedBox(height: 18),
        GrelhaOpcoes<TamanhoTexto>(
          titulo: 'Tamanho',
          opcoes: TamanhoTexto.values,
          texto: _texto,
          valor: _escolha,
          aoEscolher: (o) => setState(() => _escolha = o),
        ),
        const SizedBox(height: 18),
        Cartao(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pré-visualização',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: t.texto2,
                ),
              ),
              const SizedBox(height: 14),
              // Só a pré-visualização cresce com a escolha: o resto do ecrã segue o tamanho do sistema.
              EscalarTexto(
                escala: _escolha.escala,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                              Icones.comprimido,
                              tamanho: 22,
                              cor: t.primaria,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Lisinopril',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: t.texto,
                                ),
                              ),
                              Text(
                                '09:00 · 1 comprimido',
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
                    const SizedBox(height: 16),
                    Botao(
                      texto: 'Tomei',
                      icone: Icons.check,
                      altura: 52,
                      raio: 18,
                      tamanhoTexto: 17,
                      aoTocar: null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_erro != null) ...[
          const SizedBox(height: 10),
          Semantics(
            liveRegion: true,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.mauSuave,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _erro!,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: t.mauTexto,
                ),
              ),
            ),
          ),
        ],
      ],
      rodape: [
        Botao(
          texto: _aGuardar ? 'A guardar…' : 'Guardar',
          icone: Icons.check,
          altura: 60,
          raio: 22,
          tamanhoTexto: 18,
          aoTocar: _aGuardar ? null : _guardar,
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: _aGuardar ? null : () => Navigator.of(context).maybePop(),
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
