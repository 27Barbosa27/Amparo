/**
 * Ganchos que o resto do backend chama quando algo muda. Os testes passam versões falsas;
 * em produção quem os implementa é o módulo de push (src/push).
 */
export interface Eventos {
  /** Uma toma foi marcada como tomada. `porUserId` é o cuidador que a marcou (nulo se foi a própria pessoa). */
  tomaRegistada(profileId: string, tomaId: string, porUserId: string | null): Promise<void>;
  /** Uma edição do cuidador (receitas, medicamentos) que o telemóvel da pessoa deve ir buscar. */
  sincronizar(profileId: string): Promise<void>;
}

export const semEventos: Eventos = {
  async tomaRegistada() {},
  async sincronizar() {},
};

/** Chama um gancho sem nunca fazer falhar o pedido (o push é um extra, nunca a garantia). */
export async function dispararSemFalhar(f: () => Promise<void>): Promise<void> {
  try {
    await f();
  } catch (e) {
    console.error('Falha num gancho de evento:', e instanceof Error ? e.message : 'desconhecido');
  }
}
