-- Up Migration
-- Esquema inicial do Amparo (ver docs/plano.md, secção 5).
-- Tempo sempre em UTC (timestamptz). Campos clínicos sensíveis ficam cifrados na aplicação (bytea).

create type papel_acesso as enum ('owner', 'caregiver');
create type provedor_auth as enum ('apple', 'google');
create type tamanho_texto as enum ('normal', 'grande', 'muito_grande');
create type alarmes_em as enum ('dispositivo_da_pessoa', 'dispositivo_do_cuidador');
create type tipo_horario as enum ('intervalo', 'horas_fixas');
create type estado_toma as enum ('pendente', 'tomada', 'saltada', 'falhada');
create type origem_registo as enum ('dispositivo', 'cuidador');
create type plataforma_push as enum ('android', 'ios');

-- Só os cuidadores têm conta. As pessoas acompanhadas não criam conta.
create table users (
  id uuid primary key default gen_random_uuid(),
  email_hash bytea unique,
  password_hash text,                 -- Argon2id; nulo se entrou só com Apple/Google
  telefone_cifrado bytea,             -- opcional, para o botão "Ligar"
  consentimento_versao text not null,
  consentimento_em timestamptz not null,
  criado_em timestamptz not null default now()
);

create table auth_providers (
  user_id uuid not null references users (id) on delete cascade,
  provedor provedor_auth not null,
  provider_sub text not null,
  criado_em timestamptz not null default now(),
  primary key (provedor, provider_sub)
);
create index auth_providers_user_idx on auth_providers (user_id);

create table profiles (
  id uuid primary key default gen_random_uuid(),
  pseudonimo text not null,
  timezone text not null default 'Europe/Lisbon',
  tamanho_texto tamanho_texto not null default 'grande',
  alarmes_em alarmes_em not null default 'dispositivo_da_pessoa',
  chave_cifrada bytea not null,       -- chave por perfil (base do crypto-shredding)
  criado_em timestamptz not null default now()
);

create table profile_access (
  user_id uuid not null references users (id) on delete cascade,
  profile_id uuid not null references profiles (id) on delete cascade,
  papel papel_acesso not null,
  autorizacao_declarada_em timestamptz not null,
  autorizacao_versao text not null,
  criado_em timestamptz not null default now(),
  revogado_em timestamptz,
  primary key (user_id, profile_id)
);
create index profile_access_profile_idx on profile_access (profile_id);

create table alert_prefs (
  user_id uuid not null,
  profile_id uuid not null,
  toma_nao_confirmada boolean not null default true,
  espera_min int not null default 15 check (espera_min in (10, 15, 30)),
  toma_feita boolean not null default false,
  receita_a_acabar boolean not null default true,
  dias_antes int not null default 4 check (dias_antes between 1 and 30),
  primary key (user_id, profile_id),
  foreign key (user_id, profile_id) references profile_access (user_id, profile_id) on delete cascade
);

-- Código de ligação do telemóvel de uma pessoa (6 dígitos, 15 min, uso único). Guarda-se só o hash.
create table pairing_codes (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references profiles (id) on delete cascade,
  criado_por_user_id uuid not null references users (id) on delete cascade,
  codigo_hash bytea not null,
  expira_em timestamptz not null,
  usado_em timestamptz,
  criado_em timestamptz not null default now()
);
create index pairing_codes_ativos_idx on pairing_codes (codigo_hash) where usado_em is null;

-- Telemóvel de uma pessoa ligado por código, sem conta. Token de âmbito de um só perfil.
create table profile_devices (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references profiles (id) on delete cascade,
  token_hash bytea not null unique,
  nome text,
  criado_em timestamptz not null default now(),
  ultimo_uso_em timestamptz,
  alarmes_agendados int,              -- reportado pelo telemóvel (heartbeat)
  permissoes_alarme jsonb,            -- reportado pelo telemóvel (heartbeat)
  revogado_em timestamptz
);
create index profile_devices_profile_idx on profile_devices (profile_id);

create table push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users (id) on delete cascade,
  device_id uuid references profile_devices (id) on delete cascade,
  plataforma plataforma_push not null,
  fcm_token_hash bytea not null unique,
  criado_em timestamptz not null default now(),
  ultimo_uso_em timestamptz,
  revogado_em timestamptz,
  check ((user_id is not null) <> (device_id is not null))
);

create table medicamentos (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references profiles (id) on delete cascade,
  nome_cifrado bytea not null,
  notas_cifradas bytea,
  criado_em timestamptz not null default now()
);
create index medicamentos_profile_idx on medicamentos (profile_id);

-- A receita guarda a INTENÇÃO. As tomas são geradas a partir dela (janela rolante).
create table receitas (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references profiles (id) on delete cascade,
  medicamento_id uuid not null references medicamentos (id) on delete cascade,
  dose_cifrada bytea not null,
  tipo tipo_horario not null,
  intervalo_horas numeric(5, 2),      -- "de 8 em 8 horas": intervalo absoluto
  horas_locais time[],                -- "às 8h": hora local na timezone da receita
  timezone text not null,
  inicio_utc timestamptz not null,
  fim_utc timestamptz,
  valida_ate date,
  unidades_iniciais int check (unidades_iniciais is null or unidades_iniciais >= 0),
  ativa boolean not null default true,
  criado_em timestamptz not null default now(),
  check (fim_utc is null or fim_utc > inicio_utc),
  check (
    (tipo = 'intervalo' and intervalo_horas is not null and intervalo_horas > 0 and horas_locais is null)
    or
    (tipo = 'horas_fixas' and horas_locais is not null and cardinality(horas_locais) > 0 and intervalo_horas is null)
  )
);
create index receitas_profile_idx on receitas (profile_id) where ativa;

create table tomas (
  id uuid primary key default gen_random_uuid(),
  receita_id uuid not null references receitas (id) on delete cascade,
  profile_id uuid not null references profiles (id) on delete cascade,
  agendada_utc timestamptz not null,
  estado estado_toma not null default 'pendente',
  tomada_em_utc timestamptz,
  registada_por_user_id uuid references users (id) on delete set null,
  origem origem_registo,
  editada_manualmente boolean not null default false,
  idempotency_key text unique,
  criado_em timestamptz not null default now(),
  unique (receita_id, agendada_utc),  -- a geração nunca duplica uma toma
  check ((estado = 'tomada') = (tomada_em_utc is not null))
);
create index tomas_profile_agendada_idx on tomas (profile_id, agendada_utc);

create table refresh_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users (id) on delete cascade,
  hash bytea not null unique,
  expira_em timestamptz not null,
  revogado_em timestamptz,
  criado_em timestamptz not null default now()
);
create index refresh_tokens_user_idx on refresh_tokens (user_id);

-- Auditoria imutável. Nunca contém dados de saúde, só ids e o tipo de ação.
-- Sem chaves estrangeiras de propósito: o apagamento de um perfil não pode apagar o registo.
create table audit_logs (
  id bigserial primary key,
  ts_utc timestamptz not null default now(),
  user_id uuid,
  profile_id uuid,
  acao text not null,
  entidade text,
  entidade_id uuid,
  ip inet
);
create index audit_logs_profile_ts_idx on audit_logs (profile_id, ts_utc);

create function audit_logs_imutavel() returns trigger language plpgsql as $$
begin
  raise exception 'audit_logs é append-only: % não é permitido', tg_op using errcode = 'insufficient_privilege';
end;
$$;
create trigger audit_logs_sem_alteracoes before update or delete on audit_logs
  for each row execute function audit_logs_imutavel();
create trigger audit_logs_sem_truncate before truncate on audit_logs
  for each statement execute function audit_logs_imutavel();

-- Down Migration
drop table if exists audit_logs cascade;
drop function if exists audit_logs_imutavel();
drop table if exists refresh_tokens cascade;
drop table if exists tomas cascade;
drop table if exists receitas cascade;
drop table if exists medicamentos cascade;
drop table if exists push_tokens cascade;
drop table if exists profile_devices cascade;
drop table if exists pairing_codes cascade;
drop table if exists alert_prefs cascade;
drop table if exists profile_access cascade;
drop table if exists profiles cascade;
drop table if exists auth_providers cascade;
drop table if exists users cascade;
drop type if exists plataforma_push;
drop type if exists origem_registo;
drop type if exists estado_toma;
drop type if exists tipo_horario;
drop type if exists alarmes_em;
drop type if exists tamanho_texto;
drop type if exists provedor_auth;
drop type if exists papel_acesso;
