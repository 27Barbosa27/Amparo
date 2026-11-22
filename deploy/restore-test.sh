#!/usr/bin/env bash
# Teste de restauro: um backup que nunca se restaurou não é um backup.
#   deploy/restore-test.sh /caminho/amparo-20261122T030000Z.dump.gpg
# Corre numa máquina que tenha a chave PRIVADA gpg (a tua, não a VPS). Decifra o backup, restaura-o num
# PostgreSQL descartável (contentor temporário, nunca na base de dados verdadeira) e verifica o resultado.
# Termina com código 0 se a restauração e as verificações passarem.
set -euo pipefail

ficheiro="${1:?uso: restore-test.sh <ficheiro.dump.gpg>}"
[ -s "$ficheiro" ] || { echo "Ficheiro inexistente ou vazio: $ficheiro" >&2; exit 1; }

nome="amparo-restore-test-$$"
imagem="${POSTGRES_IMAGE:-docker.io/library/postgres:17-alpine}"
trap 'podman rm -f "$nome" >/dev/null 2>&1 || true' EXIT

echo "A criar um PostgreSQL descartável..."
podman run -d --rm --name "$nome" -e POSTGRES_USER=amparo -e POSTGRES_PASSWORD=descartavel -e POSTGRES_DB=restauro "$imagem" >/dev/null
# O arranque do PostgreSQL reinicia uma vez: espera pelas duas mensagens "ready".
for _ in $(seq 1 90); do
  [ "$(podman logs "$nome" 2>&1 | grep -c 'ready to accept connections')" -ge 2 ] && break
  sleep 1
done
sql() { podman exec "$nome" psql -U amparo -d restauro -tA -c "$1"; }
sql 'select 1' >/dev/null || { echo "O PostgreSQL descartável não arrancou." >&2; exit 1; }

echo "A decifrar e restaurar..."
gpg --batch --decrypt "$ficheiro" | podman exec -i "$nome" pg_restore -U amparo -d restauro --no-owner --exit-on-error

echo "A verificar..."
falhas=0
verificar() { # descrição, consulta, valor esperado (mínimo)
  local obtido
  obtido="$(sql "$2")"
  if [ "${obtido:-0}" -ge "$3" ]; then echo "  ok   $1 ($obtido)"; else echo "  FALHA $1 (obtido $obtido, esperado >= $3)"; falhas=$((falhas + 1)); fi
}
verificar "tabelas" "select count(*) from information_schema.tables where table_schema = 'public' and table_type = 'BASE TABLE'" 15
verificar "auditoria append-only (trigger)" "select count(*) from pg_trigger where tgname = 'audit_logs_sem_alteracoes'" 1
verificar "migrações aplicadas" "select count(*) from pgmigrations" 4
echo "  info utilizadores: $(sql 'select count(*) from users'), perfis: $(sql 'select count(*) from profiles'), tomas: $(sql 'select count(*) from tomas')"

# A auditoria restaurada continua imutável?
if podman exec "$nome" psql -U amparo -d restauro -c "delete from audit_logs" >/dev/null 2>&1; then
  echo "  FALHA a auditoria restaurada deixou apagar linhas"; falhas=$((falhas + 1))
else
  echo "  ok   a auditoria restaurada recusa apagar"
fi

if [ "$falhas" -eq 0 ]; then echo "RESTAURO OK"; else echo "RESTAURO COM FALHAS: $falhas" >&2; exit 1; fi
