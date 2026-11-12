#!/usr/bin/env bash
# Run a budget operator command as root on the NAS (truenas_admin has neither
# docker access nor passwordless sudo) through a one-shot disabled cron job,
# the channel nas/paperless/deploy.sh uses. Output is printed afterwards.
#
# Usage: nas/budget/root-run.sh <command>
#   status                      container states + last 30 worker log lines
#   logs <service> [lines]      e.g. logs actual-ai 200
#   cli <args...>               docker exec the worker CLI, e.g. cli bootstrap
#   sql "<query>"               read-only psql against the Postgres mirror
#   backup                      run the nightly backup script now
#   verify-backup               decrypt the newest backup and list its contents
#   install-backup              install nas/backup-jobs/budget-backup.sh on the NAS
#   hermes <args...>            run the hermes CLI in the Hermes container (as UID 568)
#   install-guard               create the outbox + install the Hermes delivery script
set -euo pipefail
NAS=truenas_admin@192.168.1.65
[ $# -ge 1 ] || {
  sed -n '2,15p' "$0"
  exit 2
}

# Build the root-side script locally: only fixed verbs, args are %q-quoted.
case "$1" in
status)
  body='docker ps -a --format "{{.Names}}\t{{.Status}}" | grep "^ix-budget-" ; echo; docker logs --tail 30 ix-budget-worker-1 2>&1'
  ;;
logs)
  svc=${2:?service}
  n=${3:-100}
  [[ "$svc" =~ ^[a-z-]+$ && "$n" =~ ^[0-9]+$ ]] || {
    echo "bad args" >&2
    exit 2
  }
  body="docker logs --tail $n ix-budget-$svc-1 2>&1"
  ;;
cli)
  shift
  body="docker exec ix-budget-worker-1 node dist/cli.js $(printf '%q ' "$@") 2>&1 | grep -v -e '^\[Breadcrumb\]' -e '^Syncing since' -e '^Got messages'"
  ;;
sql)
  # Read-only query against the Postgres mirror (derived data, no secrets).
  q=${2:?query}
  body="docker exec -e PGOPTIONS='-c default_transaction_read_only=on' ix-budget-budget-db-1 psql -U budget -d budget -P pager=off -c $(printf '%q' "$q") 2>&1"
  ;;
backup)
  body='/mnt/bulk/backups/.scripts/budget-backup.sh 2>&1'
  ;;
verify-backup)
  # Decrypt the newest backup and list it (restore-drill smoke test).
  body='f=$(ls -t /mnt/bulk/backups/budget/budget-data-*.gpg | head -1); echo "$f"; gpg --batch --quiet --decrypt --passphrase-file /mnt/bulk/backups/.secrets/dump-passphrase "$f" | tar -tzvf - ; echo; du -sh /mnt/fast/databases/budget/actual-data; ls -la /mnt/fast/databases/budget/actual-data'
  ;;
install-backup)
  # Install the committed nas/backup-jobs/budget-backup.sh (root 0700).
  b64=$(base64 -w0 "$(dirname "$0")/../backup-jobs/budget-backup.sh")
  body="echo $b64 | base64 -d > /mnt/bulk/backups/.scripts/budget-backup.sh && chmod 700 /mnt/bulk/backups/.scripts/budget-backup.sh && ls -l /mnt/bulk/backups/.scripts/budget-backup.sh"
  ;;
hermes)
  shift
  body="docker exec -u 568 ix-hermes-agent-hermes-agent-1 hermes $(printf '%q ' "$@") 2>&1"
  ;;
install-guard)
  # Outbox lives inside Hermes's data dataset so both apps (UID 568) see it.
  b64=$(base64 -w0 "$(dirname "$0")/hermes/budget_outbox.py")
  d=/mnt/fast/databases/hermes/data
  body="install -d -o 568 -g 568 -m 750 $d/budget $d/budget/pending $d/budget/sent $d/scripts && echo $b64 | base64 -d > $d/scripts/budget_outbox.py && chown 568:568 $d/scripts/budget_outbox.py && chmod 644 $d/scripts/budget_outbox.py && ls -ld $d/budget $d/budget/pending $d/scripts/budget_outbox.py"
  ;;
*)
  echo "unknown command $1" >&2
  exit 2
  ;;
esac

ssh "$NAS" "BODY=$(printf '%q' "$body")"' bash -s' <<'REMOTE'
set -euo pipefail
STAGE=$(mktemp -d -p ~)
chmod 700 "$STAGE"
printf '%s\n' "set -o pipefail" "$BODY" > "$STAGE/run.sh"
chmod 600 "$STAGE/run.sh"
CMD="bash $STAGE/run.sh > $STAGE/out 2>&1; chown truenas_admin $STAGE/out"
ID=$(midclt call cronjob.create "$(jq -nc --arg c "$CMD" '{user:"root",command:$c,enabled:false,schedule:{minute:"0",hour:"0",dom:"1",month:"1",dow:"*"}}')" | jq .id)
midclt call -j cronjob.run "$ID" >/dev/null 2>&1 || true
midclt call cronjob.delete "$ID" >/dev/null
cat "$STAGE/out" 2>/dev/null || echo "(no output)"
rm -rf "$STAGE"
REMOTE
