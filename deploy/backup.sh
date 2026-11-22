#!/usr/bin/env bash
# Backup cifrado da base de dados do Amparo.
#   BACKUP_GPG_RECIPIENT=backups@amparo.example deploy/backup.sh
# Cifra com a chave PÚBLICA gpg do destinatário: a VPS não guarda a chave privada, por isso quem
# roubasse os backups (ou a VPS) não os consegue abrir. Só quem tem a chave privada restaura.
#
# Variáveis: BACKUP_GPG_RECIPIENT (obrigatória), POSTGRES_USER, POSTGRES_DB,
#            DB_CONTAINER (amparo-db), BACKUP_DIR (/var/backups/amparo), RETENCAO_DIAS (14).
# O backup NÃO inclui EMAIL_ENC_KEY nem PROFILE_MASTER_KEY: guarde essas chaves à parte (ver docs/deploy.md).
set -euo pipefail

: "${BACKUP_GPG_RECIPIENT:?defina BACKUP_GPG_RECIPIENT (identificador da chave pública gpg)}"
POSTGRES_USER="${POSTGRES_USER:-amparo}"
POSTGRES_DB="${POSTGRES_DB:-amparo}"
DB_CONTAINER="${DB_CONTAINER:-amparo-db}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/amparo}"
RETENCAO_DIAS="${RETENCAO_DIAS:-14}"

umask 077
mkdir -p "$BACKUP_DIR"
destino="$BACKUP_DIR/amparo-$(date -u +%Y%m%dT%H%M%SZ).dump.gpg"
parcial="$destino.parcial"
trap 'rm -f "$parcial"' EXIT

# pipefail: se o pg_dump falhar, o script falha e o ficheiro parcial é apagado.
podman exec "$DB_CONTAINER" pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom --no-owner \
  | gpg --batch --yes --trust-model always --encrypt --recipient "$BACKUP_GPG_RECIPIENT" --output "$parcial"

[ -s "$parcial" ] || { echo "Backup vazio: abortado." >&2; exit 1; }
mv "$parcial" "$destino"

# Retenção: apaga os backups mais antigos que RETENCAO_DIAS.
find "$BACKUP_DIR" -name 'amparo-*.dump.gpg' -mtime "+$RETENCAO_DIAS" -delete

echo "$destino"
