#!/usr/bin/env bash
# Backup Odoo database, Docker volumes, and home directory to /storage/backups/.
# Run as root or with sudo for full access to /data/docker/.
set -euo pipefail

BACKUP_ROOT="/storage/backups"
DATE=$(date +%Y%m%d-%H%M%S)
DOCKER_BACKUP="${BACKUP_ROOT}/docker-${DATE}"
HOME_BACKUP="${BACKUP_ROOT}/home-${DATE}"
DB_BACKUP="${BACKUP_ROOT}/odoo-db-${DATE}.sql.gz"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# ---------------------------------------------------------------------------
# Odoo PostgreSQL dump
# ---------------------------------------------------------------------------
log "Dumping Odoo database..."
ODOO_DB_CONTAINER=$(docker compose \
  --project-directory /home/laszlokr/guix-config/docker/odoo \
  ps -q db 2>/dev/null | head -1)

if [ -n "$ODOO_DB_CONTAINER" ]; then
  docker exec "$ODOO_DB_CONTAINER" \
    pg_dump -U odoo odoo | gzip > "$DB_BACKUP"
  log "Database dump: $DB_BACKUP ($(du -sh "$DB_BACKUP" | cut -f1))"
else
  log "WARNING: Odoo db container not running — skipping database dump."
fi

# ---------------------------------------------------------------------------
# Docker volume data
# ---------------------------------------------------------------------------
log "Syncing /data/docker/ → ${DOCKER_BACKUP}/"
mkdir -p "$DOCKER_BACKUP"
rsync -a --delete \
  --exclude='*.tmp' \
  /data/docker/ "${DOCKER_BACKUP}/"
log "Docker backup: $(du -sh "$DOCKER_BACKUP" | cut -f1)"

# ---------------------------------------------------------------------------
# Home directory
# ---------------------------------------------------------------------------
log "Syncing /home/laszlokr/ → ${HOME_BACKUP}/"
mkdir -p "$HOME_BACKUP"
rsync -a --delete \
  --exclude='.cache/' \
  --exclude='.local/share/containers/' \
  --exclude='Downloads/' \
  --exclude='downloads/' \
  /home/laszlokr/ "${HOME_BACKUP}/"
log "Home backup: $(du -sh "$HOME_BACKUP" | cut -f1)"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
log "Backup complete."
echo ""
echo "  DB dump : $(du -sh "$DB_BACKUP"   2>/dev/null | cut -f1 || echo 'skipped')"
echo "  Docker  : $(du -sh "$DOCKER_BACKUP" | cut -f1)"
echo "  Home    : $(du -sh "$HOME_BACKUP"   | cut -f1)"
echo "  Total   : $(du -sh "$BACKUP_ROOT"   | cut -f1) in $BACKUP_ROOT"
