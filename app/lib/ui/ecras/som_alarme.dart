import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../tema/tokens.dart';
import '../componentes/base.dart';
import '../componentes/formulario.dart';

/// Os sons já incluídos na app para o alarme de uma toma.
enum SomAlarme {
  sino('Sino', 'O som por omissão: claro e fácil de reconhecer.', 'sons/sino.wav'),
  campainha('Campainha', 'Um toque mais tradicional.', 'sons/campainha.wav'),
  despertador(
    'Despertador',
    'Mais intenso, para quem dorme profundamente.',
    'sons/despertador.wav',
  ),
  suave('Suave', 'Mais discreto, para ambientes partilhados.', 'sons/suave.wav');

  const SomAlarme(this.titulo, this.descricao, this.ficheiro);
  final String titulo;
  final String descricao;

  /// Caminho em `assets/`, para o tocar (pré-visualização) e, no futuro, no alarme real.
  final String ficheiro;
}

/// O som do alarme escolhido: um dos incluídos na app, ou um importado do telemóvel.
/// O importado nunca sai do telemóvel (não há aqui nenhum pedido à API).
sealed class EscolhaSomAlarme {
  const EscolhaSomAlarme();
  String get titulo;
}

class SomEmbutido extends EscolhaSomAlarme {
  const SomEmbutido(this.som);
  final SomAlarme som;
  @override
  String get titulo => som.titulo;

  @override
  bool operator ==(Object other) => other is SomEmbutido && other.som == som;
  @override
  int get hashCode => som.hashCode;
}

class SomImportado extends EscolhaSomAlarme {
  const SomImportado({required this.nome, required this.bytes});
  final String nome;
  final Uint8List bytes;
  @override
  String get titulo => nome;

  @override
  bool operator ==(Object other) =>
      other is SomImportado && other.nome == nome && other.bytes == bytes;
  @override
  int get hashCode => Object.hash(nome, bytes);
}

/// Limite de tamanho do som importado: o alarme repete-o em ciclo, não precisa de ser longo.
const _tamanhoMaximoBytes = 2 * 1024 * 1024; // 2 MB

/// "Som do alarme": escolhe o som que toca quando chega a hora de uma toma, com pré-visualização.
/// Pode-se também importar um som do telemóvel: fica só neste telemóvel, nunca é enviado para a API.
class SomAlarmeEcra extends StatefulWidget {
  const SomAlarmeEcra({super.key, required this.atual, required this.aoGuardar});

  final EscolhaSomAlarme atual;
  final ValueChanged<EscolhaSomAlarme> aoGuardar;

  @override
  State<SomAlarmeEcra> createState() => _SomAlarmeEcraState();
}

class _SomAlarmeEcraState extends State<SomAlarmeEcra> {
  late EscolhaSomAlarme _escolha = widget.atual;
  final _leitor = AudioPlayer();
  SomImportado? _importado;
  bool _aImportar = false;
  String? _erro;

  @override
  void initState() {
    super.initState();
    if (widget.atual case final SomImportado s) _importado = s;
  }

  @override
  void dispose() {
    _leitor.dispose();
    super.dispose();
  }

  Future<void> _tocarBytes(Uint8List bytes) async {
    await _leitor.stop();
    await _leitor.play(BytesSource(bytes));
  }

  Future<void> _escolherEmbutido(SomAlarme som) async {
    setState(() => _escolha = SomEmbutido(som));
    await _leitor.stop();
    await _leitor.play(AssetSource(som.ficheiro));
  }

  Future<void> _importar() async {
    setState(() {
      _erro = null;
      _aImportar = true;
    });
    try {
      final ficheiro = await FilePicker.pickFile(type: FileType.audio);
      if (ficheiro == null) return; // cancelou
      final bytes = await ficheiro.readAsBytes();
      if (bytes.length > _tamanhoMaximoBytes) {
        setState(() => _erro = 'Esse som é demasiado grande. Escolha um com menos de 2 MB.');
        return;
      }
      final novo = SomImportado(nome: ficheiro.name, bytes: bytes);
      setState(() {
        _importado = novo;
        _escolha = novo;
      });
      await _tocarBytes(bytes);
    } finally {
      if (mounted) setState(() => _aImportar = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final importado = _importado;
    return CorpoComRodape(
      conteudo: [
        const CabecalhoFormulario(
          titulo: 'Som do alarme',
          subtitulo: 'Toque numa opção para ouvir como fica.',
        ),
        const SizedBox(height: 18),
        for (final som in SomAlarme.values) ...[
          if (som != SomAlarme.values.first) const SizedBox(height: 10),
          CartaoOpcao(
            titulo: som.titulo,
            descricao: som.descricao,
            ativo: _escolha == SomEmbutido(som),
            aoTocar: () => _escolherEmbutido(som),
          ),
        ],
        if (importado != null) ...[
          const SizedBox(height: 10),
          CartaoOpcao(
            titulo: importado.nome,
            descricao: 'Importado do seu telemóvel.',
            ativo: _escolha == importado,
            aoTocar: () async {
              setState(() => _escolha = importado);
              await _tocarBytes(importado.bytes);
            },
          ),
        ],
        const SizedBox(height: 18),
        Botao(
          texto: _aImportar
              ? 'A abrir…'
              : (importado == null ? 'Importar som do telemóvel' : 'Importar outro som'),
          icone: Icons.upload_file,
          fundo: t.superficie2,
          cor: t.texto,
          altura: 52,
          raio: 18,
          tamanhoTexto: 15,
          aoTocar: _aImportar ? null : _importar,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Fica só neste telemóvel: nunca é enviado para fora.',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: t.texto2),
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
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: t.mauTexto),
              ),
            ),
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
