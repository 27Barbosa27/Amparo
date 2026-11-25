-- Up Migration
-- O aviso de "toma não confirmada" deixa de ter só 3 opções fixas (10/15/30 min): o cuidador escreve os minutos.
alter table alert_prefs drop constraint alert_prefs_espera_min_check;
alter table alert_prefs add constraint alert_prefs_espera_min_check check (espera_min between 1 and 180);

-- Down Migration
alter table alert_prefs drop constraint alert_prefs_espera_min_check;
alter table alert_prefs add constraint alert_prefs_espera_min_check check (espera_min in (10, 15, 30));
