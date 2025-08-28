#!/bin/bash

# ============ CONFIG ============
FQDNS=("example.com" "IP" )
SSH_ALLOW_IP="IP"
LOCAL_SUBNETS=("10.110.0.0/20")

# Allow custom port, comment to disable function
#PORTS=("443")

# Logging
LOG_FILE="/var/log/ufw-designer.log"
ERROR_LOG="/var/log/ufw-designer-errors.log"

# ============ INIT ============
exec > >(tee -a "$LOG_FILE") 2>&1
exec 3> "$ERROR_LOG"
set -e

echo "🚧 Initializing UFW for SERVER_NAME"
echo "⏰ Время запуска: $(date)"

# ===== Checking SSH_ALLOW_IP =====
if [[ -z "$SSH_ALLOW_IP" ]]; then
  echo "❌ SSH_ALLOW_IP not specified - SSH access will NOT be opened!"
  echo "⛔Stopping the script to avoid blocking access."
  exit 1
fi

# ===== Reset and default policy =====
echo "🔄 Reset UFW rules ..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing

# ===== Enable UFW logging =====
ufw logging on

# ===== Allow loopback =====
ufw allow in on lo comment "Allow loopback"
ufw allow out on lo comment "Allow loopback"

# ===== Local Networks =====
for subnet in "${LOCAL_SUBNETS[@]}"; do
  ufw allow from "$subnet" comment "Local network $subnet"
  echo "✅ Local network allowed: $subnet"
done

# ===== SSH =====
ufw allow proto tcp from "$SSH_ALLOW_IP" to any port 22 comment "SSH from admin"
echo "✅ SSH allow from IP: $SSH_ALLOW_IP"

# ===== FQDN/IP allow =====
for host in "${FQDNS[@]}"; do
  if [[ "$host" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    ufw allow from "$host" comment "Allowed IP $host"
    echo "✅ Allowed IP: $host"
  else
    resolved_ips=$(dig +short "$host" | grep -E '^[0-9.]+$')
    if [[ -z "$resolved_ips" ]]; then
      echo "❌ Failed to resolve FQDN: $host" | tee >(cat >&3)
    else
      for ip in $resolved_ips; do
        ufw allow from "$ip" comment "FQDN $host resolved to $ip"
        echo "✅ Allowed from FQDN $host → $ip"
      done
    fi
  fi
done

# ===== Globally Open Ports =====
if [[ ${#PORTS[@]} -gt 0 ]]; then
  echo "🌐 Opening ports for all..."
  for port in "${PORTS[@]}"; do
    ufw allow "$port"/tcp comment "Allow TCP port $port from anywhere"
    echo "✅ Port $port/tcp is open for all"
  done
else
  echo "ℹ️ PORTS list is empty - global ports were not opened"
fi

# ===== Block all Docker ports on public interface =====
#iptables -I DOCKER-USER 1 -i eth0 -p tcp -j DROP

# ===== Optional: allow localhost (docker0 bridge) =====
#iptables -I DOCKER-USER -i docker0 -j ACCEPT

#echo "✅ Docker ports are blocked on eth0, only allowed from private network"

# ===== Enable UFW =====
echo "🚀 Enable UFW..."
ufw --force enable

# ===== Checking =====
echo "📋 UFW Current Status:"
ufw status verbose

echo "✅ UFW configured successfully. See log: $LOG_FILE"
