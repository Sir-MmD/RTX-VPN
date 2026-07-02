## [English](/README.md) | [فارسی](/README_fa.md)
# RTX-VPN v2 + SoftEther
# L2TP/OpenVPN/SSTP Server with Rathole + Tun2socks + Xray + Tunnel + SoftEther
# RTX-VPN = (Rathole-tun2socks-Xray) VPN
![App Screenshot](https://raw.githubusercontent.com/Sir-MmD/RTX-VPN/refs/heads/v3/menu.png)

## What Does this script do?
This script provides a solution for setting up L2TP/OpenVPN/SSTP server via "SoftEther" and tunnel via "Rathole+Tun2socks+Xray" in restricted locations (e.g., Iran, China).

## Supported Protocols
- L2TP
- L2TP/IPSec
- OpenVPN
- SSTP
- Radius (For Advanced Account Management)

## Diagram
![App Screenshot](https://raw.githubusercontent.com/Sir-MmD/RTX-VPN/refs/heads/v3/diagram.png)

## How does it work?
We need two servers: one for incoming L2TP/OpenVPN/SSTP connections and SoftEther to deploy and the other as the endpoint of our connection. The first server (Tunnel Server) will be considered a server with no limit on incoming L2TP/OpenVPN/SSTP traffic, unlike the Edge Server, which we cannot connect to directly.

The Edge Server establishes the first connection to the Tunnel Server in reverse tunnel(rathole) via a VLESS + WebSocket (WS) configuration from Xray-core, exposing a SOCKS5 proxy on the Tunnel Server. We then use tun2socks to route traffic from the SOCKS5 proxy into a virtual interface.

Finally, we use Policy-Based Routing (PBR) to route SoftEther incoming connections to the tun2socks interface.

## Donate
🔹USDT-TRC20: ```TEUsjU22rAb3TZNaecEBJAhZXQsFZYU7vv```

🔹TRX: ```TEUsjU22rAb3TZNaecEBJAhZXQsFZYU7vv```

🔹LTC: ```LS7rJ6nMWwgw9FWpMjSnYa1bAPdzK7bJLM```

🔹BTC: ```1D4cSHY95FoHExSicKYmjeVzdLLxhjTTqs```

🔹ETH: ```0x03fde84612e0d572db7a18efeeec590ad3fa5dfb```

## Installation Tutorial
https://www.youtube.com/watch?v=TbIPd9ni1PU

## Installation
```bash
sh -c "$(wget https://raw.githubusercontent.com/Sir-MmD/RTX-VPN/v3/rtxvpn_v2.sh -O -)"
```
The **Tunnel** setup now configures SoftEther automatically (Virtual Hub, L2TP/IPsec
+ raw L2TP, OpenVPN listener, the VPN user account and the `tap_softether` local
bridge) via `vpncmd` — no manual SoftEther Server Manager steps are required.

The installer also runs headlessly for automation/CI via environment variables:
```bash
# Tunnel
RTX_ROLE=tunnel RTX_NONINTERACTIVE=1 RTX_SE_ADMIN_PASS=... RTX_SE_PSK=... \
  RTX_VPN_USER=... RTX_VPN_PASS=... ./rtxvpn_v2.sh
# Edge
RTX_ROLE=edge RTX_NONINTERACTIVE=1 RTX_UUID=<from tunnel> RTX_TUNNEL_IP=<tunnel ip> \
  ./rtxvpn_v2.sh
```

## Testing
A full end-to-end test harness lives in [`test/`](test/). Using rootful podman it
brings up a tunnel + edge + client + exit topology, installs RTX-VPN headlessly,
and verifies the data path (traffic egresses via the edge) and DNS-leak safety for
OpenVPN, raw L2TP and L2TP/IPsec — across Debian 12/13, Ubuntu 22/24/26, Fedora,
Arch and AlmaLinux. See [`test/README.md`](test/README.md).
```bash
sudo test/run.sh debian13         # one distro
sudo test/matrix.sh               # all supported distros
```

## Supported OS
This script runs on any systemd-based Linux distribution across the major
package managers:
- **Debian / Ubuntu** and derivatives (`apt`) — incl. Debian 12/13, Ubuntu 22.04/24.04/26.04
- **Fedora / AlmaLinux / RHEL / Rocky** (`dnf`)
- **Arch Linux** and derivatives (`pacman`)

Architectures: `x86_64` and `aarch64`.

## Speedtest
![App Screenshot](https://raw.githubusercontent.com/Sir-MmD/RTX-VPN/refs/heads/v3/speedtest.jpg)

## Fix OpenVPN Connection Error
The OpenVPN client configuration file provided by SoftEther uses an outdated cipher. To fix this issue, please add the following line below ```cipher AES-128-CBC``` in your configuration file:
```bash
data-ciphers AES-128-CBC:AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305
```
Additionally, it is recommended to replace ```remote address``` with your actual IP or personal domain

## Recommended SoftEther Configuration
- Disable DDNS: ```declare DDnsClient: bool Disabled true```
- Disable WebUI: ```bool DisableJsonRpcWebApi true```
- Remove Unnecessary Ports
  
## Tunnel Tweaking: Xray-Core
This script uses 'VLESS + WS' as the default connection for Xray-core. You can configure your desired settings in ```/opt/rtxvpn_v2/edge/edge.json``` for the Edge Server and ```/opt/rtxvpn_v2/tunnel/tunnel.json``` for the Tunnel Server

## Tunnel Tweaking: Rathole
You can also modify the Rathole configuration in ```/opt/rtxvpn_v2/edge/edge.toml``` for the Edge Server and ```/opt/rtxvpn_v2/tunnel/tunnel.toml``` for the Tunnel Server."

## Systemd Services: Edge Server
RTX-VPN (Rathole + Xray): ```rtxvpn.service```

## Systemd Services: Tunnel Server
RTX-VPN (Rathole + Tun2socks + Xray + PBR): ```rtxvpn.service```

SoftEther: ```softether.service```

Dnsmasq: ```dnsmasq.service```

## CopyRight
SoftEther: https://www.softether.org

Rathole: https://github.com/rapiz1/rathole

Tun2socks: https://github.com/bedefaced/vpn-install

Xray-Core: https://github.com/XTLS/Xray-core
