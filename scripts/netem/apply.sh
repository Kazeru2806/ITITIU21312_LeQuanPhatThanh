#!/usr/bin/env bash
set -euo pipefail

IFACE="${IFACE:-eth0}"
SCENARIO="${1:-baseline}"

clear_qdisc() {
  sudo tc qdisc del dev "$IFACE" root 2>/dev/null || true
}

case "$SCENARIO" in
  baseline)
    clear_qdisc
    echo "netem: cleared (baseline) on $IFACE"
    ;;
  light)
    clear_qdisc
    sudo tc qdisc add dev "$IFACE" root netem delay 50ms 10ms distribution normal loss 5%
    echo "netem: light (50ms base, 10ms jitter, 5% loss) on $IFACE"
    ;;
  moderate)
    clear_qdisc
    sudo tc qdisc add dev "$IFACE" root netem delay 100ms 15ms distribution normal loss 10%
    echo "netem: moderate (100ms base, 15ms jitter, 10% loss) on $IFACE"
    ;;
  heavy)
    clear_qdisc
    sudo tc qdisc add dev "$IFACE" root netem delay 150ms 20ms distribution normal loss 15%
    echo "netem: heavy (150ms base, 20ms jitter, 15% loss) on $IFACE"
    ;;
  *)
    echo "Unknown scenario: $SCENARIO"
    echo "Usage: $0 {baseline|light|moderate|heavy}"
    exit 2
    ;;
esac

