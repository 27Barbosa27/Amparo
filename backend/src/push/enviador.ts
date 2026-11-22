import { SignJWT, importPKCS8 } from 'jose';

/**
 * O que vai pela Google/Apple: só um tipo de evento e identificadores opacos. NUNCA dados de saúde,
 * nomes de medicamentos nem nomes de pessoas. A app, ao receber, vai ao servidor buscar o detalhe por HTTPS
 * e cria a notificação localmente.
 */
export interface MensagemPush {
  tipo: 'alerta' | 'sync';
  /** UUID do perfil. */
  perfil: string;
  subtipo?: 'toma_nao_confirmada' | 'toma_feita' | 'receita_a_acabar';
}

export interface EnviadorPush {
  /** Devolve os tokens que o FCM rejeitou como inexistentes ou revogados (para os apagar). */
  enviar(tokens: string[], mensagem: MensagemPush): Promise<{ invalidos: string[] }>;
}

/** Sem credenciais do Firebase (desenvolvimento): não envia nada. */
export const enviadorNulo: EnviadorPush = {
  async enviar() {
    return { invalidos: [] };
  },
};

export interface ContaServico {
  project_id: string;
  client_email: string;
  private_key: string;
}

const ESCOPO = 'https://www.googleapis.com/auth/firebase.messaging';
const URL_TOKEN = 'https://oauth2.googleapis.com/token';

/** Corpo da mensagem. Só os campos opacos vão em `data`; o texto visível é genérico, nunca clínico. */
export function corpoMensagem(token: string, m: MensagemPush) {
  const data: Record<string, string> = { tipo: m.tipo, perfil: m.perfil };
  if (m.subtipo) data.subtipo = m.subtipo;
  const visivel = m.tipo === 'alerta';
  return {
    message: {
      token,
      data,
      android: { priority: 'HIGH' },
      apns: {
        headers: { 'apns-priority': visivel ? '10' : '5', 'apns-push-type': visivel ? 'alert' : 'background' },
        payload: { aps: visivel ? { alert: { title: 'Amparo', body: 'Tem um aviso novo.' }, sound: 'default' } : { 'content-available': 1 } },
      },
      ...(visivel ? { notification: { title: 'Amparo', body: 'Tem um aviso novo.' } } : {}),
    },
  };
}

/** Envia pelo Firebase Cloud Messaging (API HTTP v1). Só se usa o FCM do Firebase, nada mais. */
export function criarEnviadorFcm(conta: ContaServico, http: typeof fetch = fetch): EnviadorPush {
  let acesso: { token: string; expiraEm: number } | null = null;

  async function tokenDeAcesso(): Promise<string> {
    if (acesso && acesso.expiraEm - 60_000 > Date.now()) return acesso.token;
    const chave = await importPKCS8(conta.private_key, 'RS256');
    const assertion = await new SignJWT({ scope: ESCOPO })
      .setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
      .setIssuer(conta.client_email)
      .setSubject(conta.client_email)
      .setAudience(URL_TOKEN)
      .setIssuedAt()
      .setExpirationTime('55m')
      .sign(chave);
    const r = await http(URL_TOKEN, {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }),
    });
    if (!r.ok) throw new Error(`FCM: falha ao obter o token de acesso (${r.status})`);
    const j = (await r.json()) as { access_token: string; expires_in: number };
    acesso = { token: j.access_token, expiraEm: Date.now() + j.expires_in * 1000 };
    return acesso.token;
  }

  return {
    async enviar(tokens, mensagem) {
      const invalidos: string[] = [];
      if (tokens.length === 0) return { invalidos };
      const bearer = await tokenDeAcesso();
      const url = `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(conta.project_id)}/messages:send`;
      for (const token of tokens) {
        const r = await http(url, {
          method: 'POST',
          headers: { authorization: `Bearer ${bearer}`, 'content-type': 'application/json' },
          body: JSON.stringify(corpoMensagem(token, mensagem)),
        });
        if (r.ok) continue;
        const erro = (await r.json().catch(() => ({}))) as { error?: { status?: string; details?: { errorCode?: string }[] } };
        const codigo = erro.error?.details?.find((d) => d.errorCode)?.errorCode ?? erro.error?.status;
        // Token que o FCM já não conhece (app desinstalada, token rodado): apaga-se.
        if (r.status === 404 || codigo === 'UNREGISTERED' || codigo === 'NOT_FOUND') invalidos.push(token);
        else console.error('FCM: envio falhou', r.status, codigo ?? '');
      }
      return { invalidos };
    },
  };
}
