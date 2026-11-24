-- Up Migration
-- A recuperação passa a usar um código de 6 dígitos (em vez de um link): conta-se as tentativas falhadas,
-- e ao fim de 5 o código deixa de valer (6 dígitos só são seguros com este limite).
alter table password_resets add column tentativas int not null default 0;
-- Códigos antigos (links) deixam de valer.
update password_resets set expira_em = now() where usado_em is null and expira_em > now();

-- Down Migration
alter table password_resets drop column if exists tentativas;
