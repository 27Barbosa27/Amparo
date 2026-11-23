-- Up Migration
-- Recuperação de palavra-passe: token de uso único e curta duração. Só o hash fica guardado.
create table password_resets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users (id) on delete cascade,
  token_hash bytea not null unique,
  expira_em timestamptz not null,
  usado_em timestamptz,
  criado_em timestamptz not null default now()
);
create index password_resets_user_idx on password_resets (user_id, criado_em);

-- Down Migration
drop table if exists password_resets;
