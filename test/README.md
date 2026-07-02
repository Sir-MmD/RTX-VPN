# RTX-VPN v2 — end-to-end test harness

Cross-distro, full-dataplane tests for RTX-VPN using **rootful podman**.

## What it does

For a given distro it builds a systemd container image, then stands up a 4-node
topology and drives the whole system end to end:

```
          rtxnet (10.89.0.0/24)                 rtxext (10.89.1.0/24)
  client ── tunnel ── edge ─────────────────────── edge ── exit
   (VPN)   (SoftEther+     (rathole client              (source-IP
           rathole+xray+    + xray freedom)              echo server)
           tun2socks+PBR)
```

- Installs RTX-VPN **headlessly** on the tunnel and edge (`RTX_ROLE`, `RTX_NONINTERACTIVE`).
- Verifies services (`softether`, `rtxvpn`, `dnsmasq`), interfaces (`tap_softether`, `rtx`),
  the rathole reverse tunnel, and the socks proxy chain.
- Connects a **real VPN client** over **OpenVPN**, **raw L2TP** and **L2TP/IPsec**,
  and checks that:
  - the client obtains a DHCP lease through the bridge,
  - its traffic **egresses via the edge** (the exit node sees the edge's IP, proving
    the full tunnel→edge path), and
  - there is **no DNS leak** (no plaintext port-53 traffic on the client's real link).

## Requirements

- Rootful **podman** (the host's Docker daemon has networking disabled, so podman is
  used; it manages its own nftables rules).
- `/dev/net/tun` and the `l2tp`, `ppp` and IPsec (`xfrm`, `af_key`) kernel modules
  available on the host (loaded on demand).

## Usage

```bash
sudo test/run.sh <distro> [--keep] [--protocols ovpn,l2tp-raw,l2tp-ipsec]
sudo test/matrix.sh [distro ...]      # default: all 8 supported distros
```

`<distro>` ∈ `debian12 debian13 ubuntu22 ubuntu24 ubuntu26 fedora arch alma`.
`--keep` leaves the containers running for inspection. Per-distro logs from a
matrix run land in `test/logs/<distro>.log`.

## Layout

| Path | Purpose |
|------|---------|
| `run.sh` | orchestrate + verify one distro |
| `matrix.sh` | run `run.sh` across every distro |
| `images/Containerfile.{debian,dnf,arch}` | systemd base images per package manager |
| `images/Containerfile.client` | fixed Debian client (openvpn / xl2tpd / strongswan) |
| `client/openvpn.sh`, `client/l2tp.sh` | in-client connection drivers |
| `cache/`, `logs/` | download cache and run logs (git-ignored) |
