# Please use Version 2: https://github.com/Sir-MmD/RTX-VPN/tree/v2
#
## [English](/README.md) | [فارسی](/README_fa.md)
# L2TP/OpenVPN Server with Xray + Rathole + tun2socks Tunnel
# RTX-VPN = (Rathole-tun2socks-Xray) VPN
![App Screenshot](https://raw.githubusercontent.com/Sir-MmD/RTX-VPN/refs/heads/v1/screenshots/menu.png)
## What Does this script do?
This script provides a solution for setting up and tunneling L2TP/OpenVPN in restricted locations (e.g., Iran, China).

It aims to tunnel traffic via Xray-core in reverse mode (rathole), making the tunnel traffic appear legitimate.

## Diagram:
![App Screenshot](https://raw.githubusercontent.com/Sir-MmD/RTX-VPN/refs/heads/v1/diagram.PNG)

## How does it work?
We need two servers: one for incoming L2TP/OpenVPN connections and the other as the endpoint of our connection. The first server (Tunnel Server) will be considered a server with no limit on incoming L2TP/OpenVPN traffic, unlike the Edge Server, which we cannot connect to directly.

The Edge Server establishes the first connection to the Tunnel Server (reverse tunnel) via a VLESS + WebSocket (WS) configuration from Xray-core, exposing a SOCKS5 proxy on the Tunnel Server. We then use tun2socks to route traffic from the SOCKS5 proxy into a virtual interface.

Finally, we use Policy-Based Routing (PBR) to route incoming L2TP/OpenVPN traffic to the tun2socks interface.

## Donate
🔹USDT-TRC20: ```TEUsjU22rAb3TZNaecEBJAhZXQsFZYU7vv```

🔹TRX: ```TEUsjU22rAb3TZNaecEBJAhZXQsFZYU7vv```

🔹LTC: ```LS7rJ6nMWwgw9FWpMjSnYa1bAPdzK7bJLM```

🔹BTC: ```1D4cSHY95FoHExSicKYmjeVzdLLxhjTTqs```

🔹ETH: ```0x03fde84612e0d572db7a18efeeec590ad3fa5dfb```
## Installation Tutorial
https://youtu.be/Djc6CfClCvM
## Installation
```bash
git clone -b v1 https://github.com/Sir-MmD/RTX-VPN.git
chmod -R +x RTX-VPN
cd RTX-VPN
./rtxvpn_setup.sh
```
## Manage Users
```bash
./rtxvpn_manage.sh
```
## Supported OS
This script can be run on all Debian-based distributions that use systemd
## Tunnel Tweaking: Xray-core
This script uses 'VLESS + WS' as the default connection for Xray-core. You can configure your desired settings in ```/opt/xray_edge.json``` for the Edge Server and ```/opt/xray_tunnel.json``` for the Tunnel Server
## Tunnel Tweaking: rathole
You can also modify the Rathole configuration in ```/opt/rathole_edge.toml``` for the Edge Server and ```/opt/rathole_tunnel.toml``` for the Tunnel Server."
## Important Note
Please DO NOT modify the vpn server ip pool! But if you did, you MUST change the ip pool inside the ```rtxvpn_setup.sh```
## Systemd Services: Tunnel Server
tun2socks L2TP Routing Service: ```tun2socks_l2tp_setup.service```

tun2socks Interface for L2TP Service: ```tun2socks_l2tp_interface.service```

tun2socks OpenVPN Routing Service: ```tun2socks_openvpn_setup.service```

tun2socks Interface for OpenVPN Service: ```tun2socks_openvpn_interface.service```

Xray-Core Tunnel Service: ```xray_tunnel.service```

rathole Tunnel Service: ```rathole_tunnel.service```

## Systemd Services: Edge Server
Xray-Core Edge Service: ```xray_edge.service```

rathole Edge Service: ```rathole_edge.service```

## Speedtest: L2TP
![App Screenshot](https://raw.githubusercontent.com/Sir-MmD/RTX-VPN/refs/heads/v1/screenshots/l2tp/speedtest.jpg)
## Speedtest: OpenVPN
![App Screenshot](https://raw.githubusercontent.com/Sir-MmD/RTX-VPN/refs/heads/v1/screenshots/openvpn/speedtest.jpg)

### Note: The bandwidth of the tested internet connection is 35 Mbps download and 9 Mbps upload
There are also screenshots of the DNS Leak Test from https://dnsleaktest.com, which can be found inside the 'screenshots' folder
## CopyRight
L2TP Installer Script: https://github.com/bedefaced/vpn-install

OpenVPN Installer Script: https://github.com/angristan/openvpn-install

Xray-Core: https://github.com/XTLS/Xray-core

rathole: https://github.com/rapiz1/rathole

tun2socks: https://github.com/bedefaced/vpn-install
