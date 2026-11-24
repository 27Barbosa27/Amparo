/** Erro de autenticação com um código estável para a app (ver "Erros" no plano) e o estado HTTP. */
export class ErroAuth extends Error {
  constructor(
    public readonly codigo:
      | 'credenciais_invalidas'
      | 'email_ja_existe'
      | 'demasiadas_tentativas'
      | 'refresh_invalido'
      | 'nao_autenticado'
      | 'codigo_invalido'
      | 'sem_permissao'
      | 'provedor_invalido'
      | 'provedor_nao_configurado'
      | 'consentimento_necessario'
      | 'toma_nao_encontrada'
      | 'toma_ja_registada'
      | 'desfazer_expirado'
      | 'hora_invalida'
      | 'senha_incorreta'
      | 'token_invalido'
      | 'email_nao_verificado',
    public readonly estado: number,
  ) {
    super(codigo);
    this.name = 'ErroAuth';
  }
}
