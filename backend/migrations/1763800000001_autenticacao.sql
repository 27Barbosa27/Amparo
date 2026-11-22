-- Up Migration
-- Autenticação por email e palavra-passe: nome a mostrar, bloqueio progressivo e famílias de refresh tokens.

alter table users
  add column nome_exibicao text,
  add column falhas_login int not null default 0,
  add column bloqueado_ate timestamptz;

-- Cada login abre uma "família" de refresh tokens. Se um token já usado aparecer outra vez
-- (sinal de roubo), revoga-se a família inteira.
alter table refresh_tokens
  add column familia_id uuid not null default gen_random_uuid();
create index refresh_tokens_familia_idx on refresh_tokens (familia_id);

-- Down Migration
drop index if exists refresh_tokens_familia_idx;
alter table refresh_tokens drop column if exists familia_id;
alter table users
  drop column if exists bloqueado_ate,
  drop column if exists falhas_login,
  drop column if exists nome_exibicao;
