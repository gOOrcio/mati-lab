#!/usr/bin/env bash
# Nightly CouchDB dump of the obsidian-vault database (LiveSync store).
#
# Replaces the former inline `curl -u admin:<password>` cron command —
# credentials now come from /root/.backup-env (root:root 0600), so they no
# longer appear in `midclt call cronjob.query` output, `ps`, or the
# middleware DB. See nas/secrets-inventory.md (Obsidian section).
#
# Output: /mnt/bulk/backups/obsidian/obsidian-vault-<date>.json
# Retention: 30 days. (Unencrypted by design: the same content lives
# unencrypted in /mnt/bulk/obsidian-vault; the gpg passphrase protects
# dumps that leave the pool, which this one doesn't.)

set -euo pipefail

DEST=/mnt/bulk/backups/obsidian
RETAIN_DAYS=30

[ -f /root/.backup-env ] && . /root/.backup-env || true

for v in COUCHDB_ADMIN_USER COUCHDB_ADMIN_PASSWORD; do
  if [ -z "${!v:-}" ]; then
    echo "ERROR: $v missing from /root/.backup-env" >&2
    exit 1
  fi
done

mkdir -p "$DEST"

OUT="$DEST/obsidian-vault-$(date +%F).json"
curl -fsS -u "$COUCHDB_ADMIN_USER:$COUCHDB_ADMIN_PASSWORD" \
  'http://127.0.0.1:30015/obsidian-vault/_all_docs?include_docs=true' \
  -o "$OUT"

if [ ! -s "$OUT" ]; then
  echo "ERROR: dump empty: $OUT" >&2
  exit 1
fi

find "$DEST" -name 'obsidian-vault-*.json' -mtime +$RETAIN_DAYS -delete

echo "$(date -u +%FT%TZ) obsidian couchdb dump ok: $OUT ($(du -h "$OUT" | cut -f1))"
