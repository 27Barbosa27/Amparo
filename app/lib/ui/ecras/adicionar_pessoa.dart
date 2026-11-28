import 'package:material_ui/material_ui.dart';

import '../../dominio/modelos.dart';
import '../../tema/tokens.dart';
import '../componentes/base.dart';
import '../componentes/resultado.dart';
import '../componentes/formulario.dart';

/// "Adicionar pessoa" (design: Adicionar-Pessoa). Basta um nome ou apelido: não se pedem dados sensíveis.
/// Acrescenta a declaração de autorização (o plano e o backend exigem-na; o desenho não a tinha).
class AdicionarPessoaEcra extends StatefulWidget {
  const AdicionarPessoaEcra({
    super.key,
    required this.aoCriar,
    this.nomeCuidador,
  });

  /// O nome de quem usa a conta: o cuidador também pode tomar medicação ("Para mim").
  final String? nomeCuidador;

  /// Devolve o código de erro (`sem_rede`, `falha_ao_guardar`...) ou nulo se correu bem.
  final Future<String?> Function(NovaPessoa) aoCriar;

  @override
  State<AdicionarPessoaEcra> createState() => _AdicionarPessoaEcraState();
}

class _AdicionarPessoaEcraState extends State<AdicionarPessoaEcra> {
  final _nome = TextEditingController();
  final _telefone = TextEditingController();
  String? _erroTelefone;
  AlarmesEm _alarmes = AlarmesEm.pessoa;
  TamanhoTexto _tamanho = TamanhoTexto.grande;
  bool _autorizacao = false;
  bool _eu = false;
  bool _aGuardar = false;
  String? _erroNome;
  String? _erroGeral;

  @override
  void dispose() {
    _nome.dispose();
    _telefone.dispose();
    super.dispose();
  }

  static const _mensagens = {
    'sem_rede': 'Sem ligação à internet. Tente outra vez quando houver rede.',
    'sessao_expirada': 'A sessão terminou. Entre outra vez.',
  };

  Future<void> _criar() async {
    final nome = _eu ? widget.nomeCuidador!.trim() : _nome.text.trim();
    if (nome.isEmpty) {
      setState(() => _erroNome = 'Escreva um nome ou apelido.');
      return;
    }
    final telefone = _eu ? '' : _telefone.text.trim();
    if (telefone.isNotEmpty && !telefoneValido(telefone)) {
      setState(
        () => _erroTelefone =
            'Escreva só os números do telemóvel, por exemplo 912 345 678.',
      );
      return;
    }
    setState(() {
      _aGuardar = true;
      _erroNome = null;
      _erroTelefone = null;
      _erroGeral = null;
    });
    final erro = await widget.aoCriar(
      NovaPessoa(
        nome: nome,
        alarmesEm: _eu ? AlarmesEm.cuidador : _alarmes,
        tamanhoTexto: _tamanho,
        telefone: telefone.isEmpty ? null : telefone,
      ),
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
    final pode = (_eu || _autorizacao) && !_aGuardar;
    return CorpoComRodape(
      margemInferior: 28,
      conteudo: [
        const CabecalhoFormulario(
          titulo: 'Adicionar pessoa',
          subtitulo: 'Basta um nome ou apelido. Não pedimos dados sensíveis.',
        ),
        const SizedBox(height: 18),
        if (widget.nomeCuidador != null &&
            widget.nomeCuidador!.trim().isNotEmpty) ...[
          Semantics(
            header: true,
            child: Text(
              'Quem toma os medicamentos?',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: t.texto,
              ),
            ),
          ),
          const SizedBox(height: 8),
          CartaoOpcao(
            titulo: 'Outra pessoa',
            descricao: 'Alguém de quem cuido',
            ativo: !_eu,
            aoTocar: () => setState(() => _eu = false),
          ),
          const SizedBox(height: 10),
          CartaoOpcao(
            titulo: 'Eu',
            descricao: 'Os meus medicamentos, no meu telemóvel',
            ativo: _eu,
            aoTocar: () => setState(() => _eu = true),
          ),
          const SizedBox(height: 18),
        ],
        if (!_eu) ...[
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
          const SizedBox(height: 14),
          CampoTexto(
            rotulo: 'Telemóvel (opcional, para lhe ligar)',
            dica: '912 345 678',
            controlador: _telefone,
            erro: _erroTelefone,
            teclado: TextInputType.phone,
            maxLength: 18,
            aoMudar: (_) {
              if (_erroTelefone != null) setState(() => _erroTelefone = null);
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
        ],
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
        if (!_eu) const SizedBox(height: 18),
        // O RGPD: dados de saúde exigem consentimento. A pessoa acompanhada não tem conta, por isso
        // quem a adiciona declara que tem a autorização dela (ou do representante legal).
        if (!_eu)
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
    return EcraResultado(
      topo: TopoResultado(
        titulo: '${pessoa.nome} já está no Amparo',
        texto: alarmesNaPessoa
            ? 'O perfil está criado. Falta ligar o telemóvel de ${pessoa.nome}.'
            : 'O perfil está criado. Os alarmes tocam no seu telemóvel.',
      ),
      cartao: CartaoResultado(
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
                  const SizedBox(height: 2),
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
      acoes: [
        if (alarmesNaPessoa)
          Botao(
            texto: 'Ligar o telemóvel de ${pessoa.nome}',
            altura: 60,
            raio: 22,
            tamanhoTexto: 18,
            aoTocar: aoLigarTelemovel,
          ),
        AcaoTexto(
          texto: 'Adicionar uma receita primeiro',
          aoTocar: aoAdicionarReceita,
        ),
        AcaoTexto(texto: 'Concluir', aoTocar: aoConcluir),
      ],
    );
  }
}
