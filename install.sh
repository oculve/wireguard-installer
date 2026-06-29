#!/bin/bash
# This script is part of Oculve - github.com/oculve/wireguard-installer
# WireGuard VPN setup script — installs and configures WireGuard on any Linux server via SSH.
set -eo pipefail
export DEBIAN_FRONTEND=noninteractive
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# ---- Defaults ----
DEFAULT_WG_PORT="51820"
DEFAULT_DNS="1.1.1.1"
DEFAULT_CLIENTS="client"

# ---- Usage ----
usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -s, --server-IP <IP>      Server public IP address (env: SERVER_IP, required)
  -p, --port <PORT>         WireGuard listen port (env: WG_PORT, default: ${DEFAULT_WG_PORT})
  -d, --dns <DNS>           DNS server for clients (env: DNS, default: ${DEFAULT_DNS})
  -c, --clients <NAMES>     Comma-separated client names (env: CLIENT_NAMES, default: ${DEFAULT_CLIENTS})
  -h, --help                Show this help message

Environment variables:
  SERVER_IP                 Server public IP address (overridden by -s)
  WG_PORT                   WireGuard listen port (overridden by -p)
  DNS                       DNS server for clients (overridden by -d)
  CLIENT_NAMES              Comma-separated client names (overridden by -c)

Examples:
  $(basename "$0") -s 203.0.113.1
  $(basename "$0") -s 203.0.113.1 -p 51820 -d 1.1.1.1 -c "alice,bob,charlie"
  SERVER_IP=203.0.113.1 CLIENT_NAMES="laptop,phone" $(basename "$0")
  curl -sS https://raw.githubusercontent.com/oculve/wireguard-installer/main/install.sh | bash -s -- -s 203.0.113.1
EOF
  exit 0
}

# ---- Parse arguments ----
SERVER_IP="${SERVER_IP:-}"
WG_PORT="${WG_PORT:-$DEFAULT_WG_PORT}"
DNS="${DNS:-$DEFAULT_DNS}"
CLIENT_NAMES="${CLIENT_NAMES:-$DEFAULT_CLIENTS}"

while [ $# -gt 0 ]; do
  case "$1" in
    -s|--server-ip)
      SERVER_IP="$2"
      shift 2
      ;;
    -p|--port)
      WG_PORT="$2"
      shift 2
      ;;
    -d|--dns)
      DNS="$2"
      shift 2
      ;;
    -c|--clients)
      CLIENT_NAMES="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "ERROR: Unknown option: $1"
      usage
      ;;
  esac
done

# ---- Validate ----
if [ -z "$SERVER_IP" ]; then
  echo "ERROR: SERVER_IP is required. Use -s <IP> or set SERVER_IP environment variable."
  exit 1
fi

# ---- Sanitise client names (mirrors TypeScript buildScript logic) ----
sanitise_name() {
  local raw="$1" index="$2" fallback="client$((index + 1))"
  # Strip non-alphanumeric, keep underscore and hyphen
  local cleaned
  cleaned=$(echo "$raw" | tr -cd 'a-zA-Z0-9_-' | head -c 30)
  if [ -z "$cleaned" ]; then
    echo "$fallback"
  else
    echo "$cleaned"
  fi
}

IFS=',' read -r -a RAW_CLIENT_NAMES <<< "$CLIENT_NAMES"
CLIENT_LIST=()
for i in "${!RAW_CLIENT_NAMES[@]}"; do
  [ "$i" -ge 20 ] && break  # max 20 clients
  CLIENT_LIST+=("$(sanitise_name "${RAW_CLIENT_NAMES[$i]}" "$i")")
done

if [ ${#CLIENT_LIST[@]} -eq 0 ]; then
  CLIENT_LIST=("client1")
fi

# ============================================================
# INSTALLATION STARTS HERE
# ============================================================

echo "PROGRESS:Checking permissions..."
if [ "$(id -u)" != "0" ]; then
  echo "ERROR: Must be run as root. Use root login or prepend sudo."
  exit 1
fi

echo "PROGRESS:Detecting operating system..."
OS_ID=unknown
[ -f /etc/os-release ] && . /etc/os-release && OS_ID=$ID

echo "PROGRESS:Installing WireGuard (may take 1-2 minutes)..."
if ! command -v wg &>/dev/null; then
  case "$OS_ID" in
    ubuntu|debian)
      apt-get update -qq 2>&1 | tail -1
      apt-get install -y -qq wireguard wireguard-tools iptables 2>&1 | tail -3
      ;;
    centos|rhel|almalinux|rocky)
      yum install -y -q epel-release 2>&1 | tail -1
      yum install -y -q wireguard-tools iptables 2>&1 | tail -3
      ;;
    fedora)
      dnf install -y -q wireguard-tools iptables 2>&1 | tail -3
      ;;
    *)
      apt-get update -qq 2>&1 | tail -1 && apt-get install -y -qq wireguard wireguard-tools iptables 2>&1 | tail -3 || {
        echo "ERROR: Unsupported OS: $OS_ID. Supported: Ubuntu, Debian, CentOS/RHEL, Fedora."
        exit 1
      }
      ;;
  esac
fi

echo "PROGRESS:Enabling IP forwarding..."
sysctl -qw net.ipv4.ip_forward=1 2>/dev/null || true
grep -qxF 'net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf

SNIC=$(ip route show default 2>/dev/null | awk '/default/{print $5;exit}')
[ -z "$SNIC" ] && SNIC=$(ls /sys/class/net/ 2>/dev/null | grep -v lo | head -1)
[ -z "$SNIC" ] && SNIC=eth0
echo "PROGRESS:Primary interface: $SNIC"

echo "PROGRESS:Generating server keys..."
mkdir -p /etc/wireguard && chmod 700 /etc/wireguard
SPRIV=$(wg genkey)
SPUB=$(echo "$SPRIV" | wg pubkey)

echo "PROGRESS:Writing server configuration..."
{
  echo "[Interface]"
  echo "Address = 10.66.66.1/24"
  echo "ListenPort = ${WG_PORT}"
  echo "PrivateKey = $SPRIV"
  echo "PostUp = iptables -I INPUT -p udp --dport ${WG_PORT} -j ACCEPT; iptables -I FORWARD -i wg0 -j ACCEPT; iptables -I FORWARD -o wg0 -j ACCEPT; iptables -t nat -I POSTROUTING -o $SNIC -j MASQUERADE"
  echo "PostDown = iptables -D INPUT -p udp --dport ${WG_PORT} -j ACCEPT; iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $SNIC -j MASQUERADE"
} > /etc/wireguard/wg0.conf
chmod 600 /etc/wireguard/wg0.conf

# ---- Client profile generation (loop over CLIENT_LIST) ----
echo "PROGRESS:Generating client profiles..."
CLIENT_INDEX=0
for CLIENT_NAME in "${CLIENT_LIST[@]}"; do
  CLIENT_IP_SUFFIX=$((CLIENT_INDEX + 2))

  echo "PROGRESS:Creating profile for ${CLIENT_NAME}..."

  C_PRIV=$(wg genkey)
  C_PUB=$(echo "$C_PRIV" | wg pubkey)
  C_PSK=$(wg genpsk)

  # Append peer to server config
  printf '\n[Peer]\n# %s\nPublicKey = %s\nPresharedKey = %s\nAllowedIPs = 10.66.66.%d/32\n' \
    "$CLIENT_NAME" "$C_PUB" "$C_PSK" "$CLIENT_IP_SUFFIX" >> /etc/wireguard/wg0.conf

  # Build and emit client config (base64 encoded)
  C_CONF=$(printf '[Interface]\nPrivateKey = %s\nAddress = 10.66.66.%d/32\nDNS = %s\n\n[Peer]\nPublicKey = %s\nPresharedKey = %s\nEndpoint = %s:%s\nAllowedIPs = 0.0.0.0/0, ::/0\nPersistentKeepalive = 25' \
    "$C_PRIV" "$CLIENT_IP_SUFFIX" "$DNS" "$SPUB" "$C_PSK" "$SERVER_IP" "$WG_PORT")
  echo "CLIENT_CONFIG:${CLIENT_NAME}:$(echo "$C_CONF" | base64 | tr -d '\n')"

  CLIENT_INDEX=$((CLIENT_INDEX + 1))
done

echo "PROGRESS:Exporting configurations..."
echo "SERVER_CONFIG:$(base64 -w0 /etc/wireguard/wg0.conf 2>/dev/null || base64 /etc/wireguard/wg0.conf | tr -d '\n')"

echo "PROGRESS:Starting WireGuard service..."
systemctl enable wg-quick@wg0 2>/dev/null || true
if systemctl is-active --quiet wg-quick@wg0 2>/dev/null; then
  systemctl restart wg-quick@wg0 2>/dev/null || true
else
  systemctl start wg-quick@wg0 2>/dev/null || wg-quick up wg0 2>/dev/null || true
fi

echo "DONE"
