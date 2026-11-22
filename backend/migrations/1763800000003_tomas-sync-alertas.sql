-- Up Migration
-- Registo de tomas: quando foi registada (para o "desfazer 1 min" e para resolver conflitos da fila offline).
alter table tomas add column registado_em timestamptz;
alter table tomas add column atualizado_em timestamptz not null default now();
create index tomas_profile_atualizado_idx on tomas (profile_id, atualizado_em);

create function tomas_tocar() returns trigger language plpgsql as $$
begin
  new.atualizado_em := now();
  return new;
end;
$$;
create trigger tomas_atualizado before update on tomas for each row execute function tomas_tocar();

-- Sincronização delta: as tomas apagadas (regeneração) ficam registadas para os telemóveis as removerem.
create table tomas_removidas (
  id bigserial primary key,
  toma_id uuid not null,
  profile_id uuid not null,
  removida_em timestamptz not null default now()
);
create index tomas_removidas_profile_idx on tomas_removidas (profile_id, removida_em);

create function tomas_registar_remocao() returns trigger language plpgsql as $$
begin
  insert into tomas_removidas (toma_id, profile_id) values (old.id, old.profile_id);
  return old;
end;
$$;
create trigger tomas_removidas_trg after delete on tomas for each row execute function tomas_registar_remocao();

-- Alertas já enviados (evita enviar o mesmo alerta duas vezes ao mesmo cuidador).
create table alertas_enviados (
  user_id uuid not null references users (id) on delete cascade,
  tipo text not null,
  chave text not null,
  enviado_em timestamptz not null default now(),
  primary key (user_id, tipo, chave)
);

-- O token FCM em claro só serve para enviar: guarda-se cifrado (o hash serve para o encontrar).
alter table push_tokens add column fcm_token_cifrado bytea;

-- Down Migration
alter table push_tokens drop column if exists fcm_token_cifrado;
drop table if exists alertas_enviados;
drop trigger if exists tomas_removidas_trg on tomas;
drop function if exists tomas_registar_remocao();
drop table if exists tomas_removidas;
drop trigger if exists tomas_atualizado on tomas;
drop function if exists tomas_tocar();
alter table tomas drop column if exists atualizado_em;
alter table tomas drop column if exists registado_em;
