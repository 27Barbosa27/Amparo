/**
 * Ganchos que o resto do backend chama quando algo muda. Os testes passam versões falsas;
 * em produção quem os implementa é o módulo de push (src/push).
 */
export interface Eventos {
  /** Uma toma foi marcada como tomada. `porUserId` é o cuidador que a marcou (nulo se foi a própria pessoa). */
  tomaRegistada(profileId: string, tomaId: string, porUserId: string | null): Promise<void>;
  /** Uma edição do cuidador (receitas, medicamentos) que o telemóvel da pessoa deve ir buscar. */
  sincronizar(profileId: string): Promise<void>;
  /**
   * "Lembrar": o cuidador pede ao telemóvel da pessoa que volte a mostrar o alarme desta toma.
   * `recente`: este cuidador já lembrou esta toma há menos de 5 minutos (não se insiste).
   */
  lembrar(profileId: string, tomaId: string, porUserId: string): Promise<ResultadoLembrete>;
}

export type ResultadoLembrete = 'enviado' | 'sem_telemovel' | 'recente';

export const semEventos: Eventos = {
  async tomaRegistada() {},
  async sincronizar() {},
  async lembrar() {
    return 'sem_telemovel';
  },
};

/** Chama um gancho sem nunca fazer falhar o pedido (o push é um extra, nunca a garantia). */
export async function dispararSemFalhar(f: () => Promise<void>): Promise<void> {
  try {
    await f();
  } catch (e) {
    console.error('Falha num gancho de evento:', e instanceof Error ? e.message : 'desconhecido');
  }
}
