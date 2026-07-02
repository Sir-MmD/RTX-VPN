#!/usr/bin/env bash
#MmD
# RTX-VPN v2 installer — cross-distro (apt / dnf / pacman), systemd-based.
# Supports interactive use and a headless env-driven mode (see RTX_* vars below).

set -u

# --------------------------------------------------------------------------
# Colors (safe when there is no TTY, e.g. piped installs / CI)
# --------------------------------------------------------------------------
if command -v tput >/dev/null 2>&1 && [ -t 1 ] && [ -n "${TERM:-}" ] && [ "${TERM:-}" != "dumb" ]; then
  GREEN=$(tput setaf 2); RED=$(tput setaf 1); BLUE=$(tput setaf 4)
  GOLD=$(tput setaf 3);  CYAN=$(tput setaf 6); NC=$(tput sgr0)
else
  GREEN=""; RED=""; BLUE=""; GOLD=""; CYAN=""; NC=""
fi

UUID=""

# --------------------------------------------------------------------------
# Headless configuration (all optional; unset => interactive prompts)
#   RTX_ROLE            tunnel | edge | uninstall
#   RTX_NONINTERACTIVE  1 to skip the menu and never prompt
#   RTX_LOCAL_REPO      path to a checkout; copy configs+softether from here
#                       instead of downloading them (used by the test harness)
#   Tunnel:  RTX_SE_ADMIN_PASS RTX_SE_PSK RTX_VPN_USER RTX_VPN_PASS
#   Edge:    RTX_UUID RTX_TUNNEL_IP
# --------------------------------------------------------------------------
RTX_ROLE="${RTX_ROLE:-}"
RTX_NONINTERACTIVE="${RTX_NONINTERACTIVE:-0}"
RTX_LOCAL_REPO="${RTX_LOCAL_REPO:-}"
RTX_SE_ADMIN_PASS="${RTX_SE_ADMIN_PASS:-}"
RTX_SE_PSK="${RTX_SE_PSK:-vpn}"
RTX_VPN_USER="${RTX_VPN_USER:-rtxvpn}"
RTX_VPN_PASS="${RTX_VPN_PASS:-rtxvpn}"
RTX_UUID="${RTX_UUID:-}"
RTX_TUNNEL_IP="${RTX_TUNNEL_IP:-}"
RTX_CACHE="${RTX_CACHE:-}"

# Project mirror (fallback source for tools, and source for config files).
RTX_RAW="https://raw.githubusercontent.com/Sir-MmD/RTX-VPN/v3"

# --------------------------------------------------------------------------
# Third-party tool versions — pinned to the latest release as of 2026-07-02.
# Each tool is fetched from its OFFICIAL source first, and only falls back to
# the copy mirrored under this project's assets/ (RTX_RAW) if that fails.
# --------------------------------------------------------------------------
RATHOLE_VER="v0.5.0"
RATHOLE_BASE="https://github.com/rathole-org/rathole/releases/download/${RATHOLE_VER}"

XRAY_VER="v26.3.27"
XRAY_BASE="https://github.com/XTLS/Xray-core/releases/download/${XRAY_VER}"

TUN2SOCKS_VER="v2.6.0"
TUN2SOCKS_BASE="https://github.com/xjasonlyu/tun2socks/releases/download/${TUN2SOCKS_VER}"

SOFTETHER_VER="v4.44-9807-rtm-2025.04.16"
SOFTETHER_BASE="https://www.softether-download.com/files/softether/${SOFTETHER_VER}-tree/Linux/SoftEther_VPN_Server"
SOFTETHER_X64="softether-vpnserver-${SOFTETHER_VER}-linux-x64-64bit.tar.gz"
SOFTETHER_ARM="softether-vpnserver-${SOFTETHER_VER}-linux-arm64-64bit.tar.gz"
SOFTETHER_X64_URL="${SOFTETHER_BASE}/64bit_-_Intel_x64_or_AMD64/${SOFTETHER_X64}"
SOFTETHER_ARM_URL="${SOFTETHER_BASE}/64bit_-_ARM_64bit/${SOFTETHER_ARM}"

PYTHON_BIN=""

# --------------------------------------------------------------------------
# OS / package-manager abstraction
# --------------------------------------------------------------------------
detect_os() {
  if [ ! -r /etc/os-release ]; then
    echo "${RED}Cannot detect OS (/etc/os-release missing).${NC}"; exit 1
  fi
  # shellcheck disable=SC1091
  . /etc/os-release
  OS_ID="${ID:-}"
  OS_LIKE="${ID_LIKE:-}"
  case "$OS_ID" in
    debian|ubuntu|linuxmint|pop|raspbian|kali|devuan) PKG=apt ;;
    fedora|almalinux|rhel|centos|rocky|ol) PKG=dnf ;;
    arch|manjaro|endeavouros|cachyos|garuda) PKG=pacman ;;
    *)
      case " $OS_LIKE " in
        *debian*|*ubuntu*) PKG=apt ;;
        *rhel*|*fedora*|*centos*) PKG=dnf ;;
        *arch*) PKG=pacman ;;
        *) echo "${RED}Unsupported OS: $OS_ID${NC}"; exit 1 ;;
      esac ;;
  esac
  # dnf vs older yum
  if [ "$PKG" = dnf ] && ! command -v dnf >/dev/null 2>&1 && command -v yum >/dev/null 2>&1; then
    PKG=yum
  fi
  echo "Detected OS: ${GREEN}${OS_ID:-unknown}${NC} (package manager: ${GREEN}${PKG}${NC})"
}

# Map a generic package token to the distro-specific name(s).
map_pkg() {
  case "$1" in
    build)
      case "$PKG" in
        apt) echo "build-essential" ;;
        dnf|yum) echo "gcc gcc-c++ make" ;;
        pacman) echo "base-devel" ;;
      esac ;;
    python)
      case "$PKG" in
        apt) echo "python3" ;;
        dnf|yum) echo "python3" ;;
        pacman) echo "python" ;;
      esac ;;
    iproute)
      case "$PKG" in
        apt) echo "iproute2" ;;
        dnf|yum) echo "iproute" ;;
        pacman) echo "iproute2" ;;
      esac ;;
    iptables)
      case "$PKG" in
        apt) echo "iptables" ;;
        dnf|yum) echo "iptables-nft" ;;
        pacman) echo "iptables-nft" ;;
      esac ;;
    dnsmasq) echo "dnsmasq" ;;
    wget)    echo "wget" ;;
    unzip)   echo "unzip" ;;
    tar)     echo "tar" ;;
    sudo)    echo "sudo" ;;
    *)       echo "$1" ;;
  esac
}

pkg_refresh() {
  case "$PKG" in
    apt)     DEBIAN_FRONTEND=noninteractive apt-get update -y ;;
    dnf|yum) $PKG -y makecache || true ;;
    pacman)  pacman -Sy --noconfirm ;;
  esac
}

pkg_install() {
  local generic names=()
  for generic in "$@"; do
    # shellcheck disable=SC2206
    names+=( $(map_pkg "$generic") )
  done
  echo "Installing: ${CYAN}${names[*]}${NC}"
  case "$PKG" in
    apt)     DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${names[@]}" ;;
    dnf|yum) $PKG install -y "${names[@]}" ;;
    pacman)  pacman -S --noconfirm --needed "${names[@]}" ;;
  esac
}

resolve_python() {
  PYTHON_BIN="$(command -v python3 || command -v python || echo /usr/bin/python3)"
}

# --------------------------------------------------------------------------
# Config / asset acquisition (local checkout when RTX_LOCAL_REPO is set)
# --------------------------------------------------------------------------
fetch_config() {  # fetch_config <dest_dir> <filename>
  local dest="$1" name="$2"
  if [ -n "$RTX_LOCAL_REPO" ] && [ -f "$RTX_LOCAL_REPO/configs/$name" ]; then
    cp -f "$RTX_LOCAL_REPO/configs/$name" "$dest/$name"
  else
    wget -q -O "$dest/$name" "$RTX_RAW/configs/$name"
  fi
}

# Download a third-party tool, preferring its OFFICIAL source and falling back
# to this project's mirror (RTX_RAW/assets) if the official download fails.
# Lookup order:
#   1. RTX_CACHE       - on-disk cache (test/CI, avoids repeated downloads)
#   2. RTX_LOCAL_REPO  - local checkout's assets/ (test harness)
#   3. official URL    - the upstream release (primary source)
#   4. project mirror  - RTX_RAW/assets/<name> (fallback if official is down)
dl() {  # dl <dest_dir> <official_url>
  local dest="$1" url="$2" name; name=$(basename "$url")

  if [ -n "$RTX_CACHE" ] && [ -f "$RTX_CACHE/$name" ]; then
    cp -f "$RTX_CACHE/$name" "$dest/$name"; return 0
  fi
  if [ -n "$RTX_LOCAL_REPO" ] && [ -f "$RTX_LOCAL_REPO/assets/$name" ]; then
    cp -f "$RTX_LOCAL_REPO/assets/$name" "$dest/$name"
  elif wget -q -O "$dest/$name" "$url" && [ -s "$dest/$name" ]; then
    echo "  ${GREEN}✓${NC} $name (official)"
  else
    rm -f "$dest/$name"
    echo "  ${GOLD}!${NC} official source failed for $name; trying project mirror"
    if ! { wget -q -O "$dest/$name" "$RTX_RAW/assets/$name" && [ -s "$dest/$name" ]; }; then
      echo "${RED}Failed to download $name from official source and project mirror.${NC}"
      exit 1
    fi
    echo "  ${GREEN}✓${NC} $name (mirror)"
  fi
  if [ -n "$RTX_CACHE" ]; then
    mkdir -p "$RTX_CACHE" && cp -f "$dest/$name" "$RTX_CACHE/$name" 2>/dev/null || true
  fi
  return 0
}

# --------------------------------------------------------------------------
# Checks
# --------------------------------------------------------------------------
root_check() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as ${RED}root!${NC}"; exit 1
  fi
}

install_check() {
  if [ -d "/opt/rtxvpn_v2/tunnel" ] || [ -d "/opt/rtxvpn_v2/edge" ]; then
    echo "RTX-VPN v2 is already ${GREEN}installed!${NC}"; exit 1
  fi
}

# --------------------------------------------------------------------------
# Downloads
# --------------------------------------------------------------------------
download_edge_files() {
  pkg_refresh
  pkg_install tar sudo wget unzip python iproute

  mkdir -p /opt/rtxvpn_v2/edge || { echo "${RED}Failed to create edge dir${NC}"; exit 1; }
  local d=/opt/rtxvpn_v2/edge
  local arch; arch=$(uname -m)
  case "$arch" in
    x86_64|amd64)
      dl "$d" "${RATHOLE_BASE}/rathole-x86_64-unknown-linux-gnu.zip"
      dl "$d" "${XRAY_BASE}/Xray-linux-64.zip"
      unzip -oq "$d/rathole-x86_64-unknown-linux-gnu.zip" -d "$d"
      unzip -oq "$d/Xray-linux-64.zip" -d "$d" ;;
    aarch64|arm64)
      dl "$d" "${RATHOLE_BASE}/rathole-aarch64-unknown-linux-musl.zip"
      dl "$d" "${XRAY_BASE}/Xray-linux-arm64-v8a.zip"
      unzip -oq "$d/rathole-aarch64-unknown-linux-musl.zip" -d "$d"
      unzip -oq "$d/Xray-linux-arm64-v8a.zip" -d "$d" ;;
    *) echo "${RED}Unsupported CPU architecture: $arch${NC}"; exit 1 ;;
  esac
  fetch_config "$d" edge.json
  fetch_config "$d" edge.toml
  fetch_config "$d" edge.py
  chmod -R +x "$d"
}

download_tunnel_files() {
  pkg_refresh
  pkg_install tar sudo wget unzip dnsmasq iptables build python iproute

  mkdir -p /opt/rtxvpn_v2/tunnel || { echo "${RED}Failed to create tunnel dir${NC}"; exit 1; }
  local d=/opt/rtxvpn_v2/tunnel
  local arch; arch=$(uname -m)
  case "$arch" in
    x86_64|amd64)
      dl "$d" "${RATHOLE_BASE}/rathole-x86_64-unknown-linux-gnu.zip"
      dl "$d" "${TUN2SOCKS_BASE}/tun2socks-linux-amd64.zip"
      dl "$d" "${XRAY_BASE}/Xray-linux-64.zip"
      dl "$d" "${SOFTETHER_X64_URL}"
      unzip -oq "$d/rathole-x86_64-unknown-linux-gnu.zip" -d "$d"
      unzip -oq "$d/tun2socks-linux-amd64.zip" -d "$d"
      unzip -oq "$d/Xray-linux-64.zip" -d "$d"
      tar xf "$d/$SOFTETHER_X64" -C "$d"
      mv -f "$d/tun2socks-linux-amd64" "$d/tun2socks" ;;
    aarch64|arm64)
      dl "$d" "${RATHOLE_BASE}/rathole-aarch64-unknown-linux-musl.zip"
      dl "$d" "${TUN2SOCKS_BASE}/tun2socks-linux-arm64.zip"
      dl "$d" "${XRAY_BASE}/Xray-linux-arm64-v8a.zip"
      dl "$d" "${SOFTETHER_ARM_URL}"
      unzip -oq "$d/rathole-aarch64-unknown-linux-musl.zip" -d "$d"
      unzip -oq "$d/tun2socks-linux-arm64.zip" -d "$d"
      unzip -oq "$d/Xray-linux-arm64-v8a.zip" -d "$d"
      tar xf "$d/$SOFTETHER_ARM" -C "$d"
      mv -f "$d/tun2socks-linux-arm64" "$d/tun2socks" ;;
    *) echo "${RED}Unsupported CPU architecture: $arch${NC}"; exit 1 ;;
  esac
  fetch_config "$d" tunnel.json
  fetch_config "$d" tunnel.toml
  fetch_config "$d" tunnel.py
  chmod -R +x "$d"
}

# --------------------------------------------------------------------------
# SoftEther: build (auto-accept EULA) + service + headless vpncmd config
# --------------------------------------------------------------------------
softether_build() {
  if [ ! -d "/opt/rtxvpn_v2/tunnel/vpnserver" ]; then
    echo "${RED}SoftEther not found!${NC}"; exit 1
  fi
  # The tarball ships precompiled .a archives; `make` only links them.
  # It prints an EULA prompt three times expecting "1"; feed it non-interactively.
  printf '1\n1\n1\n' | make -C /opt/rtxvpn_v2/tunnel/vpnserver >/dev/null 2>&1 || \
    printf '1\n1\n1\n' | make -C /opt/rtxvpn_v2/tunnel/vpnserver
  if [ ! -x /opt/rtxvpn_v2/tunnel/vpnserver/vpnserver ]; then
    echo "${RED}SoftEther build failed!${NC}"; exit 1
  fi

  cat <<EOF > /etc/systemd/system/softether.service
[Unit]
Description=SoftEther VPN Server
After=network.target

[Service]
Type=forking
ExecStart=/opt/rtxvpn_v2/tunnel/vpnserver/vpnserver start
ExecStop=/opt/rtxvpn_v2/tunnel/vpnserver/vpnserver stop
ExecReload=/opt/rtxvpn_v2/tunnel/vpnserver/vpnserver restart
WorkingDirectory=/opt/rtxvpn_v2/tunnel/vpnserver
Restart=always
RestartSec=3
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable softether.service >/dev/null 2>&1
  systemctl restart softether.service

  # Wait for the management API (localhost:443) to answer.
  local V=/opt/rtxvpn_v2/tunnel/vpnserver/vpncmd i
  for i in $(seq 1 30); do
    if "$V" localhost /SERVER /PASSWORD: /CMD About >/dev/null 2>&1; then break; fi
    sleep 1
  done
}

# Replaces the manual SoftEther GUI walkthrough entirely.
softether_configure() {
  local V=/opt/rtxvpn_v2/tunnel/vpnserver/vpncmd

  # 1) Set the server admin password (initial password is empty).
  "$V" localhost /SERVER /PASSWORD: /CMD ServerPasswordSet "$RTX_SE_ADMIN_PASS" >/dev/null 2>&1

  # 2) Everything else in one authenticated batch. vpncmd's /IN: needs a real
  #    file path (it cannot read a pipe such as /dev/stdin), so write a temp file.
  #    - HubCreate VPN                : the Virtual Hub
  #    - IPsecEnable                  : L2TP/IPsec + raw L2TP, default hub VPN, PSK
  #    - OpenVpnEnable                : OpenVPN-compatible listener on udp/1194
  #    - VpnAzureSetEnable no         : disable the Azure relay
  #    - BridgeCreate .. /TAP:yes     : creates kernel iface tap_softether
  #    - Hub VPN / SecureNatDisable   : bridged mode, not SecureNAT
  #    - UserCreate / UserPasswordSet : the VPN login account
  local batch; batch=$(mktemp)
  cat > "$batch" <<EOF
HubCreate VPN /PASSWORD:none
IPsecEnable /L2TP:yes /L2TPRAW:yes /ETHERIP:no /PSK:$RTX_SE_PSK /DEFAULTHUB:VPN
OpenVpnEnable yes /PORTS:1194
VpnAzureSetEnable no
BridgeCreate VPN /DEVICE:softether /TAP:yes
Hub VPN
SecureNatDisable
UserCreate $RTX_VPN_USER /GROUP:none /REALNAME:none /NOTE:none
UserPasswordSet $RTX_VPN_USER /PASSWORD:$RTX_VPN_PASS
EOF
  "$V" localhost /SERVER /PASSWORD:"$RTX_SE_ADMIN_PASS" /IN:"$batch" >/dev/null 2>&1
  rm -f "$batch"

  # Confirm the tap device now exists (SoftEther names it tap_<device>).
  local i
  for i in $(seq 1 15); do
    ip link show tap_softether >/dev/null 2>&1 && break
    sleep 1
  done
  if ! ip link show tap_softether >/dev/null 2>&1; then
    echo "${RED}Warning: tap_softether did not appear; local bridge may have failed.${NC}"
  fi
}

# --------------------------------------------------------------------------
# dnsmasq (DHCP + DNS for VPN clients on tap_softether)
# --------------------------------------------------------------------------
dnsmasq_setup() {
  [ -f /etc/dnsmasq.conf ] && [ ! -f /etc/dnsmasq.conf.backup ] && \
    mv /etc/dnsmasq.conf /etc/dnsmasq.conf.backup
  cat <<EOF > /etc/dnsmasq.conf
interface=tap_softether
bind-interfaces
dhcp-range=tap_softether,198.19.0.2,198.19.0.254,12h
dhcp-option=tap_softether,3,198.19.0.1
dhcp-option=tap_softether,6,8.8.8.8,8.8.4.4
EOF

  # Start dnsmasq only after the tap exists and is configured by rtxvpn.service.
  mkdir -p /etc/systemd/system/dnsmasq.service.d
  cat <<EOF > /etc/systemd/system/dnsmasq.service.d/rtx.conf
[Unit]
After=rtxvpn.service
Requires=rtxvpn.service

[Service]
Restart=always
RestartSec=3
EOF
  systemctl daemon-reload
  systemctl enable dnsmasq >/dev/null 2>&1
  systemctl restart dnsmasq || true
}

# --------------------------------------------------------------------------
# systemd services
# --------------------------------------------------------------------------
tunnel_setup() {
  # Register the "rtx_table" name for readable `ip rule` output. Newer distros
  # (Debian 13, Fedora, Arch) don't ship /etc/iproute2/rt_tables, so create it.
  # PBR itself uses the numeric id 200 and does not depend on this succeeding.
  mkdir -p /etc/iproute2
  if [ ! -f /etc/iproute2/rt_tables ]; then
    if [ -f /usr/lib/iproute2/rt_tables ]; then
      cp /usr/lib/iproute2/rt_tables /etc/iproute2/rt_tables
    else
      printf '255\tlocal\n254\tmain\n253\tdefault\n0\tunspec\n' > /etc/iproute2/rt_tables
    fi
  fi
  grep -q "rtx_table" /etc/iproute2/rt_tables 2>/dev/null || \
    echo "200 rtx_table" >> /etc/iproute2/rt_tables

  cat <<EOF > /etc/systemd/system/rtxvpn.service
[Unit]
Description=RTX-VPN Tunnel Service
After=softether.service
Requires=softether.service
PartOf=softether.service

[Service]
Type=simple
ExecStart=${PYTHON_BIN} /opt/rtxvpn_v2/tunnel/tunnel.py
ExecStop=/bin/kill -SIGINT \$MAINPID
Restart=on-failure
User=root
Group=root
Environment="PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin"
PIDFile=/var/run/vpn-service.pid

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable rtxvpn.service >/dev/null 2>&1
  systemctl restart rtxvpn.service
}

edge_setup() {
  cat <<EOF > /etc/systemd/system/rtxvpn.service
[Unit]
Description=RTX-VPN Edge Service
After=network.target

[Service]
Type=simple
ExecStart=${PYTHON_BIN} /opt/rtxvpn_v2/edge/edge.py
ExecStop=/bin/kill -SIGINT \$MAINPID
Restart=on-failure
User=root
Group=root
Environment="PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin"
PIDFile=/var/run/vpn-service.pid

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable rtxvpn.service >/dev/null 2>&1
  systemctl restart rtxvpn.service
}

# --------------------------------------------------------------------------
# UUID / peering
# --------------------------------------------------------------------------
uuid_tunnel() {
  UUID=$(/opt/rtxvpn_v2/tunnel/xray uuid)
  sed -i "s/\"uuid\"/\"$UUID\"/g" /opt/rtxvpn_v2/tunnel/tunnel.json
  sed -i "s/\"uuid\"/\"$UUID\"/g" /opt/rtxvpn_v2/tunnel/tunnel.toml
  echo "$UUID" > /opt/rtxvpn_v2/tunnel/.uuid
}

uuid_edge() {
  if [ "$RTX_NONINTERACTIVE" != "1" ]; then
    read -rp "Enter UUID: " RTX_UUID
    read -rp "Enter Tunnel IP: " RTX_TUNNEL_IP
  fi
  UUID="$RTX_UUID"
  sed -i "s/\"uuid\"/\"$RTX_UUID\"/g" /opt/rtxvpn_v2/edge/edge.json
  sed -i "s/\"uuid\"/\"$RTX_UUID\"/g" /opt/rtxvpn_v2/edge/edge.toml
  sed -i "s/remote_addr = \".*:[0-9]\+\"/remote_addr = \"$RTX_TUNNEL_IP:7081\"/" /opt/rtxvpn_v2/edge/edge.toml
}

# --------------------------------------------------------------------------
# Uninstall
# --------------------------------------------------------------------------
uninstall() {
  if [ -d "/opt/rtxvpn_v2/tunnel" ]; then
    rm -rf /opt/rtxvpn_v2/tunnel
    systemctl stop dnsmasq 2>/dev/null; systemctl disable dnsmasq 2>/dev/null
    rm -f /etc/systemd/system/dnsmasq.service.d/rtx.conf
    sed -i '/200 rtx_table/d' /etc/iproute2/rt_tables 2>/dev/null
    ip link set dev rtx down 2>/dev/null
    ip tuntap del mode tun dev rtx 2>/dev/null
    ip rule del from 198.19.0.0/24 table 200 priority 10 2>/dev/null
    ip route flush table 200 2>/dev/null
    ip rule del to 8.8.8.8 table main priority 11 2>/dev/null
    ip rule del to 8.8.4.4 table main priority 12 2>/dev/null
    for svc in rtxvpn softether; do
      if [ -f "/etc/systemd/system/$svc.service" ]; then
        systemctl stop $svc 2>/dev/null; systemctl disable $svc 2>/dev/null
        rm -f "/etc/systemd/system/$svc.service"
      fi
    done
    systemctl daemon-reload
    echo "RTX-VPN v2 (Tunnel) has been ${GREEN}removed${NC}"
  fi
  if [ -d "/opt/rtxvpn_v2/edge" ]; then
    rm -rf /opt/rtxvpn_v2/edge
    if [ -f "/etc/systemd/system/rtxvpn.service" ]; then
      systemctl stop rtxvpn 2>/dev/null; systemctl disable rtxvpn 2>/dev/null
      rm -f /etc/systemd/system/rtxvpn.service
    fi
    systemctl daemon-reload
    echo "RTX-VPN v2 (Edge) has been ${GREEN}removed${NC}"
  fi
  if [ ! -d "/opt/rtxvpn_v2/tunnel" ] && [ ! -d "/opt/rtxvpn_v2/edge" ]; then
    echo "RTX-VPN v2 is ${RED}not installed!${NC}"
  fi
}

# --------------------------------------------------------------------------
# High-level flows
# --------------------------------------------------------------------------
do_tunnel() {
  install_check
  detect_os
  resolve_python
  download_tunnel_files
  softether_build
  softether_configure
  uuid_tunnel
  tunnel_setup
  dnsmasq_setup
  echo ""
  echo "${GREEN}Tunnel installed!${NC} Configure the Edge server with this UUID: ${GOLD}$UUID${NC}"
  echo "RTX_UUID=$UUID"
  echo "Check status: ${CYAN}systemctl status rtxvpn softether dnsmasq${NC}"
}

do_edge() {
  install_check
  detect_os
  resolve_python
  download_edge_files
  uuid_edge
  edge_setup
  echo ""
  echo "${GREEN}Edge installed!${NC} Enjoy your ${GOLD}FREEDOM${NC}"
  echo "Check status: ${CYAN}systemctl status rtxvpn${NC}"
}

# --------------------------------------------------------------------------
# Entry point
# --------------------------------------------------------------------------
root_check

# Headless dispatch
if [ "$RTX_NONINTERACTIVE" = "1" ] || [ -n "$RTX_ROLE" ]; then
  case "$RTX_ROLE" in
    tunnel)    do_tunnel ;;
    edge)      do_edge ;;
    uninstall) uninstall ;;
    *) echo "${RED}RTX_ROLE must be tunnel|edge|uninstall${NC}"; exit 1 ;;
  esac
  exit 0
fi

# Interactive menu
clear
echo "${GREEN}  _____ _________   __  __      _______  _   _    "
echo " |  __ \\__   __\\ \\ / /  \\ \\    / /  __ \\| \\ | |   ${NC}"
echo " | |__) | | |   \\ V /${GOLD}____${NC}\\ \\  / /| |__) |  \\| |   "
echo " |  _  /  | |    > <${GOLD}______${NC}\\ \\/ / |  ___/| .   |   ${RED}"
echo " | | \\ \\  | |   / . \\      \\  /  | |    | |\\  |   "
echo " |_|  \\_\\ |_|  /_/ \\_\\  ${GOLD}V2${RED}  \\/   |_|    |_| \\_|   ${NC}"
echo "${CYAN}   SoftEther + Rathole + Tun2socks + Xray${NC}"
echo ""
echo "Choose an option:"
echo "1. Setup Tunnel"
echo "2. Setup Edge"
echo "3. Uninstall"
echo ""
while true; do
  read -rp "Enter your choice (1, 2 or 3): " choice
  case "$choice" in
    1)
      if [ -z "$RTX_SE_ADMIN_PASS" ]; then read -rp "Set SoftEther admin password: " RTX_SE_ADMIN_PASS; fi
      read -rp "Set L2TP/IPsec pre-shared key [${RTX_SE_PSK}]: " _p; RTX_SE_PSK="${_p:-$RTX_SE_PSK}"
      read -rp "Set VPN username [${RTX_VPN_USER}]: " _u; RTX_VPN_USER="${_u:-$RTX_VPN_USER}"
      read -rp "Set VPN user password [${RTX_VPN_PASS}]: " _w; RTX_VPN_PASS="${_w:-$RTX_VPN_PASS}"
      do_tunnel; break ;;
    2) do_edge; break ;;
    3) uninstall; break ;;
    *) echo "Invalid option. Please enter 1, 2, or 3." ;;
  esac
done
