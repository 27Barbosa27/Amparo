/** Erro de autenticação com um código estável para a app (ver "Erros" no plano) e o estado HTTP. */
export class ErroAuth extends Error {
  constructor(
    public readonly codigo:
      | 'credenciais_invalidas'
      | 'email_ja_existe'
      | 'demasiadas_tentativas'
      | 'refresh_invalido'
      | 'nao_autenticado',
    public readonly estado: number,
  ) {
    super(codigo);
    this.name = 'ErroAuth';
  }
}
