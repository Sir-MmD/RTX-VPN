#!/usr/bin/env python3
#MmD
import os
import subprocess
import signal
import time
import sys
import threading

log_file = "/var/log/vpn-service.log"
pidfile = "/var/run/vpn-service.pid"

def log(message):
    timestamp = time.strftime('%Y-%m-%d %H:%M:%S')
    with open(log_file, "a") as f:
        f.write(f"{timestamp} - {message}\n")

def run_command(command):
    try:
        subprocess.run(command, shell=True, check=True)
    except subprocess.CalledProcessError as e:
        log(f"Command failed: {command} - {e}")

def pbr():
    commands = [
        "ip tuntap add mode tun dev rtx || true",
        "ip addr add 198.18.0.1/15 dev rtx || true",
        "ip link set dev rtx up || true",
        "ip link set dev tap_softether down || true",
        "ip addr add 198.19.0.1/24 dev tap_softether || true",
        "ip link set dev tap_softether up || true",
        # Use the numeric table id (200) directly: the "rtx_table" name is only
        # present if /etc/iproute2/rt_tables exists, which newer distros (e.g.
        # Debian 13, Fedora, Arch) no longer ship by default. A numeric id always
        # works, so PBR no longer depends on the name being registered.
        "ip route add 198.19.0.0/24 dev rtx table 200 || true",
        "ip route add default dev rtx table 200 || true",
        "ip rule add from 198.19.0.0/24 table 200 priority 10 || true",
        "ip rule add to 8.8.8.8 table main priority 11 || true",
        "ip rule add to 8.8.4.4 table main priority 12 || true",
    ]
    for cmd in commands:
        run_command(cmd)
    log("PBR setup completed")

def firewall():
    """Enable forwarding and install FORWARD rules (idempotent, distro-agnostic).

    Kept here instead of relying on iptables-persistent/netfilter-persistent so
    the setup works identically on Debian/Ubuntu, Fedora/Alma and Arch. Rules are
    (re)applied on every service start."""
    run_command("sysctl -w net.ipv4.ip_forward=1")
    rules = [
        "-i tap_softether -o rtx -j ACCEPT",
        "-i rtx -o tap_softether -m state --state ESTABLISHED,RELATED -j ACCEPT",
    ]
    for rule in rules:
        # Delete first (ignore failure) so we never stack duplicates, then add.
        run_command(f"iptables -D FORWARD {rule} 2>/dev/null || true")
        run_command(f"iptables -A FORWARD {rule}")
    log("Firewall/forwarding setup completed")

def tap_has_gateway_ip():
    r = subprocess.run(
        "ip -4 addr show tap_softether 2>/dev/null | grep -q '198.19.0.1/24'",
        shell=True)
    return r.returncode == 0

def watchdog():
    """SoftEther deletes and recreates tap_softether whenever the VPN server
    restarts (crash-restart or manual), which drops the 198.19.0.1/24 address
    that pbr() assigned. Without that address dnsmasq refuses to serve DHCP and
    L2TP/OpenVPN clients cannot get a lease. Re-apply it whenever it goes
    missing so the data path survives SoftEther restarts."""
    while True:
        time.sleep(5)
        try:
            if not tap_has_gateway_ip():
                run_command("ip addr add 198.19.0.1/24 dev tap_softether || true")
                run_command("ip link set dev tap_softether up || true")
                log("watchdog: re-applied tap_softether 198.19.0.1/24")
            if subprocess.run("ip link show rtx >/dev/null 2>&1", shell=True).returncode != 0:
                pbr()
        except Exception as e:
            log(f"watchdog error: {e}")

def start_process(command, name):
    try:
        process = subprocess.Popen(command, shell=True)
        log(f"{name} started with PID {process.pid}")
        return process
    except Exception as e:
        log(f"Error starting {name}: {e}")
        sys.exit(1)

pbr()
firewall()
threading.Thread(target=watchdog, daemon=True).start()
rathole_process = start_process("/opt/rtxvpn_v2/tunnel/rathole /opt/rtxvpn_v2/tunnel/tunnel.toml", "Rathole")
tun2socks_process = start_process("/opt/rtxvpn_v2/tunnel/tun2socks -device rtx -proxy socks5://127.0.0.1:10808", "Tun2socks")
xray_process = start_process("/opt/rtxvpn_v2/tunnel/xray run -c /opt/rtxvpn_v2/tunnel/tunnel.json", "Xray")

log("VPN Service Started")

def shutdown_handler(signum, frame):
    """Handle shutdown signals."""
    log("VPN Service interrupted")
    for process in [rathole_process, tun2socks_process, xray_process]:
        if process:
            process.terminate()
    sys.exit(1)

# Register signal handlers
signal.signal(signal.SIGINT, shutdown_handler)
signal.signal(signal.SIGTERM, shutdown_handler)

# Wait for processes
rathole_process.wait()
tun2socks_process.wait()
xray_process.wait()

log("VPN Service finished")
