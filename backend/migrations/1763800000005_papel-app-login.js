// Cria (ou atualiza a palavra-passe de) o utilizador com que a API se liga em produção: `amparo_runtime`,
// membro do papel `amparo_app`. Só corre se APP_DB_PASSWORD estiver definida; em desenvolvimento e nos
// testes a API liga-se com o dono do esquema e esta migração não faz nada.
export const shorthands = undefined;

export async function up(pgm) {
  const senha = process.env.APP_DB_PASSWORD;
  if (!senha) return;
  // O valor vai dentro de um bloco com $$: recusa-se o que o pudesse partir.
  if (senha.length < 24 || /['"$\\\s]/.test(senha)) {
    throw new Error('APP_DB_PASSWORD inválida: mínimo 24 caracteres, sem aspas, $, barras nem espaços (use base64url).');
  }
  pgm.sql(`
    do $$
    begin
      if not exists (select 1 from pg_roles where rolname = 'amparo_runtime') then
        create role amparo_runtime login in role amparo_app password '${senha}';
      else
        alter role amparo_runtime login password '${senha}';
      end if;
    end
    $$;
  `);
}

export async function down() {
  // O utilizador mantém-se: apagá-lo exigiria largar tudo o que lhe pertence.
}
