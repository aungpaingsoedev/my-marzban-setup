#!/bin/bash

# Clear screen
clear

# --- Colors & UI Helpers ---
CYAN="\e[1;36m"
GREEN="\e[1;32m"
YELLOW="\e[1;33m"
RED="\e[1;31m"
BOLD="\e[1m"
DIM="\e[2m"
RESET="\e[0m"

line() {
    echo -e "${DIM}────────────────────────────────────────────────────────${RESET}"
}

section() {
    echo ""
    line
    echo -e "${CYAN}  $1${RESET}"
    line
}

info()    { echo -e "${CYAN}›${RESET} $1"; }
ok()      { echo -e "${GREEN}✓${RESET} $1"; }
warn()    { echo -e "${YELLOW}!${RESET} $1"; }
fail()    { echo -e "${RED}✗${RESET} $1"; }
step()    { echo -e "${BOLD}→${RESET} $1"; }

ask() {
    local prompt="$1"
    local var="$2"
    local secret="${3:-0}"
    if [ "$secret" = "1" ]; then
        read -s -p "$(echo -e "${YELLOW}?${RESET} ${prompt}: ")" "$var"
        echo ""
    else
        read -p "$(echo -e "${YELLOW}?${RESET} ${prompt}: ")" "$var"
    fi
}

# --- Banner ---
echo -e "${CYAN}"
echo "       █████╗ ██████╗ ███████╗"
echo "      ██╔══██╗██╔══██╗██╔════╝"
echo "      ███████║██████╔╝███████╗"
echo "      ██╔══██║██╔═══╝ ╚════██║"
echo "      ██║  ██║██║     ███████║"
echo "      ╚═╝  ╚═╝╚═╝     ╚══════╝"
echo -e "${RESET}"
echo -e "         ${BOLD}Marzban One Line Setup${RESET}"
echo -e "         ${DIM}Automated install · SSL · Protocols · MySQL${RESET}"
line
echo -e "  ${BOLD}Protocols${RESET}"
echo -e "  ${DIM}•${RESET} VLESS   Reality · WS TLS · TCP"
echo -e "  ${DIM}•${RESET} VMess   WS TLS · TCP"
echo -e "  ${DIM}•${RESET} Trojan  TLS · TCP"
echo -e "  ${DIM}•${RESET} Shadowsocks  TCP/UDP"
line

# --- Packages ---
section "1 / 6  Dependencies"
step "Updating packages and installing dependencies..."
sudo apt update && sudo apt install -y curl socat wget sed unzip python3
ok "Dependencies ready."

# --- Inputs ---
section "2 / 6  Configuration"
echo -e "  ${DIM}Enter the details below to continue.${RESET}"
echo ""
ask "Domain name (e.g. singapore1.pixel4u.site)" DOMAIN
ask "Email for SSL certificate" EMAIL
ask "Telegram bot token" BOT_TOKEN
ask "Telegram admin ID" ADMIN_ID
ask "Subscription title" SUB_TITLE
ask "Admin username" ADMIN_USER
ask "Admin password" ADMIN_PASS 1

echo ""
echo -e "  ${BOLD}Remote MySQL Database${RESET}"
echo ""
ask "MySQL IP / Host" DB_HOST
ask "MySQL username" DB_USER
ask "MySQL password" DB_PASS 1
DB_PORT="3306"
DB_NAME="marzban"

DOMAIN=$(echo "$DOMAIN" | xargs)
EMAIL=$(echo "$EMAIL" | xargs)
DB_HOST=$(echo "$DB_HOST" | xargs)
DB_USER=$(echo "$DB_USER" | xargs)

if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    fail "Invalid domain: '${DOMAIN}'"
    fail "Use a domain like singapore1.pixel4u.site (do not use @ / email)."
    exit 1
fi

if [[ ! "$EMAIL" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; then
    fail "Invalid email: '${EMAIL}'"
    exit 1
fi

if [ -z "$DB_HOST" ] || [ -z "$DB_USER" ] || [ -z "$DB_PASS" ]; then
    fail "MySQL host, username, and password are required."
    exit 1
fi

ok "Inputs saved."

# --- Marzban Install ---
section "3 / 6  Marzban Install"
step "Installing Marzban..."
sudo bash -c "$(curl -sL https://github.com/Gozargah/Marzban-scripts/raw/master/marzban.sh)" @ install
ok "Marzban installed."

# Restore official image (remove any Neon custom build leftovers)
step "Restoring official Marzban Docker image..."
sudo rm -f /opt/marzban/Dockerfile
sudo tee /opt/marzban/docker-compose.yml > /dev/null <<'COMPOSE'
services:
  marzban:
    image: gozargah/marzban:latest
    restart: always
    env_file: .env
    network_mode: host
    volumes:
      - /var/lib/marzban:/var/lib/marzban
COMPOSE
ok "Official Docker Compose ready."

CERT_DIR="/var/lib/marzban/certs/${DOMAIN}"
CERT_FILE="${CERT_DIR}/fullchain.pem"
KEY_FILE="${CERT_DIR}/privkey.pem"

step "Issuing SSL certificate for ${BOLD}${DOMAIN}${RESET}..."
sudo bash -c "$(curl -sL https://raw.githubusercontent.com/erfjab/ESSL/master/essl.sh)" @ --install
if ! sudo essl "$EMAIL" "$DOMAIN" marzban; then
    fail "SSL certificate failed for ${DOMAIN}."
    fail "Check DNS A record points to this server, then try again."
    exit 1
fi

if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
    fail "Certificate files not found:"
    info "$CERT_FILE"
    info "$KEY_FILE"
    exit 1
fi
ok "SSL certificate ready."

step "Downloading subscription template..."
sudo mkdir -p /var/lib/marzban/templates/subscription/
sudo wget -N -P /var/lib/marzban/templates/subscription/ https://raw.githubusercontent.com/yannaing86tt/template/main/subscription/index.html
ok "Template installed."

# --- Env ---
section "4 / 6  Environment"
ENV_FILE="/opt/marzban/.env"

update_env() {
    local key=$1
    local value=$2
    if sudo grep -iqE "^#?\s*$key\s*=" "$ENV_FILE"; then
        sudo sed -i "s|^#*\s*$key\s*=.*|$key = \"$value\"|gI" "$ENV_FILE"
    else
        echo "$key = \"$value\"" | sudo tee -a "$ENV_FILE" > /dev/null
    fi
}

# URL-encode MySQL password
DB_PASS_ENC=$(printf '%s' "$DB_PASS" | python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read(), safe=''))")
DB_URL="mysql+pymysql://${DB_USER}:${DB_PASS_ENC}@${DB_HOST}:${DB_PORT}/${DB_NAME}"

step "Writing .env settings..."
update_env "UVICORN_HOST" "0.0.0.0"
update_env "UVICORN_PORT" "8000"
update_env "UVICORN_SSL_CERTFILE" "$CERT_FILE"
update_env "UVICORN_SSL_KEYFILE" "$KEY_FILE"
update_env "SQLALCHEMY_DATABASE_URL" "$DB_URL"
update_env "TELEGRAM_API_TOKEN" "$BOT_TOKEN"
update_env "TELEGRAM_ADMIN_ID" "$ADMIN_ID"
update_env "SUB_PROFILE_TITLE" "$SUB_TITLE"
update_env "XRAY_SUBSCRIPTION_URL_PREFIX" "https://$DOMAIN:8000"
update_env "CUSTOM_TEMPLATES_DIRECTORY" "/var/lib/marzban/templates/"
update_env "SUBSCRIPTION_PAGE_TEMPLATE" "subscription/index.html"

# Remove any old typo / Neon leftovers
sudo sed -i "/^UNICORN_SSL_/d" "$ENV_FILE"
ok ".env updated (remote MySQL)."

# --- Protocols ---
section "5 / 6  Protocols"
step "Generating Reality keys..."

KEYS=$(docker exec marzban-marzban-1 xray x25519 2>/dev/null || docker exec marzban-1 xray x25519 2>/dev/null)

if [ -z "$KEYS" ]; then
    warn "xray not found in Docker — downloading binary..."
    curl -L -o /tmp/xray.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip &>/dev/null
    unzip -o /tmp/xray.zip xray -d /tmp/ &>/dev/null
    chmod +x /tmp/xray
    KEYS=$(/tmp/xray x25519)
fi

PRIV=$(echo "$KEYS" | grep "Private key" | cut -d ' ' -f 3)
PUB=$(echo "$KEYS" | grep "Public key" | cut -d ' ' -f 3)
SID=$(openssl rand -hex 4)

if [ -z "$PRIV" ]; then
    fail "Could not generate Reality keys."
    exit 1
fi

ok "Reality keys generated."

step "Writing xray_config.json..."
sudo tee /var/lib/marzban/xray_config.json > /dev/null <<EOF
{
    "log": { "loglevel": "warning" },
    "routing": {
        "rules": [ { "type": "field", "ip": ["geoip:private"], "outboundTag": "BLOCK" } ]
    },
    "inbounds": [
        {
            "tag": "VLESS WS TLS",
            "listen": "0.0.0.0",
            "port": 2083,
            "protocol": "vless",
            "settings": { "clients": [], "decryption": "none" },
            "streamSettings": {
                "network": "ws", "security": "tls",
                "tlsSettings": {
                    "certificates": [{
                        "certificateFile": "$CERT_FILE",
                        "keyFile": "$KEY_FILE"
                    }]
                },
                "wsSettings": { "path": "/vless" }
            }
        },
        {
            "tag": "VLESS REALITY",
            "listen": "0.0.0.0",
            "port": 443,
            "protocol": "vless",
            "settings": { "clients": [], "decryption": "none" },
            "streamSettings": {
                "network": "tcp", "security": "reality",
                "realitySettings": {
                    "show": false, "dest": "www.cloudflare.com:443", "xver": 0,
                    "serverNames": ["www.cloudflare.com", "$DOMAIN"],
                    "privateKey": "$PRIV",
                    "publicKey": "$PUB",
                    "shortIds": ["$SID"]
                }
            },
            "sniffing": { "enabled": true, "destOverride": ["http", "tls"] }
        },
        {
            "tag": "VMess WS TLS",
            "listen": "0.0.0.0",
            "port": 8443,
            "protocol": "vmess",
            "settings": { "clients": [] },
            "streamSettings": {
                "network": "ws", "security": "tls",
                "tlsSettings": {
                    "certificates": [{
                        "certificateFile": "$CERT_FILE",
                        "keyFile": "$KEY_FILE"
                    }]
                },
                "wsSettings": { "path": "/vmess" }
            }
        },
        {
            "tag": "Trojan TLS",
            "listen": "0.0.0.0",
            "port": 2053,
            "protocol": "trojan",
            "settings": { "clients": [] },
            "streamSettings": {
                "network": "tcp", "security": "tls",
                "tlsSettings": {
                    "certificates": [{
                        "certificateFile": "$CERT_FILE",
                        "keyFile": "$KEY_FILE"
                    }]
                }
            }
        },
        {
            "tag": "VLESS TLS",
            "listen": "0.0.0.0",
            "port": 9850,
            "protocol": "vless",
            "settings": { "clients": [], "decryption": "none" },
            "streamSettings": { "network": "tcp", "security": "none" },
            "sniffing": { "enabled": true, "destOverride": ["http", "tls"] }
        },
        {
            "tag": "VMESS + TCP",
            "listen": "0.0.0.0",
            "port": 4427,
            "protocol": "vmess",
            "settings": { "clients": [] },
            "streamSettings": { "network": "tcp", "security": "none" },
            "sniffing": { "enabled": true, "destOverride": ["http", "tls"] }
        },
        {
            "tag": "TROJAN + TCP",
            "listen": "0.0.0.0",
            "port": 9094,
            "protocol": "trojan",
            "settings": { "clients": [] },
            "streamSettings": { "network": "tcp", "security": "none" },
            "sniffing": { "enabled": true, "destOverride": ["http", "tls"] }
        },
        {
            "tag": "Shadowsocks TCP",
            "listen": "0.0.0.0",
            "port": 1080,
            "protocol": "shadowsocks",
            "settings": { "clients": [], "network": "tcp,udp" }
        }
    ],
    "outbounds": [
        { "protocol": "freedom", "tag": "DIRECT" },
        { "protocol": "blackhole", "tag": "BLOCK" }
    ]
}
EOF
ok "Protocol config written."

# --- Finish ---
section "6 / 6  Finalize"
step "Restarting Marzban..."
cd /opt/marzban && sudo docker compose up -d --force-recreate
marzban restart 2>/dev/null || true

# Cleanup
rm -rf /tmp/xray.zip /tmp/xray 2>/dev/null

# Wait for Marzban to wake up before creating admin
sleep 5

step "Creating admin user..."
if marzban cli admin create --username "$ADMIN_USER" --password "$ADMIN_PASS" --sudo; then
    ok "Admin user created."
else
    warn "Admin setup skipped (may already exist)."
fi

echo ""
line
echo -e "${GREEN}${BOLD}  Setup complete${RESET}"
line
echo -e "  ${BOLD}Dashboard${RESET}  https://${DOMAIN}:8000/dashboard"
echo -e "  ${BOLD}Username${RESET}   ${ADMIN_USER}"
echo -e "  ${BOLD}Database${RESET}  ${DB_HOST}"
echo -e "  ${BOLD}Config${RESET}     /var/lib/marzban/xray_config.json"
line
echo -e "  ${DIM}Open the dashboard and add your users.${RESET}"
echo ""
