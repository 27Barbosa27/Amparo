-- Up Migration
-- A geração das tomas de uma receita pode correr em segundo plano; o cliente segue o estado.
alter table receitas add column geracao_estado text not null default 'concluida'
  check (geracao_estado in ('a_gerar', 'concluida', 'falhou'));
alter table receitas add column geracao_tomas int not null default 0;

-- Down Migration
alter table receitas drop column if exists geracao_tomas;
alter table receitas drop column if exists geracao_estado;
