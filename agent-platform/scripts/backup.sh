#!/usr/bin/env bash
# Nightly dump. Install on the host with:
#   (crontab -l 2>/dev/null; echo "0 3 * * * $HOME/agent-platform/scripts/backup.sh") | crontab -
#
# WHAT THIS IS, HONESTLY: a dump on the same disk as the database is a restore point for an
# application mistake — a bad migration, a wrong DELETE. It is NOT a backup. It survives nothing
# that kills the machine. BACKUP_OFFSITE_DEST is where that gets fixed, and until it is set this
# script warns on every run rather than looking successful.
set -euo pipefail

cd "$HOME/agent-platform"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
OUT="backups/agent_platform_${STAMP}.sql.gz"
KEEP_DAYS=14

mkdir -p backups

# --clean --if-exists so a restore into a non-empty database works rather than half-failing.
docker compose exec -T db pg_dump -U agent -d agent_platform --clean --if-exists \
  | gzip -9 > "$OUT"

SIZE=$(stat -c%s "$OUT")
if [ "$SIZE" -lt 1024 ]; then
    # A dump that produced almost nothing is a failed dump wearing a success exit code — exactly
    # the silent-degradation case that must fail loudly instead.
    echo "FAILED: dump is only ${SIZE} bytes, refusing to keep it" >&2
    exit 1
fi
echo "wrote $OUT (${SIZE} bytes)"

# Retention. These dumps contain personal data, so keeping them forever is its own liability — and
# a deletion request has to reach them too, or the erasure is incomplete.
find backups -name 'agent_platform_*.sql.gz' -mtime "+${KEEP_DAYS}" -print -delete

if [ -n "${BACKUP_OFFSITE_DEST:-}" ]; then
    rsync -a "$OUT" "${BACKUP_OFFSITE_DEST}/"
    echo "copied offsite to ${BACKUP_OFFSITE_DEST}"
else
    echo "WARNING: BACKUP_OFFSITE_DEST unset — this dump shares a disk with the database" >&2
fi
