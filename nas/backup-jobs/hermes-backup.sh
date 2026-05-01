#!/usr/bin/env bash
# Followups Plan Task 7 — nightly logical backup of Hermes Agent.
#
# Hermes ships its own `hermes backup` subcommand that produces a self-contained
# zip of config + skills + sessions + memory + auth + cron. We invoke it via
# `docker exec` (Hermes container runs as 568, can write into the bind-mounted
# /opt/data), then encrypt + move to /mnt/bulk/backups/hermes/.
#
# Output: /mnt/bulk/backups/hermes/hermes-<ISO>.zip.gpg
# Same encryption / retention / heartbeat shape as gitea-pgdump.sh +
# litellm-pgdump.sh (Phase 8 Tasks 3 + 4).

set -euo pipefail

# Capture all output to a log unconditionally — `midclt call cronjob.run`
# appends `> /dev/null 2> /dev/null` to whatever you put in the cron command,
# silencing the `>> log 2>&1` redirect that we add in the cron entry. Real
# cron passes through, but this makes both invocation paths identical.
exec >> /var/log/hermes-backup.log 2>&1
echo "==== $(date -u +%FT%TZ) hermes-backup.sh start ===="

DEST=/mnt/bulk/backups/hermes
PASSF=/mnt/bulk/backups/.secrets/dump-passphrase
RETAIN_DAYS=14
DATA_DIR=/mnt/.ix-apps/app_mounts/hermes/data        # host-side bind mount of /opt/data inside container
TMP_BASENAME=_pending_backup.zip                      # ephemeral, lives inside DATA_DIR briefly

[ -f /root/.backup-env ] && . /root/.backup-env || true
KUMA_URL="${KUMA_URL_HERMES_DUMP:-}"

mkdir -p "$DEST"
chmod 700 "$DEST"

DATE=$(date -u +%Y%m%dT%H%M%SZ)
OUT="$DEST/hermes-$DATE.zip.gpg"

HERMES_CONTAINER=$(docker ps --format '{{.Names}}' | grep '^ix-hermes-hermes-' | grep -v dashboard | head -1)
if [ -z "$HERMES_CONTAINER" ]; then
  echo "ERROR: ix-hermes-hermes-* container not running" >&2
  exit 1
fi

# Run hermes backup inside the container — writes to the bind-mounted data dir.
# Use absolute venv path: `docker exec` doesn't run a login shell so the
# entrypoint's `source /opt/hermes/.venv/bin/activate` is NOT in effect, and
# the bare `hermes` symbol isn't on PATH.
#
# NOT using `-q` (--quick): quick mode writes an internal state snapshot to
# /opt/data/state-snapshots/ and ignores `-o`. We need a real portable zip,
# which is what the full backup produces.
docker exec "$HERMES_CONTAINER" /opt/hermes/.venv/bin/hermes backup -o "/opt/data/$TMP_BASENAME"

TMP_HOST="$DATA_DIR/$TMP_BASENAME"
if [ ! -s "$TMP_HOST" ]; then
  echo "ERROR: hermes backup produced empty file at $TMP_HOST" >&2
  rm -f "$TMP_HOST"
  exit 1
fi

# Encrypt to dest, then drop the plaintext zip.
gpg --batch --yes --symmetric --cipher-algo AES256 \
    --passphrase-file "$PASSF" --output "$OUT" "$TMP_HOST"
rm -f "$TMP_HOST"

if [ ! -s "$OUT" ]; then
  echo "ERROR: encrypted dump output is empty: $OUT" >&2
  exit 1
fi

find "$DEST" -name 'hermes-*.zip.gpg' -mtime +$RETAIN_DAYS -delete

[ -n "$KUMA_URL" ] && curl -fsS -m 10 "$KUMA_URL?status=up&msg=ok" >/dev/null || true

echo "$(date -u +%FT%TZ) hermes dump ok: $OUT ($(du -h "$OUT" | cut -f1))"
