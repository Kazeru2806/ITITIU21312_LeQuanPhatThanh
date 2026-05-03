#!/usr/bin/env bash
set -euo pipefail

IFACE="${IFACE:-eth0}"
sudo tc qdisc del dev "$IFACE" root 2>/dev/null || true
echo "netem: cleared on $IFACE"

