-- Up Migration
-- Telefone da pessoa acompanhada (para o botão "Ligar" do cuidador): dado pessoal opcional, guardado cifrado
-- com a chave dos campos, como o telefone do cuidador em users.
alter table profiles add column telefone_cifrado bytea;

-- Down Migration
alter table profiles drop column telefone_cifrado;
