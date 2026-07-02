#!/usr/bin/env python3
#MmD
import os
import subprocess
import signal
import time
import sys

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

def start_process(command, name):
    try:
        process = subprocess.Popen(command, shell=True)
        log(f"{name} started with PID {process.pid}")
        return process
    except Exception as e:
        log(f"Error starting {name}: {e}")
        sys.exit(1)
        
rathole_process = start_process("/opt/rtxvpn_v2/edge/rathole /opt/rtxvpn_v2/edge/edge.toml", "Rathole")
xray_process = start_process("/opt/rtxvpn_v2/edge/xray run -c /opt/rtxvpn_v2/edge/edge.json", "Xray")

log("VPN Service Started")

def shutdown_handler(signum, frame):
    """Handle shutdown signals."""
    log("VPN Service interrupted")
    for process in [rathole_process, xray_process]:
        if process:
            process.terminate()
    sys.exit(1)

# Register signal handlers
signal.signal(signal.SIGINT, shutdown_handler)
signal.signal(signal.SIGTERM, shutdown_handler)

# Wait for processes
rathole_process.wait()
xray_process.wait()

log("VPN Service finished")
