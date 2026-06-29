# WireGuard Installer

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**One-command WireGuard VPN setup for any Linux server.**

This script installs, configures, and starts WireGuard on a remote (or local) Linux server. It generates a full server configuration plus individual client profiles — all with a single command. Designed for headless servers running Ubuntu, Debian, CentOS/RHEL, AlmaLinux, Rocky Linux, or Fedora.

Part of the [Oculve](https://oculve.com) ecosystem — a privacy-focused VPN management platform.

---

## Features

- 🚀 **Zero configuration** — just provide a server IP and get WireGuard running in under 2 minutes
- 📦 **Automatic OS detection** — supports Ubuntu, Debian, CentOS/RHEL, AlmaLinux, Rocky Linux, Fedora
- 👥 **Multi-client** — generate any number of client profiles in one run
- 🔐 **Full encryption** — each client gets a unique key pair and pre-shared key
- 📤 **Machine-readable output** — `PROGRESS:`, `CLIENT_CONFIG:`, `SERVER_CONFIG:`, `ERROR:` prefixes for programmatic consumption
- 🧹 **Idempotent** — safe to re-run on an existing installation

---

## Quick Start

### Run directly via pipe (recommended for automated setups)

```bash
curl -sS https://raw.githubusercontent.com/oculve/wireguard-installer/main/install.sh | bash -s -- -s YOUR_SERVER_IP
```

### Download and run

```bash
wget https://raw.githubusercontent.com/oculve/wireguard-installer/main/install.sh
chmod +x install.sh
./install.sh -s YOUR_SERVER_IP
```

### Via environment variables

```bash
export SERVER_IP="YOUR_SERVER_IP"
export CLIENT_NAMES="laptop,phone,tablet"
curl -sS https://raw.githubusercontent.com/oculve/wireguard-installer/main/install.sh | bash
```

> ⚠️ **Important:** Replace `YOUR_SERVER_IP` with your server's public IP address.

---

## Usage

```bash
./install.sh [options]

Options:
  -s, --server-IP <IP>      Server public IP address (env: SERVER_IP, required)
  -p, --port <PORT>         WireGuard listen port (env: WG_PORT, default: 51820)
  -d, --dns <DNS>           DNS server for clients (env: DNS, default: 1.1.1.1)
  -c, --clients <NAMES>     Comma-separated client names (env: CLIENT_NAMES, default: client)
  -h, --help                Show help message
```

### Examples

**Single client with default settings:**
```bash
./install.sh -s 203.0.113.1
```

**Multiple clients on a custom port with Cloudflare DNS:**
```bash
./install.sh -s 203.0.113.1 -p 51822 -d 1.1.1.1 -c "alice,bob,charlie"
```

**Using all environment variables:**
```bash
SERVER_IP=203.0.113.1 WG_PORT=51820 DNS=8.8.8.8 CLIENT_NAMES="laptop,phone,desktop" ./install.sh
```

**Piped from curl with arguments:**
```bash
curl -sS https://raw.githubusercontent.com/oculve/wireguard-installer/main/install.sh | bash -s -- -s 203.0.113.1 -p 51820 -c "home,office"
```

---

## Environment Variables

| Variable       | Required | Default      | Description                            |
|----------------|----------|--------------|----------------------------------------|
| `SERVER_IP`    | ✅ Yes   | —            | Public IP address of your server       |
| `WG_PORT`      | ❌ No    | `51820`      | UDP port WireGuard listens on          |
| `DNS`          | ❌ No    | `1.1.1.1`    | DNS resolver pushed to VPN clients     |
| `CLIENT_NAMES` | ❌ No    | `client`     | Comma-separated client profile names   |

Command-line flags take precedence over environment variables.

---

## Output Format

The script produces machine-parseable output for easy integration:

| Prefix            | Description                                      |
|-------------------|--------------------------------------------------|
| `PROGRESS:`       | Status updates during installation               |
| `CLIENT_CONFIG:`  | `CLIENT_CONFIG:<name>:<base64-encoded config>`   |
| `SERVER_CONFIG:`  | `SERVER_CONFIG:<base64-encoded server config>`   |
| `ERROR:`          | Error message if something goes wrong            |
| `DONE`            | Final success signal                             |

These prefixes are consumed by the [Oculve API](https://oculve.com) to provide real-time setup feedback in the web dashboard, but you can parse them with any tool.

---

## What the Script Does

1. **Validates** it is running as root
2. **Detects** the operating system (Ubuntu, Debian, CentOS/RHEL, Fedora, etc.)
3. **Installs** WireGuard and iptables via the native package manager
4. **Enables** IP forwarding for NAT/routing
5. **Detects** the primary network interface
6. **Generates** server key pair and writes `/etc/wireguard/wg0.conf`
7. **Creates** individual client profiles with unique keys, PSKs, and IPs
8. **Starts** the WireGuard service and enables it on boot
9. **Outputs** the server config and each client config as base64-encoded strings

---

## Security

This script is fully open source so you can audit exactly what it does before running it:

- No telemetry, no phone-home, no data collection
- No external downloads other than WireGuard from your OS package manager
- Full encryption — all keys are generated locally on your server
- ~200 lines of straightforward bash — easy to review

Found a vulnerability? Contact **security@oculve.com**.
---

## Requirements

- **Linux server** (Ubuntu 20.04+, Debian 11+, CentOS 7+, RHEL 8+, AlmaLinux 9+, Rocky Linux 9+, Fedora 34+)
- **Root access** (run as root or via sudo)
- **Outbound internet access** (to download WireGuard packages)
- **UDP port** (default 51820) must be open on the server firewall

---

## License

[MIT](LICENSE) © 2025 Oculve

---

## About Oculve

[Oculve](https://oculve.com) is a privacy-first VPN management platform. This installer script is used internally by the Oculve API to provision WireGuard servers for users, but it works just as well as a standalone tool.

- 🌐 [oculve.com](https://oculve.com)
- 🐙 [github.com/oculve](https://github.com/oculve)
- 📧 [security@oculve.com](mailto:security@oculve.com)
