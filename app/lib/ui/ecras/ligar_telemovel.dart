import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../dados/api.dart';
import '../../dados/repositorio.dart';
import '../../dominio/modelos.dart';
import '../../tema/tokens.dart';
import '../componentes/base.dart';
import '../componentes/estilo.dart';
import '../componentes/formulario.dart';
import '../componentes/icones.dart';
import '../componentes/resultado.dart';

/// "Ligar o telemóvel" (cuidador): mostra o código de 6 dígitos, que a pessoa escreve no telemóvel dela.
/// A app vai perguntando ao servidor (a cada 3 s) se o código já foi usado, e conta o tempo que falta.
class LigarTelemovelEcra extends StatefulWidget {
  const LigarTelemovelEcra({
    super.key,
    required this.repositorio,
    required this.perfil,
    required this.aoConcluir,
    this.relogio = DateTime.now,
    this.intervalo = const Duration(seconds: 3),
  });

  final Repositorio repositorio;
  final Perfil perfil;
  final VoidCallback aoConcluir;
  final DateTime Function() relogio;
  final Duration intervalo;

  @override
  State<LigarTelemovelEcra> createState() => _LigarTelemovelEcraState();
}

enum _Estado { aGerar, aEspera, expirado, erro }

class _LigarTelemovelEcraState extends State<LigarTelemovelEcra> {
  _Estado _estado = _Estado.aGerar;
  CodigoLigacao? _codigo;
  String _erro = 'falha_ao_guardar';
  Timer? _consulta;
  Timer? _contagem;

  @override
  void initState() {
    super.initState();
    _gerar();
  }

  @override
  void dispose() {
    _consulta?.cancel();
    _contagem?.cancel();
    super.dispose();
  }

  Future<void> _gerar() async {
    _consulta?.cancel();
    _contagem?.cancel();
    if (_estado != _Estado.aGerar) setState(() => _estado = _Estado.aGerar);
    try {
      final c = await widget.repositorio.criarCodigoLigacao(widget.perfil.id);
      if (!mounted) return;
      setState(() {
        _codigo = c;
        _estado = _Estado.aEspera;
      });
      _consulta = Timer.periodic(widget.intervalo, (_) => _perguntar());
      _contagem = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        if (_resta <= Duration.zero) {
          _terminouTempo();
        } else {
          setState(() {});
        }
      });
    } on ErroApi catch (e) {
      _falhou(e.codigo);
    } catch (_) {
      _falhou('falha_ao_guardar');
    }
  }

  void _falhou(String codigo) {
    if (!mounted) return;
    setState(() {
      _erro = codigo;
      _estado = _Estado.erro;
    });
  }

  void _terminouTempo() {
    _consulta?.cancel();
    _contagem?.cancel();
    if (mounted) setState(() => _estado = _Estado.expirado);
  }

  Duration get _resta => _codigo!.expiraEm.difference(widget.relogio());

  Future<void> _perguntar() async {
    final c = _codigo;
    if (c == null || _estado != _Estado.aEspera) return;
    try {
      final e = await widget.repositorio.estadoCodigo(widget.perfil.id, c.id);
      if (!mounted || _estado != _Estado.aEspera) return;
      if (e == EstadoCodigo.ligado) {
        _consulta?.cancel();
        _contagem?.cancel();
        Navigator.of(context).pushReplacement(
          rotaPagina<void>(
            SucessoLigadoEcra(
              pessoa: widget.perfil,
              aoConcluir: widget.aoConcluir,
            ),
          ),
        );
      } else if (e == EstadoCodigo.expirado) {
        _terminouTempo();
      }
    } catch (_) {
      // uma consulta falhada não estraga nada: a seguinte volta a tentar
    }
  }

  String _tempo(Duration d) {
    final s = d.isNegative ? 0 : d.inSeconds;
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final nome = widget.perfil.nome;
    if (_estado == _Estado.erro) {
      return EcraResultado(
        topo: TopoResultado(
          titulo: 'Não foi possível criar o código',
          texto: _erro == 'sem_rede'
              ? 'Sem ligação à internet. Verifique a ligação e tente outra vez.'
              : 'Algo correu mal. Tente outra vez.',
          corTexto: t.mauTexto,
          animacao: Icone(Icones.semNuvem, tamanho: 72, cor: t.texto2),
        ),
        acoes: [
          Botao(
            texto: 'Tentar outra vez',
            altura: 60,
            raio: 22,
            tamanhoTexto: 18,
            aoTocar: _gerar,
          ),
          AcaoTexto(
            texto: 'Cancelar',
            aoTocar: () => Navigator.of(context).maybePop(),
          ),
        ],
      );
    }
    final expirado = _estado == _Estado.expirado;
    final codigo = _codigo?.codigo ?? '';
    final grupos = codigo.length == 6
        ? '${codigo.substring(0, 3)} ${codigo.substring(3)}'
        : '······';
    return CorpoComRodape(
      margemInferior: 28,
      conteudo: [
        ...escalonar([
          CabecalhoFormulario(
            titulo: 'Ligar o telemóvel de $nome',
            subtitulo:
                'No telemóvel de $nome, abra o Amparo, toque em "Tenho um código" e escreva estes números.',
          ),
          Semantics(
            liveRegion: true,
            label: expirado
                ? 'O código expirou'
                : 'Código ${codigo.split('').join(' ')}',
            child: Cartao(
              raio: 28,
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 18),
              child: ExcludeSemantics(
                child: Column(
                  children: [
                    Text(
                      expirado ? '------' : grupos,
                      style: TextStyle(
                        fontSize: 48,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 4,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: expirado ? t.texto2 : t.texto,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      switch (_estado) {
                        _Estado.aGerar => 'A criar o código…',
                        _Estado.expirado => 'O código expirou',
                        _ => 'Vale mais ${_tempo(_resta)} · uso único',
                      },
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: expirado ? t.mauTexto : t.texto2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_estado == _Estado.aEspera)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(width: 10),
                Text(
                  'À espera de $nome…',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: t.texto2,
                  ),
                ),
              ],
            ),
        ], espaco: 18),
      ],
      rodape: [
        if (expirado)
          Botao(
            texto: 'Gerar outro código',
            altura: 60,
            raio: 22,
            tamanhoTexto: 18,
            aoTocar: _gerar,
          )
        else
          Botao(
            texto: 'Gerar outro código',
            altura: 52,
            raio: 20,
            fundo: Colors.transparent,
            cor: t.texto,
            contorno: t.linha,
            aoTocar: _estado == _Estado.aGerar ? null : _gerar,
          ),
        const SizedBox(height: 6),
        AcaoTexto(
          texto: 'Fazer isto mais tarde',
          aoTocar: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }
}

/// "{Nome} está ligado" (cuidador): o código foi usado e o telemóvel da pessoa já está ligado.
class SucessoLigadoEcra extends StatelessWidget {
  const SucessoLigadoEcra({
    super.key,
    required this.pessoa,
    required this.aoConcluir,
  });
  final Perfil pessoa;
  final VoidCallback aoConcluir;

  @override
  Widget build(BuildContext context) {
    return EcraResultado(
      topo: TopoResultado(
        titulo: 'O telemóvel de ${pessoa.nome} está ligado',
        texto: 'A partir de agora, os alarmes tocam lá e vê aqui quando as tomas são feitas.',
      ),
      acoes: [
        Botao(
          texto: 'Concluir',
          altura: 60,
          raio: 22,
          tamanhoTexto: 18,
          aoTocar: aoConcluir,
        ),
      ],
    );
  }
}

/// "Tenho um código" (telemóvel da pessoa): escreve os 6 dígitos que o cuidador mostra.
class CodigoEcra extends StatefulWidget {
  const CodigoEcra({super.key, required this.aoLigar});

  /// Devolve o código de erro (`codigo_invalido`, `demasiadas_tentativas`, `sem_rede`...) ou nulo se ligou.
  final Future<String?> Function(String codigo) aoLigar;

  @override
  State<CodigoEcra> createState() => _CodigoEcraState();
}

class _CodigoEcraState extends State<CodigoEcra> {
  final _codigo = TextEditingController();
  bool _aLigar = false;
  String? _erro;

  static const _mensagens = {
    'codigo_invalido': 'Código errado, expirado ou já usado. Peça um código novo a quem cuida de si.',
    'demasiadas_tentativas':
        'Demasiadas tentativas. Espere uns minutos e tente outra vez.',
    'sem_rede':
        'Sem ligação à internet. Verifique a ligação e tente outra vez.',
  };

  @override
  void dispose() {
    _codigo.dispose();
    super.dispose();
  }

  Future<void> _ligar() async {
    final c = _codigo.text.replaceAll(RegExp(r'\s'), '');
    if (!RegExp(r'^\d{6}$').hasMatch(c)) {
      setState(() => _erro = 'O código tem 6 números.');
      return;
    }
    setState(() {
      _aLigar = true;
      _erro = null;
    });
    final erro = await widget.aoLigar(c);
    if (!mounted) return;
    setState(() {
      _aLigar = false;
      _erro = erro == null
          ? null
          : (_mensagens[erro] ?? 'Não foi possível ligar. Tente outra vez.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return CorpoComRodape(
      margemInferior: 28,
      conteudo: [
        ...escalonar([
          const CabecalhoFormulario(
            titulo: 'Tenho um código',
            subtitulo: 'Escreva os 6 números que aparecem no telemóvel de quem cuida de si.',
          ),
          Semantics(
            label: 'Código de 6 números',
            child: TextField(
              controller: _codigo,
              autofocus: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 7,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
              ],
              onChanged: (_) {
                if (_erro != null) setState(() => _erro = null);
              },
              onSubmitted: (_) => _aLigar ? null : _ligar(),
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w800,
                letterSpacing: 6,
                color: t.texto,
              ),
              decoration: InputDecoration(
                counterText: '',
                hintText: '000 000',
                hintStyle: TextStyle(
                  color: t.texto2.withValues(alpha: .5),
                  fontWeight: FontWeight.w800,
                ),
                filled: true,
                fillColor: t.superficie,
                contentPadding: const EdgeInsets.symmetric(vertical: 22),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(
                    color: _erro == null ? t.linha : t.mau,
                    width: 2,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(
                    color: _erro == null ? t.linha : t.mau,
                    width: 2,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(
                    color: _erro == null ? t.primaria : t.mau,
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
          if (_erro != null)
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
        ], espaco: 18),
      ],
      rodape: [
        Botao(
          texto: _aLigar ? 'A ligar…' : 'Ligar este telemóvel',
          altura: 60,
          raio: 22,
          tamanhoTexto: 18,
          aoTocar: _aLigar ? null : _ligar,
        ),
      ],
    );
  }
}

/// "Ligado" (telemóvel da pessoa): primeira vez que vê o seu perfil.
class SucessoPessoaLigadoEcra extends StatelessWidget {
  const SucessoPessoaLigadoEcra({
    super.key,
    required this.pessoa,
    required this.aoContinuar,
  });
  final Perfil pessoa;
  final VoidCallback aoContinuar;

  @override
  Widget build(BuildContext context) {
    return EcraResultado(
      topo: TopoResultado(
        titulo: 'Este telemóvel está ligado',
        texto:
            'Aqui vai ver as tomas de ${pessoa.nome} e marcar quando as fizer.',
      ),
      acoes: [
        Botao(
          texto: 'Continuar',
          altura: 60,
          raio: 22,
          tamanhoTexto: 18,
          aoTocar: aoContinuar,
        ),
      ],
    );
  }
}
