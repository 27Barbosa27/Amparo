-- Up Migration
-- O email passa a guardar-se também CIFRADO (AES-256-GCM), para se poder enviar o link de
-- recuperação de palavra-passe. O email_hash continua a servir para encontrar a conta.
alter table users add column email_cifrado bytea;

-- Down Migration
alter table users drop column if exists email_cifrado;
