#!/usr/bin/env bash
# RTX-VPN full end-to-end test harness (rootful podman).
#
#   sudo test/run.sh <distro-key> [--keep] [--protocols ovpn,l2tp-raw,l2tp-ipsec]
#
# Brings up exit + tunnel + edge + client, installs RTX-VPN headlessly on the
# tunnel and edge (on <distro-key>), then drives real VPN client connections and
# checks the data path egresses via the edge with no DNS leak.
set -u

DISTRO="${1:-debian12}"; shift || true
KEEP=0
PROTOCOLS="ovpn,l2tp-raw,l2tp-ipsec"
while [ $# -gt 0 ]; do
  case "$1" in
    --keep) KEEP=1 ;;
    --protocols) shift; PROTOCOLS="$1" ;;
    *) echo "unknown arg: $1"; exit 2 ;;
  esac; shift
done

REPO="$(cd "$(dirname "$0")/.." && pwd)"
IMG="rtx-test:$DISTRO"
CLIENT_IMG="rtx-test:client"
NET=rtxnet; EXTNET=rtxext
SE_ADMIN=admin123; SE_PSK=vpnpsk; VPN_USER=rtxvpn; VPN_PASS=rtxpass
GREEN=$'\e[32m'; RED=$'\e[31m'; YEL=$'\e[33m'; NC=$'\e[0m'

S(){ podman "$@"; }                       # already run under sudo
pex(){ local c="$1"; shift; podman exec "$c" "$@"; }

declare -A RESULT
pass(){ RESULT[$1]=PASS; echo "  ${GREEN}PASS${NC} $1"; }
fail(){ RESULT[$1]=FAIL; echo "  ${RED}FAIL${NC} $1 ${2:+- $2}"; }

# --- distro -> base image + Containerfile ---
base_of(){ case "$1" in
  debian12) echo "debian:12 Containerfile.debian" ;;
  debian13) echo "debian:13 Containerfile.debian" ;;
  ubuntu22) echo "ubuntu:22.04 Containerfile.debian" ;;
  ubuntu24) echo "ubuntu:24.04 Containerfile.debian" ;;
  ubuntu26) echo "ubuntu:26.04 Containerfile.debian" ;;
  fedora)   echo "fedora:latest Containerfile.dnf" ;;
  alma)     echo "almalinux:latest Containerfile.dnf" ;;
  arch)     echo "archlinux:latest Containerfile.arch" ;;
  *) echo ""; ;; esac; }

wait_systemd(){ local c="$1" i s
  for i in $(seq 1 30); do
    s=$(pex "$c" systemctl is-system-running 2>/dev/null)
    case "$s" in running|degraded) return 0;; esac; sleep 2
  done; return 1; }

build_image(){
  local spec base cf; spec=$(base_of "$DISTRO"); base=${spec% *}; cf=${spec#* }
  [ -z "$spec" ] && { echo "unknown distro $DISTRO"; exit 2; }
  echo "==> building $IMG from $base"
  S build -q --build-arg BASE="$base" -t "$IMG" -f "$REPO/test/images/$cf" "$REPO/test" >/dev/null || {
    echo "${RED}image build failed (base $base may be unavailable)${NC}"; exit 3; }
  S image exists "$CLIENT_IMG" || {
    echo "==> building $CLIENT_IMG"
    S build -q -t "$CLIENT_IMG" -f "$REPO/test/images/Containerfile.client" "$REPO/test" >/dev/null; }
}

teardown(){ S rm -f rtx_tunnel rtx_edge rtx_exit rtx_client >/dev/null 2>&1; }

echo "######## RTX-VPN e2e: distro=$DISTRO protocols=$PROTOCOLS ########"
build_image
teardown
S network create "$NET"    >/dev/null 2>&1 || true
S network create "$EXTNET" >/dev/null 2>&1 || true

# ---- boot nodes ----
echo "==> booting nodes"
S run -d --name rtx_exit   --network "$EXTNET" "$CLIENT_IMG" sleep infinity >/dev/null
CACHE="$REPO/test/cache"; mkdir -p "$CACHE"
S run -d --name rtx_tunnel --network "$NET" --systemd=always --privileged --device /dev/net/tun -v "$REPO:/repo:ro" -v "$CACHE:/cache:rw" "$IMG" >/dev/null
S run -d --name rtx_edge   --network "$NET" --systemd=always --privileged --device /dev/net/tun -v "$REPO:/repo:ro" -v "$CACHE:/cache:rw" "$IMG" >/dev/null
S run -d --name rtx_client --network "$NET" --privileged --device /dev/net/tun "$CLIENT_IMG" >/dev/null
S network connect "$EXTNET" rtx_edge >/dev/null

for n in rtx_tunnel rtx_edge; do
  wait_systemd "$n" || { fail "boot:$n"; }
done

TUN_IP=$(S inspect -f "{{.NetworkSettings.Networks.${NET}.IPAddress}}" rtx_tunnel)
EDGE_EXT=$(S inspect -f "{{.NetworkSettings.Networks.${EXTNET}.IPAddress}}" rtx_edge)
EXIT_EXT=$(S inspect -f "{{.NetworkSettings.Networks.${EXTNET}.IPAddress}}" rtx_exit)
echo "    TUN_IP=$TUN_IP EDGE_EXT=$EDGE_EXT EXIT_EXT=$EXIT_EXT"

# exit-node: source-IP echo server on :80
pex rtx_exit pkill -f BaseHTTP 2>/dev/null || true
podman exec -d rtx_exit python3 -c "
import http.server,socketserver
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(s):
        ip=s.client_address[0].encode(); s.send_response(200); s.send_header('Content-Length',str(len(ip))); s.end_headers(); s.wfile.write(ip)
    def log_message(s,*a): pass
socketserver.TCPServer(('0.0.0.0',80),H).serve_forever()" >/dev/null

# ---- install tunnel ----
echo "==> installing tunnel ($DISTRO)"
if pex rtx_tunnel env RTX_ROLE=tunnel RTX_NONINTERACTIVE=1 RTX_LOCAL_REPO=/repo RTX_CACHE=/cache \
     RTX_SE_ADMIN_PASS=$SE_ADMIN RTX_SE_PSK=$SE_PSK RTX_VPN_USER=$VPN_USER RTX_VPN_PASS=$VPN_PASS \
     bash /repo/rtxvpn_v2.sh >/tmp/rtx_tun_install.log 2>&1; then
  UUID=$(pex rtx_tunnel cat /opt/rtxvpn_v2/tunnel/.uuid 2>/dev/null)
  [ -n "$UUID" ] && pass "install:tunnel" || fail "install:tunnel" "no uuid"
else
  fail "install:tunnel" "installer exit"; tail -15 /tmp/rtx_tun_install.log
fi

# tunnel service/interface checks
for chk in softether rtxvpn dnsmasq; do
  [ "$(pex rtx_tunnel systemctl is-active $chk 2>/dev/null)" = active ] && pass "svc:$chk" || fail "svc:$chk"
done
pex rtx_tunnel ip link show tap_softether >/dev/null 2>&1 && pass "iface:tap_softether" || fail "iface:tap_softether"
pex rtx_tunnel ip link show rtx >/dev/null 2>&1 && pass "iface:rtx" || fail "iface:rtx"

# ---- install edge ----
echo "==> installing edge ($DISTRO)"
if pex rtx_edge env RTX_ROLE=edge RTX_NONINTERACTIVE=1 RTX_LOCAL_REPO=/repo RTX_CACHE=/cache \
     RTX_UUID="${UUID:-}" RTX_TUNNEL_IP="$TUN_IP" \
     bash /repo/rtxvpn_v2.sh >/tmp/rtx_edge_install.log 2>&1; then
  pass "install:edge"
else
  fail "install:edge"; tail -15 /tmp/rtx_edge_install.log
fi
sleep 6
pex rtx_tunnel bash -c "ss -tlnp | grep -q ':7082'" && pass "rathole:tunnel-up" || fail "rathole:tunnel-up"

# ---- socks-chain proof (tunnel -> edge egress) ----
OUT=$(pex rtx_tunnel curl -s --max-time 15 --socks5-hostname 127.0.0.1:10808 "http://$EXIT_EXT/" 2>/dev/null)
[ "$OUT" = "$EDGE_EXT" ] && pass "dataplane:socks-egress-via-edge" || fail "dataplane:socks-egress-via-edge" "saw '$OUT' want $EDGE_EXT"

# ---- client setup ----
cp "$REPO/test/client/openvpn.sh" /tmp/ovpn.sh; cp "$REPO/test/client/l2tp.sh" /tmp/l2tp.sh
S cp /tmp/ovpn.sh rtx_client:/root/openvpn.sh
S cp /tmp/l2tp.sh rtx_client:/root/l2tp.sh

# build the OpenVPN client config from the server's generated sample
pex rtx_tunnel bash -c "cd /tmp && rm -rf ovpn ovpn.zip && /opt/rtxvpn_v2/tunnel/vpnserver/vpncmd localhost /SERVER /PASSWORD:$SE_ADMIN /CMD OpenVpnMakeConfig ovpn.zip >/dev/null 2>&1 && mkdir -p ovpn && cd ovpn && unzip -oq /tmp/ovpn.zip"
pex rtx_tunnel bash -c 'cat /tmp/ovpn/*l2.ovpn' > /tmp/client.ovpn
sed -i "s/^remote .*/remote $TUN_IP 1194/" /tmp/client.ovpn
cat >> /tmp/client.ovpn <<EOF

data-ciphers AES-128-CBC:AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305
data-ciphers-fallback AES-128-CBC
auth-user-pass /etc/rtx-creds
auth-nocache
connect-retry-max 3
verb 3
EOF
S cp /tmp/client.ovpn rtx_client:/etc/client.ovpn
printf '%s@VPN\n%s\n' "$VPN_USER" "$VPN_PASS" > /tmp/creds && S cp /tmp/creds rtx_client:/etc/rtx-creds

# ---- per-protocol dataplane + DNS-leak ----
reset_client(){
  pex rtx_client bash -c "pkill -f 'openvpn --config' 2>/dev/null; pkill xl2tpd 2>/dev/null; ipsec stop >/dev/null 2>&1;
    for i in ppp0 tap0; do ip link del \$i 2>/dev/null; done;
    ip route replace default via \$(ip route | awk '/default/{print \$3; exit}') 2>/dev/null; true" 2>/dev/null || true
  sleep 2
}

run_protocol(){  # <label> <connect-cmd...>
  local label="$1"; shift
  reset_client
  echo "==> protocol: $label"
  local log; log=$(pex rtx_client bash -c "$*" 2>&1)
  if ! echo "$log" | grep -qE 'OVPN_OK|L2TP_OK'; then
    fail "connect:$label" "$(echo "$log" | tail -3 | tr '\n' '|')"; return
  fi
  pass "connect:$label"
  local cip; cip=$(echo "$log" | grep -oE 'CLIENT_IP=[0-9./]+' | cut -d= -f2)
  echo "    client got $cip"
  # egress check: client -> exit must be seen as coming from the edge.
  # Retry a few times: the first packets warm up the tun2socks/xray/rathole chain.
  local out=""
  for _ in 1 2 3 4 5; do
    out=$(pex rtx_client curl -s --max-time 12 "http://$EXIT_EXT/" 2>/dev/null)
    [ "$out" = "$EDGE_EXT" ] && break
    sleep 2
  done
  [ "$out" = "$EDGE_EXT" ] && pass "egress:$label" || fail "egress:$label" "saw '$out' want $EDGE_EXT"
  # DNS-leak check: capture eth0 while resolving; no plaintext :53 must leave eth0
  pex rtx_client bash -c "timeout 8 tcpdump -ni eth0 -c 1 'udp port 53' >/tmp/leak.txt 2>/dev/null & sleep 1; \
     nslookup example.com >/dev/null 2>&1; getent hosts example.com >/dev/null 2>&1; sleep 2" 2>/dev/null
  if pex rtx_client bash -c "grep -q '.' /tmp/leak.txt 2>/dev/null"; then
    fail "dnsleak:$label" "plaintext DNS on eth0"
  else
    pass "dnsleak:$label"
  fi
}

case ",$PROTOCOLS," in *,ovpn,*) run_protocol "openvpn" "bash /root/openvpn.sh";; esac
case ",$PROTOCOLS," in *,l2tp-raw,*)   run_protocol "l2tp-raw"   "bash /root/l2tp.sh raw   $TUN_IP $SE_PSK $VPN_USER $VPN_PASS";; esac
case ",$PROTOCOLS," in *,l2tp-ipsec,*) run_protocol "l2tp-ipsec" "bash /root/l2tp.sh ipsec $TUN_IP $SE_PSK $VPN_USER $VPN_PASS";; esac

# ---- summary ----
echo ""; echo "######## SUMMARY ($DISTRO) ########"
fails=0
for k in $(printf '%s\n' "${!RESULT[@]}" | sort); do
  printf '  %-34s %s\n' "$k" "${RESULT[$k]}"
  [ "${RESULT[$k]}" = FAIL ] && fails=$((fails+1))
done
echo "  ---- $([ $fails -eq 0 ] && echo "${GREEN}ALL PASS${NC}" || echo "${RED}$fails FAILED${NC}") ----"

[ $KEEP -eq 0 ] && teardown
exit $fails
