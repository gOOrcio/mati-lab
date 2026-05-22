#!/usr/bin/env bash
# Send a Wake-on-LAN magic packet to the Proxmox host.
# Runs from any LAN/VPN-connected machine with python3 — no extra packages needed.
#
# Usage:
#   wake.sh                       # uses PROXMOX_MAC from env or the default below
#   wake.sh aa:bb:cc:dd:ee:ff     # explicit MAC
#   PROXMOX_BROADCAST=192.168.1.255 wake.sh   # override broadcast (defaults to 255.255.255.255)

set -euo pipefail

MAC="${1:-${PROXMOX_MAC:-}}"
BCAST="${PROXMOX_BROADCAST:-255.255.255.255}"
PORT="${PROXMOX_WOL_PORT:-9}"

if [[ -z "${MAC}" ]]; then
  echo "error: MAC address not provided (positional arg or PROXMOX_MAC env)" >&2
  exit 2
fi

if [[ ! "${MAC}" =~ ^([0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}$ ]]; then
  echo "error: '${MAC}' is not a valid MAC address" >&2
  exit 2
fi

python3 - "$MAC" "$BCAST" "$PORT" <<'PY'
import socket, sys
mac, bcast, port = sys.argv[1], sys.argv[2], int(sys.argv[3])
raw = bytes.fromhex(mac.replace(":", "").replace("-", ""))
packet = b"\xff" * 6 + raw * 16
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
    s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    s.sendto(packet, (bcast, port))
print(f"magic packet sent to {mac} via {bcast}:{port}")
PY
