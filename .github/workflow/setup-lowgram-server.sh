#!/usr/bin/env bash
# Installs gramsrv (Telegram-compatible MTProto server) on a fresh Ubuntu/Debian VPS.
# Usage: sudo bash setup-lowgram-server.sh [PUBLIC_IP]
set -euo pipefail

GRAMSRV_COMMIT=3e04d96534939dcf957d262dab8ef106b45870fa
PORT=2398

[[ $EUID -eq 0 ]] || { echo "run as root"; exit 1; }
IP=${1:-$(curl -4fsS https://ifconfig.me || true)}
[[ "$IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "pass the public IPv4 as argument"; exit 1; }

# Swap: build and Postgres need headroom on small VPS.
mem_mb=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
if [[ $mem_mb -lt 3500 ]] && ! swapon --show | grep -q .; then
  fallocate -l 3G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

command -v docker >/dev/null || curl -fsSL https://get.docker.com | sh
apt-get install -y git ufw >/dev/null

# Firewall: ssh + MTProto only. Admin UI stays on 127.0.0.1.
ufw allow OpenSSH >/dev/null; ufw allow ${PORT}/tcp >/dev/null; ufw --force enable >/dev/null

cd /opt
[[ -d gramsrv ]] || git clone --branch main --single-branch https://github.com/iamxvbaba/gramsrv.git
cd gramsrv
git fetch --depth 1 origin "$GRAMSRV_COMMIT" && git checkout -q "$GRAMSRV_COMMIT"

ENV=deploy/docker/.env
if [[ ! -f $ENV ]]; then
  ./scripts/new-docker-env.sh --advertise-ip "$IP" --admin-bind-ip 127.0.0.1 --allow-insecure-development-auth

  setkv() { if grep -q "^$1=" "$ENV"; then sed -i "s|^$1=.*|$1=$2|" "$ENV"; else echo "$1=$2" >> "$ENV"; fi; }
  CODE=$(shuf -i 100000-999999 -n 1)
  # Private RSA identity (the published image ships a public test key) and a non-default login code.
  setkv TELESRV_SERVER_BUILD_TARGET server
  setkv TELESRV_RSA_IDENTITY_MODE generated
  setkv TELESRV_DEV_AUTH_CODE "$CODE"
fi

./scripts/start-docker.sh --build

echo
echo "lowgram server: ${IP}:${PORT}"
echo "login code (give only to people you invite): $(awk -F= '$1=="TELESRV_DEV_AUTH_CODE"{print $2}' "$ENV")"
echo "admin UI: ssh -L 2600:127.0.0.1:2600 root@${IP}  ->  http://127.0.0.1:2600  (password in /opt/gramsrv/${ENV})"
