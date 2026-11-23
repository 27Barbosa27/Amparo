/**
 * Dados de demonstração para desenvolver a app contra a API verdadeira.
 *   npm run dev          (noutro terminal: a API tem de estar a correr)
 *   npm run seed:dev
 * Cria a conta de cuidador de teste, duas pessoas com receitas e uma semana de histórico.
 * É seguro repetir: se a conta já existe, não faz nada. Só serve para desenvolvimento.
 */
const API = process.env.API_URL ?? 'http://127.0.0.1:3000';
export const EMAIL_DEMO = 'demo@amparo.test';
export const SENHA_DEMO = 'amparo-demo-123';

async function chamar(metodo: string, caminho: string, token?: string, corpo?: unknown, perfil?: string) {
  const r = await fetch(`${API}${caminho}`, {
    method: metodo,
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      ...(perfil ? { 'x-profile-id': perfil } : {}),
    },
    body: corpo === undefined ? undefined : JSON.stringify(corpo),
  });
  const texto = await r.text();
  return { estado: r.status, corpo: texto ? (JSON.parse(texto) as any) : null };
}

async function main() {
  const entrada = await chamar('POST', '/auth/login', undefined, { email: EMAIL_DEMO, senha: SENHA_DEMO });
  if (entrada.estado === 200) {
    console.log('A conta de demonstração já existe: nada a fazer.');
    return;
  }
  const reg = await chamar('POST', '/auth/registo', undefined, { email: EMAIL_DEMO, senha: SENHA_DEMO, nome: 'Ana', aceitaTermos: true });
  if (reg.estado !== 201) throw new Error(`Registo falhou: ${reg.estado} ${JSON.stringify(reg.corpo)}`);
  const token: string = reg.corpo.accessToken;
  await chamar('PATCH', '/auth/me', token, { telefone: '+351 912 345 678' });

  const inicio = new Date(Date.now() - 7 * 86_400_000).toISOString();
  const pessoas: { nome: string; meds: { nome: string; dose: string; horas: string[] }[] }[] = [
    {
      nome: 'Maria',
      meds: [
        { nome: 'Metformina', dose: '1 comprimido', horas: ['08:00', '13:00'] },
        { nome: 'Lisinopril', dose: '10 mg', horas: ['09:00'] },
        { nome: 'Atorvastatina', dose: '20 mg', horas: ['21:00'] },
      ],
    },
    { nome: 'Manuel', meds: [{ nome: 'Ramipril', dose: '5 mg', horas: ['10:00'] }] },
  ];

  for (const p of pessoas) {
    const pr = await chamar('POST', '/profiles', token, { pseudonimo: p.nome, autorizacaoDeclarada: true });
    if (pr.estado !== 201) throw new Error(`Perfil falhou: ${JSON.stringify(pr.corpo)}`);
    const perfilId: string = pr.corpo.perfil.id;
    for (const m of p.meds) {
      const med = await chamar('POST', `/profiles/${perfilId}/medicamentos`, token, { nome: m.nome });
      const rec = await chamar('POST', `/profiles/${perfilId}/receitas`, token, {
        medicamentoId: med.corpo.medicamento.id,
        dose: m.dose,
        horario: { tipo: 'horas_fixas', horasLocais: m.horas },
        inicio,
        unidadesIniciais: 40,
      });
      if (rec.estado !== 201) throw new Error(`Receita falhou: ${JSON.stringify(rec.corpo)}`);
    }

    // Histórico: marca como tomadas as tomas já passadas há mais de 3 horas, menos as de um dia (a "toma esquecida").
    const agora = Date.now();
    const lista = await chamar('GET', `/tomas?de=${encodeURIComponent(inicio)}&ate=${encodeURIComponent(new Date(agora).toISOString())}`, token, undefined, perfilId);
    const esquecer = new Date(agora - 4 * 86_400_000).toISOString().slice(0, 10);
    let marcadas = 0;
    for (const t of lista.corpo.tomas as { id: string; agendadaUtc: string; estado: string }[]) {
      if (t.estado !== 'pendente' || Date.parse(t.agendadaUtc) > agora - 3 * 3_600_000) continue;
      if (t.agendadaUtc.slice(0, 10) === esquecer) continue;
      await chamar('POST', `/tomas/${t.id}/registo`, token, { tomadaEmUtc: t.agendadaUtc }, perfilId);
      marcadas++;
    }
    console.log(`Pessoa "${p.nome}": ${p.meds.length} receitas, ${marcadas} tomas passadas marcadas.`);
  }
  console.log(`\nPronto. Entre na app com ${EMAIL_DEMO} e a palavra-passe ${SENHA_DEMO} (só para desenvolvimento).`);
}

main().catch((e) => {
  console.error(e instanceof Error ? e.message : e);
  process.exit(1);
});
