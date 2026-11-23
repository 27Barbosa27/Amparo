import 'package:material_ui/material_ui.dart';

import '../../dominio/modelos.dart';
import '../../tema/tokens.dart';
import '../componentes/animacao.dart';
import '../componentes/base.dart';
import '../componentes/formulario.dart';

/// "Adicionar pessoa" (design: Adicionar-Pessoa). Basta um nome ou apelido: não se pedem dados sensíveis.
/// Acrescenta a declaração de autorização (o plano e o backend exigem-na; o desenho não a tinha).
class AdicionarPessoaEcra extends StatefulWidget {
  const AdicionarPessoaEcra({super.key, required this.aoCriar});

  /// Devolve o código de erro (`sem_rede`, `falha_ao_guardar`...) ou nulo se correu bem.
  final Future<String?> Function(NovaPessoa) aoCriar;

  @override
  State<AdicionarPessoaEcra> createState() => _AdicionarPessoaEcraState();
}

class _AdicionarPessoaEcraState extends State<AdicionarPessoaEcra> {
  final _nome = TextEditingController();
  AlarmesEm _alarmes = AlarmesEm.pessoa;
  TamanhoTexto _tamanho = TamanhoTexto.grande;
  bool _autorizacao = false;
  bool _aGuardar = false;
  String? _erroNome;
  String? _erroGeral;

  @override
  void dispose() {
    _nome.dispose();
    super.dispose();
  }

  static const _mensagens = {
    'sem_rede': 'Sem ligação à internet. Tente outra vez quando houver rede.',
    'sessao_expirada': 'A sessão terminou. Entre outra vez.',
  };

  Future<void> _criar() async {
    final nome = _nome.text.trim();
    if (nome.isEmpty) {
      setState(() => _erroNome = 'Escreva um nome ou apelido.');
      return;
    }
    setState(() {
      _aGuardar = true;
      _erroNome = null;
      _erroGeral = null;
    });
    final erro = await widget.aoCriar(
      NovaPessoa(nome: nome, alarmesEm: _alarmes, tamanhoTexto: _tamanho),
    );
    if (!mounted) return;
    setState(() {
      _aGuardar = false;
      _erroGeral = erro == null
          ? null
          : (_mensagens[erro] ??
                'Não foi possível criar o perfil. Tente outra vez.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final pode = _autorizacao && !_aGuardar;
    return CorpoComRodape(
      conteudo: [
        const CabecalhoFormulario(
          titulo: 'Adicionar pessoa',
          subtitulo: 'Basta um nome ou apelido. Não pedimos dados sensíveis.',
        ),
        const SizedBox(height: 18),
        CampoTexto(
          rotulo: 'Nome ou apelido',
          dica: 'Ex.: Avó Rosa',
          controlador: _nome,
          erro: _erroNome,
          maxLength: 40,
          aoMudar: (_) {
            if (_erroNome != null) setState(() => _erroNome = null);
          },
        ),
        const SizedBox(height: 18),
        Semantics(
          header: true,
          child: Text(
            'Quem recebe os alarmes?',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: t.texto,
            ),
          ),
        ),
        const SizedBox(height: 8),
        CartaoOpcao(
          titulo: 'A pessoa, no telemóvel dela',
          descricao: 'Liga-se com um código. Não precisa de conta.',
          ativo: _alarmes == AlarmesEm.pessoa,
          aoTocar: () => setState(() => _alarmes = AlarmesEm.pessoa),
        ),
        const SizedBox(height: 10),
        CartaoOpcao(
          titulo: 'Eu, no meu telemóvel',
          descricao: 'Recebo os alarmes e confirmo por ela',
          ativo: _alarmes == AlarmesEm.cuidador,
          aoTocar: () => setState(() => _alarmes = AlarmesEm.cuidador),
        ),
        const SizedBox(height: 18),
        GrelhaOpcoes<TamanhoTexto>(
          titulo: 'Tamanho do texto',
          opcoes: TamanhoTexto.values,
          texto: (o) => switch (o) {
            TamanhoTexto.normal => 'Normal',
            TamanhoTexto.grande => 'Grande',
            TamanhoTexto.muitoGrande => 'Muito grande',
          },
          valor: _tamanho,
          aoEscolher: (o) => setState(() => _tamanho = o),
        ),
        const SizedBox(height: 18),
        // O RGPD: dados de saúde exigem consentimento. A pessoa acompanhada não tem conta, por isso
        // quem a adiciona declara que tem a autorização dela (ou do representante legal).
        Semantics(
          container: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _autorizacao = !_autorizacao),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: _autorizacao,
                  onChanged: (v) => setState(() => _autorizacao = v ?? false),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'Tenho a autorização desta pessoa (ou do seu representante legal) para registar aqui os medicamentos dela.',
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                        color: t.texto,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_erroGeral != null) ...[
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
                _erroGeral!,
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
          texto: _aGuardar ? 'A criar…' : 'Criar perfil',
          icone: Icons.check,
          altura: 60,
          raio: 22,
          tamanhoTexto: 18,
          aoTocar: pode ? _criar : null,
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

/// "{Nome} já está no Amparo" (design: Sucesso-Pessoa), com texto neutro quanto ao género.
class SucessoPessoaEcra extends StatelessWidget {
  const SucessoPessoaEcra({
    super.key,
    required this.pessoa,
    required this.aoLigarTelemovel,
    required this.aoAdicionarReceita,
    required this.aoConcluir,
    this.alarmesNaPessoa = true,
  });

  final Perfil pessoa;
  final bool alarmesNaPessoa;
  final VoidCallback aoLigarTelemovel;
  final VoidCallback aoAdicionarReceita;
  final VoidCallback aoConcluir;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(
                child: AnimacaoLottie(
                  asset: 'assets/lottie/sucesso.json',
                  largura: 220,
                  altura: 240,
                  ultimoFotograma: 112,
                  descricao: 'Concluído com sucesso',
                ),
              ),
              const SizedBox(height: 12),
              Semantics(
                header: true,
                child: Text(
                  '${pessoa.nome} já está no Amparo',
                  textAlign: TextAlign.center,
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
                alarmesNaPessoa
                    ? 'O perfil está criado. Falta ligar o telemóvel de ${pessoa.nome}.'
                    : 'O perfil está criado. Os alarmes tocam no seu telemóvel.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                  color: t.texto2,
                ),
              ),
              const SizedBox(height: 18),
              Cartao(
                child: Row(
                  children: [
                    Avatar(inicial: pessoa.inicial, tamanho: 48),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pessoa.nome,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: t.texto,
                            ),
                          ),
                          Text(
                            alarmesNaPessoa
                                ? 'Os alarmes tocam no telemóvel dela'
                                : 'Os alarmes tocam no seu telemóvel',
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
              const SizedBox(height: 28),
              if (alarmesNaPessoa) ...[
                Botao(
                  texto: 'Ligar o telemóvel de ${pessoa.nome}',
                  altura: 60,
                  raio: 22,
                  tamanhoTexto: 18,
                  aoTocar: aoLigarTelemovel,
                ),
                const SizedBox(height: 8),
              ],
              Botao(
                texto: 'Adicionar uma receita primeiro',
                altura: 52,
                raio: 20,
                fundo: Colors.transparent,
                cor: t.texto,
                contorno: t.linha,
                aoTocar: aoAdicionarReceita,
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: aoConcluir,
                child: SizedBox(
                  height: 44,
                  child: Center(
                    child: Text(
                      'Concluir',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: t.texto,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
