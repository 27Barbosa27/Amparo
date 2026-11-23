-- Up Migration
-- A API deve ligar-se à base de dados com um papel de MENOS privilégios do que o dono do esquema.
-- Assim o "append-only" da auditoria não depende só do trigger: o papel de execução nem sequer
-- tem permissão para alterar ou apagar linhas do audit_logs (REVOKE + trigger, como o plano pede).
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'amparo_app') then
    create role amparo_app nologin;
  end if;
end
$$;

grant usage on schema public to amparo_app;
grant select, insert, update, delete on all tables in schema public to amparo_app;
grant usage, select on all sequences in schema public to amparo_app;
alter default privileges in schema public grant select, insert, update, delete on tables to amparo_app;
alter default privileges in schema public grant usage, select on sequences to amparo_app;

-- A auditoria só se lê e só se acrescenta.
revoke update, delete, truncate on audit_logs from amparo_app;
revoke update, delete, truncate on audit_logs from public;
-- O histórico das migrações não é da API.
revoke all on pgmigrations from amparo_app;

-- Down Migration
revoke all on all tables in schema public from amparo_app;
revoke all on all sequences in schema public from amparo_app;
alter default privileges in schema public revoke all on tables from amparo_app;
alter default privileges in schema public revoke all on sequences from amparo_app;
revoke usage on schema public from amparo_app;
