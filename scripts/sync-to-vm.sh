#!/usr/bin/env bash
set -euo pipefail

VM_USER="${VM_USER:-ubuntu}"
VM_HOST="${VM_HOST:-192.168.64.2}"
SRC="${SRC:-/Users/kazeru2806/Documents/GitHub/vn-party-thesis/}"
DEST="${VM_USER}@${VM_HOST}:~/vn-party-thesis/"

rsync -avz --delete \
  --exclude 'node_modules' \
  --exclude '_build' \
  --exclude 'deps' \
  --exclude '.git' \
  --exclude 'priv/static/assets' \
  "$SRC" "$DEST"

echo "Synced to ${DEST}. On VM: cd ~/vn-party-thesis/backend && mix deps.get && mix phx.server"
