#!/usr/bin/env bash
# OpenVPN L2 (tap) client for the RTX test harness. Runs INSIDE the client node.
# Expects /etc/client.ovpn (remote already rewritten) and /etc/rtx-creds.
# Prints CLIENT_IP=... and a final OVPN_OK / OVPN_FAIL line.
set -u
LOG=/var/log/ovpn.log
GW=198.19.0.1

pkill -f 'openvpn --config' 2>/dev/null; sleep 1
rm -f "$LOG"
openvpn --config /etc/client.ovpn --daemon --log "$LOG" --writepid /run/ovpn.pid

# Wait for the tap device OpenVPN creates (exclude tap_softether just in case).
IF=""
for _ in $(seq 1 40); do
  IF=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^tap[0-9]' | head -1)
  [ -n "$IF" ] && break
  if grep -qiE 'AUTH_FAILED|TLS Error|Cannot load|Options error|error=' "$LOG" 2>/dev/null; then
    echo "OVPN_FAIL (handshake)"; tail -6 "$LOG"; exit 1
  fi
  sleep 1
done
[ -z "$IF" ] && { echo "OVPN_FAIL (no tap)"; tail -10 "$LOG"; exit 1; }
ip link set "$IF" up

# Obtain L3 config from dnsmasq on the bridged segment.
dhclient -1 -v "$IF" >/tmp/dhc.log 2>&1 || true
IP=$(ip -4 -o addr show "$IF" | awk '{print $4}' | head -1)
[ -z "$IP" ] && { echo "OVPN_FAIL (no dhcp lease)"; tail -10 /tmp/dhc.log; exit 1; }

# Force full-tunnel: default route via the VPN gateway (transport to the server
# stays on the connected eth0 route, which is more specific).
ip route replace default via "$GW" dev "$IF"

echo "CLIENT_IF=$IF"
echo "CLIENT_IP=$IP"
echo "OVPN_OK"
