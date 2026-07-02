#!/usr/bin/env bash
# L2TP client for the RTX test harness. Runs INSIDE the client node.
# Usage: l2tp.sh <raw|ipsec> <tunnel_ip> <psk> <user> <pass>
# Prints CLIENT_IP=... and a final L2TP_OK / L2TP_FAIL line.
set -u
MODE="$1"; TUNNEL_IP="$2"; PSK="$3"; USER="$4"; PASS="$5"
GW=198.19.0.1

cleanup() { pkill xl2tpd 2>/dev/null; ipsec stop >/dev/null 2>&1; sleep 1; }
cleanup

# ---- IPsec layer (only for L2TP/IPsec) ----
if [ "$MODE" = ipsec ]; then
  cat > /etc/ipsec.conf <<EOF
config setup
  uniqueids=no
conn rtx
  keyexchange=ikev1
  authby=secret
  type=transport
  left=%defaultroute
  leftprotoport=17/1701
  right=$TUNNEL_IP
  rightprotoport=17/1701
  auto=add
EOF
  echo ": PSK \"$PSK\"" > /etc/ipsec.secrets
  ipsec restart >/dev/null 2>&1
  # wait for charon to accept commands
  for _ in $(seq 1 15); do ipsec status >/dev/null 2>&1 && break; sleep 1; done
  ok=0
  for _ in 1 2 3; do
    if ipsec up rtx >/tmp/ipsec.log 2>&1 && grep -qiE 'connection.*established|IKE_SA.*established|success' /tmp/ipsec.log; then ok=1; break; fi
    sleep 2
  done
  [ $ok -eq 1 ] || { echo "L2TP_FAIL (ipsec up)"; tail -10 /tmp/ipsec.log; exit 1; }
fi

# ---- L2TP (xl2tpd) + PPP ----
mkdir -p /etc/xl2tpd /etc/ppp /var/run/xl2tpd
cat > /etc/xl2tpd/xl2tpd.conf <<EOF
[lac rtx]
lns = $TUNNEL_IP
pppoptfile = /etc/ppp/options.l2tpd.client
length bit = yes
EOF
cat > /etc/ppp/options.l2tpd.client <<EOF
ipcp-accept-local
ipcp-accept-remote
refuse-eap
require-mschap-v2
noccp
noauth
mtu 1280
mru 1280
noipdefault
usepeerdns
connect-delay 5000
user "$USER"
password "$PASS"
EOF

# Dial with retries: L2TP/PPP negotiation over a freshly-built IPsec SA can be
# racy (first control packets may be dropped before the SA is fully installed),
# so re-dial a few times before giving up.
IP=""
for attempt in 1 2 3; do
  pkill xl2tpd 2>/dev/null; sleep 1
  rm -f /var/run/xl2tpd/l2tp-control
  xl2tpd -D >/var/log/xl2tpd.log 2>&1 &
  for _ in $(seq 1 15); do [ -p /var/run/xl2tpd/l2tp-control ] && break; sleep 1; done
  [ -p /var/run/xl2tpd/l2tp-control ] || { sleep 2; continue; }

  echo "c rtx" > /var/run/xl2tpd/l2tp-control
  for _ in $(seq 1 20); do
    IP=$(ip -4 -o addr show ppp0 2>/dev/null | awk '{print $4}' | head -1)
    [ -n "$IP" ] && break
    # if the LAC gave up early, re-dial
    grep -qiE 'Connection closed|Terminating pppd|Maximum retries' /var/log/xl2tpd.log 2>/dev/null && break
    sleep 1
  done
  [ -n "$IP" ] && break
  echo "L2TP dial attempt $attempt failed; retrying..." >&2
done
[ -z "$IP" ] && { echo "L2TP_FAIL (no ppp lease)"; tail -15 /var/log/xl2tpd.log; exit 1; }

# Full tunnel via ppp0 (keep the transport route to the server on eth0).
SRV_ROUTE=$(ip route get "$TUNNEL_IP" 2>/dev/null | head -1)
ip route replace default dev ppp0
echo "CLIENT_IP=$IP"
echo "L2TP_OK"
