#!/usr/bin/env bash
# Test suite for guard-bash.py. Run before touching ~/.claude/settings.json.
# False positives are the real danger here — a guard that blocks legitimate
# work gets disabled, and then it protects nothing.
set -uo pipefail

GUARD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/guard-bash.py"
PASS=0
FAIL=0

check() { # check <expect: block|allow> <command>
  local expect="$1" cmd="$2" rc
  printf '%s' "$(python3 -c '
import json,sys
print(json.dumps({"tool_name":"Bash","cwd":"/","tool_input":{"command":sys.argv[1]}}))' "$cmd")" \
    | python3 "$GUARD" >/dev/null 2>&1
  rc=$?
  local got="allow"; [ "$rc" = "2" ] && got="block"
  if [ "$got" = "$expect" ]; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    printf '  FAIL expected=%-5s got=%-5s : %s\n' "$expect" "$got" "$cmd"
  fi
}

echo "== must BLOCK =="
check block 'git push --force origin main'
check block 'git push -f origin main'
check block 'git push --force-with-lease'
check block 'cd /repo && git push --force'
check block 'git push origin +main:main'
check block 'git push https://github.com/gOOrcio/mati-lab.git main'
check block 'git push github main'
check block 'cat /root/.backup-env'
check block 'cat network/mapa/.env.example network/mapa/.env'
check block 'cat .env.local'
check block 'grep TOKEN network/mapa/.env.production'
check block 'cat network/caddy/.env'
check block 'grep LITELLM /mnt/fast/databases/hermes/.env'
check block 'ssh truenas_admin@192.168.1.65 "cat /mnt/fast/databases/litellm/.env"'
check block 'head -5 ~/.ssh/id_ed25519'
check block 'awk -F= "{print \$2}" /root/.backup-env'
check block 'cat /mnt/bulk/backups/.secrets/dump-passphrase'
check block 'cat ~/.config/act_runner/.runner'
check block 'grep -c mati-lab /root/.backup-env'
check block 'cat compute/gitea_runner_vm/group_vars/all/vault.yml'
check block 'base64 network/authelia/data/oidc.key'
check block 'cat /opt/mati-lab/network/alertmanager/ntfy-token'

echo "== must BLOCK: process/env dumps (2026-09-06 key-leak class) =="
check block 'pgrep -af git'
check block 'pgrep -a claude'
check block 'ps aux'
check block 'ps -ef | grep claude'
check block 'ps auxww'
check block 'cat /proc/14926/environ'
check block 'cat /proc/self/cmdline'

echo "== must ALLOW (false positives are worse than misses) =="
check allow 'pgrep -f claude'
check allow 'pidof ollama'
check allow 'ps -o pid,etime,comm -p 14926'
check allow 'systemctl status fail2ban'
check allow 'git push origin main'
check allow 'git push -u origin feature-branch'
check allow 'git push origin main && rm -f /tmp/scratch'
check allow 'rm -f /tmp/foo'
check allow 'git pull --rebase origin main'
check allow 'git log --oneline -5'
check allow 'ls -la network/caddy/.env'
check allow 'stat -c %a /mnt/bulk/backups/.secrets/dump-passphrase'
check allow "sed -E 's/=.*/=<redacted>/' /opt/mati-lab/network/authelia/.env"
check allow 'cat network/caddy/Caddyfile'
check allow 'grep -n listen network/caddy/Caddyfile'
check allow 'cat docs/followups.md'
check allow 'curl -H "Authorization: Bearer $(cat tokenfile)" http://localhost:8093/x'
check allow 'docker logs --since 24h caddy | grep -i error'
check allow 'find . -name "*.env" -newer /tmp/x'
check allow 'chmod 600 /root/.backup-env'
check allow 'install -m 600 /tmp/new.env /mnt/fast/databases/x/.env'
check allow 'git remote -v'
check allow 'ssh gooral@192.168.1.252 "docker ps -a"'
check allow 'wc -l docs/followups.md'
check allow 'cat network/mapa/.env.example'
check allow 'grep -n KEY nas/litellm/.env.sample'
check allow "cat > network/mapa/.env.example <<'EOF'"
check allow 'head .env.template'

echo "== GitHub push: target resolved via git remotes (NON_MIRRORED_GITHUB allowlist) =="
check_in() { # check_in <expect> <cwd> <command>
  local expect="$1" dir="$2" cmd="$3" rc
  python3 -c '
import json,sys
print(json.dumps({"tool_name":"Bash","cwd":sys.argv[2],"tool_input":{"command":sys.argv[1]}}))' "$cmd" "$dir" \
    | python3 "$GUARD" >/dev/null 2>&1
  rc=$?
  local got="allow"; [ "$rc" = "2" ] && got="block"
  if [ "$got" = "$expect" ]; then PASS=$((PASS+1)); else
    FAIL=$((FAIL+1)); printf '  FAIL expected=%-5s got=%-5s : (in %s) %s\n' "$expect" "$got" "$dir" "$cmd"; fi
}
T="$(mktemp -d)"
GITEA_WARA=ssh://git@gitea-ssh.mati-lab.online:30009/gooral/wara-portfolio.git
GH=https://github.com
git init -q "$T/client" && git -C "$T/client" remote add origin "$GITEA_WARA" \
  && git -C "$T/client" remote add github "$GH/wargovsky/portfolio.git"
git init -q "$T/moved" && git -C "$T/moved" remote add origin "$GH/wargovsky/portfolio.git" \
  && git -C "$T/moved" remote add gitea "$GITEA_WARA"
git init -q "$T/mirrored" && git -C "$T/mirrored" remote add origin "$GH/gOOrcio/mati-lab.git" \
  && git -C "$T/mirrored" remote add gitea git@gitea-ssh.mati-lab.online:gooral/mati-lab.git
git init -q "$T/thirdparty" && git -C "$T/thirdparty" remote add origin git@github.com:someone/else.git
check_in allow "$T/client"     'git push github main'
check_in allow "$T/client"     'git push -u github fix/x'
check_in allow "$T/client"     'git push https://github.com/wargovsky/portfolio.git main'
check_in allow "$T/client"     'git push origin main'
check_in allow "$T/moved"      'git push origin main'
check_in allow "$T/moved"      'git push'
check_in block "$T/moved"      'git push --force origin main'
check_in block "$T/client"     'git push https://github.com/gOOrcio/mati-lab.git main'
check_in block "$T/mirrored"   'git push origin main'
check_in block "$T/mirrored"   'git push'
check_in block "/"             "cd $T/mirrored && git push origin main"
check_in allow "$T/thirdparty" 'git push origin main'
check_in allow "$T/client"     "git -C $T/client push github main"
# bypass attempts (security review 2026-10-14): text rule must stay the floor
check_in block "$T/client"     'git push --repo=https://github.com/gOOrcio/mati-lab.git'
check_in block "$T/client"     'git push -o ci.skip github main'
check_in block "$T/client"     'git -c remote.github.pushurl=x push github main'
check_in block "$T/client"     'git push https://github.com/wargovsky/portfolio.git/../../gOOrcio/mati-lab.git main'
check_in block "$T/client"     'git push https://evil.example/github.com/wargovsky/portfolio.git main'
git -C "$T/client" remote add both "$GH/wargovsky/portfolio.git" \
  && git -C "$T/client" remote set-url --add --push both "$GH/wargovsky/portfolio.git" \
  && git -C "$T/client" remote set-url --add --push both "$GH/gOOrcio/mati-lab.git"
check_in block "$T/client"     'git push both main'
check_in block "$T/client"     'git push github main https://github.com/gOOrcio/mati-lab.git'
rm -rf "$T"

echo "== fail-open wrapper (python3 exits 2 on a missing file, which would"
echo "   otherwise read as BLOCK and wedge every Bash call) =="
WRAP_MISSING='if [ -r "/nonexistent/guard.py" ]; then exec python3 "/nonexistent/guard.py"; else exit 0; fi'
echo '{"tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}' \
  | sh -c "$WRAP_MISSING" >/dev/null 2>&1
if [ $? -eq 0 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "  FAIL missing-script wrapper did not fail open"; fi

WRAP_PRESENT="if [ -r \"$GUARD\" ]; then exec python3 \"$GUARD\"; else exit 0; fi"
echo '{"tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}' \
  | sh -c "$WRAP_PRESENT" >/dev/null 2>&1
if [ $? -eq 2 ]; then PASS=$((PASS+1)); else FAIL=$((FAIL+1)); echo "  FAIL present-script wrapper did not block"; fi

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
