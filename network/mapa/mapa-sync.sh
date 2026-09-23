#!/usr/bin/env bash
# Pull the latest map from gooral/wysowa into /opt/wysowa (sparse: only
# mapa/mapa.html + mapa/podklady/). nginx serves the files straight from
# here, so no container restart is needed.
set -Eeuo pipefail

REPO_DIR=/opt/wysowa
REPO_URL=git@gitea-ssh.mati-lab.online:gooral/wysowa.git
BRANCH=main
PATHS=(/mapa/mapa.html /mapa/podklady/)

if [ ! -d "$REPO_DIR/.git" ]; then
  git clone --quiet --filter=blob:none --no-checkout -b "$BRANCH" "$REPO_URL" "$REPO_DIR"
fi

cd "$REPO_DIR"
# Re-assert the whitelist every run so nothing else can ever be checked out.
git sparse-checkout set --no-cone "${PATHS[@]}"
git fetch --quiet --prune origin "$BRANCH"
before=$(git rev-parse -q --verify HEAD || echo none)
git reset --quiet --hard "origin/$BRANCH"
git clean -fdq
after=$(git rev-parse HEAD)
[ "$before" = "$after" ] || echo "mapa updated ${before:0:7} -> ${after:0:7}"
