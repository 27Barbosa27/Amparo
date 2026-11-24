-- Up Migration
-- Verificação do email no registo: a conta só abre sessão depois de se provar que o email é de quem se registou.
alter table users add column email_verificado_em timestamptz;
-- As contas que já existem contam como verificadas (não se lhes pede nada de novo).
update users set email_verificado_em = now();

-- O código de 6 dígitos que se envia por email. Só o hash fica guardado; 5 erros esgotam o código.
create table email_verificacoes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users (id) on delete cascade,
  codigo_hash bytea not null,
  expira_em timestamptz not null,
  tentativas int not null default 0,
  usado_em timestamptz,
  criado_em timestamptz not null default now()
);
create index email_verificacoes_user_idx on email_verificacoes (user_id, criado_em);

-- Down Migration
drop table if exists email_verificacoes;
alter table users drop column if exists email_verificado_em;
