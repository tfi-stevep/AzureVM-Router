#!/usr/bin/env bash
set -euo pipefail

echo "[*] Ubuntu 22.04 NAT router setup (IPv4 NAT, IPv4/IPv6 forwarding)…"

# --- Detect default egress interface (fallback to eth0) ---
EGRESS_IF="$(ip -4 route show default 2>/dev/null | awk '/default/ {print $5; exit}')"
EGRESS_IF="${EGRESS_IF:-eth0}"
echo "[*] Egress interface detected: ${EGRESS_IF}"

# --- Runtime sysctl (immediate effect) ---
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv6.conf.all.forwarding=1
sysctl -w net.ipv4.conf.all.accept_redirects=0
sysctl -w net.ipv6.conf.all.accept_redirects=0

# --- Persistent sysctl via /etc/sysctl.d (preferred) ---
SYSCTL_DROPIN="/etc/sysctl.d/99-nat-forwarding.conf"
cat > "${SYSCTL_DROPIN}" <<'EOF'
# Enable forwarding and disable ICMP redirects
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
net.ipv4.conf.all.accept_redirects=0
net.ipv6.conf.all.accept_redirects=0
EOF
# Reload sysctl configs
sysctl --system >/dev/null

# --- Packages (non-interactive) ---
export DEBIAN_FRONTEND=noninteractive
apt-get update -y --fix-missing
# Preseed iptables-persistent to disable autosave prompts
echo "iptables-persistent iptables-persistent/autosave_v4 boolean false" | debconf-set-selections
echo "iptables-persistent iptables-persistent/autosave_v6 boolean false" | debconf-set-selections
apt-get install -y iptables-persistent

# Ensure the service is enabled (usually done by package)
systemctl enable netfilter-persistent >/dev/null 2>&1 || true

# --- IPv4 NAT rules (idempotent) ---
ensure_rule() {
  local table="$1" ; shift
  local chain="$1" ; shift
  local args=("$@")
  if iptables -t "$table" -C "$chain" "${args[@]}" 2>/dev/null; then
    echo "[=] Rule exists: iptables -t $table -C $chain ${args[*]}"
  else
    echo "[+] Adding: iptables -t $table -A $chain ${args[*]}"
    iptables -t "$table" -A "$chain" "${args[@]}"
  fi
}

# Do not NAT RFC1918 destinations (ACCEPT first), then MASQUERADE all else out the egress IF
ensure_rule nat POSTROUTING -d 10.0.0.0/8 -j ACCEPT
ensure_rule nat POSTROUTING -d 172.16.0.0/12 -j ACCEPT
ensure_rule nat POSTROUTING -d 192.168.0.0/16 -j ACCEPT
ensure_rule nat POSTROUTING -o "${EGRESS_IF}" -j MASQUERADE

# --- Persist IPv4 rules ---
mkdir -p /etc/iptables
iptables-save > /etc/iptables/rules.v4
echo "[*] Saved IPv4 rules to /etc/iptables/rules.v4"

# Explicitly reload persistence (optional now, automatic on next boot)
systemctl restart netfilter-persistent || true

echo "[✓] Done. Reboot not required."
``
