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

/// Tira a extensão do nome do ficheiro (".mp3", ".wav"...): ninguém precisa de a ver.
String _semExtensao(String nome) {
  final i = nome.lastIndexOf('.');
  return i <= 0 ? nome : nome.substring(0, i);
}

/// "Som do alarme": escolhe o som que toca quando chega a hora de uma toma, com pré-visualização.
/// Pode-se também importar vários sons do telemóvel (e renomeá-los): ficam só neste telemóvel,
/// nunca são enviados para a API.
class SomAlarmeEcra extends StatefulWidget {
  const SomAlarmeEcra({
    super.key,
    required this.atual,
    required this.importados,
    required this.aoGuardar,
  });

  final EscolhaSomAlarme atual;
  final List<SomImportado> importados;

  /// Devolve a escolha e a lista atualizada de importados (pode ter mais itens, ou nomes mudados).
  final void Function(EscolhaSomAlarme escolha, List<SomImportado> importados) aoGuardar;

  @override
  State<SomAlarmeEcra> createState() => _SomAlarmeEcraState();
}

class _SomAlarmeEcraState extends State<SomAlarmeEcra> {
  late EscolhaSomAlarme _escolha = widget.atual;
  late final _importados = List<SomImportado>.of(widget.importados);
  final _leitor = AudioPlayer();
  bool _aImportar = false;
  String? _erro;

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

  Future<void> _escolherImportado(SomImportado som) async {
    setState(() => _escolha = som);
    await _tocarBytes(som.bytes);
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
      final novo = SomImportado(nome: _semExtensao(ficheiro.name), bytes: bytes);
      setState(() {
        _importados.add(novo);
        _escolha = novo;
      });
      await _tocarBytes(bytes);
    } finally {
      if (mounted) setState(() => _aImportar = false);
    }
  }

  Future<void> _renomear(int indice) async {
    final atual = _importados[indice];
    final controlador = TextEditingController(text: atual.nome);
    final novoNome = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Nome do som'),
        content: TextField(controller: controlador, autofocus: true, maxLength: 40),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(c).pop(controlador.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    controlador.dispose();
    if (novoNome == null || novoNome.isEmpty || !mounted) return;
    final renomeado = SomImportado(nome: novoNome, bytes: atual.bytes);
    setState(() {
      final eraEscolhido = _escolha == atual;
      _importados[indice] = renomeado;
      if (eraEscolhido) _escolha = renomeado;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
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
        for (var i = 0; i < _importados.length; i++) ...[
          const SizedBox(height: 10),
          CartaoOpcao(
            titulo: _importados[i].nome,
            descricao: 'Importado do seu telemóvel.',
            ativo: _escolha == _importados[i],
            aoTocar: () => _escolherImportado(_importados[i]),
            fim: Semantics(
              button: true,
              label: 'Renomear ${_importados[i].nome}',
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _renomear(i),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.edit,
                    size: 20,
                    color: _escolha == _importados[i] ? t.sobrePrimariaSuave : t.texto2,
                  ),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 18),
        Botao(
          texto: _aImportar ? 'A abrir…' : 'Importar som do telemóvel',
          icone: Icons.upload_file,
          fundo: t.superficie2,
          cor: t.texto,
          altura: 52,
          raio: 18,
          tamanhoTexto: 15,
          aoTocar: _aImportar ? null : _importar,
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
            widget.aoGuardar(_escolha, _importados);
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
