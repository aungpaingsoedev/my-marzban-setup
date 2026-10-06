#!/bin/bash

set -u

# ============================================================
# Marzban One-Line Setup
# Fixed:
# - cron/acme.sh installation
# - existing SSL certificate detection
# - SSL installation to Marzban cert directory
# - local MySQL connection
# - MySQL readiness checks
# - Docker startup checks
# - safer .env updates
# ============================================================

clear

# ---------- Colors ----------
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

info() { echo -e "${CYAN}›${RESET} $1"; }
ok()   { echo -e "${GREEN}✓${RESET} $1"; }
warn() { echo -e "${YELLOW}!${RESET} $1"; }
fail() { echo -e "${RED}✗${RESET} $1"; }
step() { echo -e "${BOLD}→${RESET} $1"; }

ask() {
    local prompt="$1"
    local var="$2"
    local secret="${3:-0}"

    if [ "$secret" = "1" ]; then
        read -r -s -p "$(echo -e "${YELLOW}?${RESET} ${prompt}: ")" "$var"
        echo ""
    else
        read -r -p "$(echo -e "${YELLOW}?${RESET} ${prompt}: ")" "$var"
    fi
}

die() {
    fail "$1"
    exit 1
}

# ---------- Root check ----------
if [ "$(id -u)" -ne 0 ]; then
    die "Please run this script as root."
fi

# ---------- Banner ----------
echo -e "${CYAN}"
echo "        █████╗ ██████╗ ███████╗"
echo "       ██╔══██╗██╔══██╗██╔════╝"
echo "       ███████║██████╔╝███████╗"
echo "       ██╔══██║██╔═══╝ ╚════██║"
echo "       ██║  ██║██║     ███████║"
echo "       ╚═╝  ╚═╝██║     ╚══════╝"
echo -e "${RESET}"

echo -e "          ${BOLD}Marzban One Line Setup${RESET}"
echo -e "          ${DIM}Marzban · SSL · Xray · MySQL${RESET}"

line
echo -e "  ${BOLD}Protocols${RESET}"
echo -e "  ${DIM}•${RESET} VLESS     Reality · WS TLS · TCP"
echo -e "  ${DIM}•${RESET} VMess     WS TLS · TCP"
echo -e "  ${DIM}•${RESET} Trojan    TLS · TCP"
echo -e "  ${DIM}•${RESET} Shadowsocks TCP/UDP"
line


# ============================================================
# 1 / 7 Dependencies
# ============================================================

section "1 / 7  Dependencies"

step "Updating packages..."

apt-get update || die "apt update failed."

step "Installing dependencies..."

DEBIAN_FRONTEND=noninteractive apt-get install -y \
    curl \
    wget \
    socat \
    unzip \
    python3 \
    cron \
    openssl \
    ca-certificates \
    dnsutils \
    netcat-openbsd

if [ $? -ne 0 ]; then
    die "Could not install dependencies."
fi

systemctl enable cron >/dev/null 2>&1 || true
systemctl start cron >/dev/null 2>&1 || true

ok "Dependencies ready."


# ============================================================
# 2 / 7 Configuration
# ============================================================

section "2 / 7  Configuration"

echo -e "  ${DIM}Enter the details below.${RESET}"
echo ""

ask "Domain name (e.g. japan.pixel4u.site)" DOMAIN
ask "Email for SSL certificate" EMAIL
ask "Telegram bot token" BOT_TOKEN
ask "Telegram admin ID" ADMIN_ID
ask "Subscription title" SUB_TITLE
ask "Admin username" ADMIN_USER
ask "Admin password" ADMIN_PASS 1

DOMAIN=$(echo "$DOMAIN" | xargs)
EMAIL=$(echo "$EMAIL" | xargs)

if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    die "Invalid domain: $DOMAIN"
fi

if [[ ! "$EMAIL" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; then
    die "Invalid email: $EMAIL"
fi


# ============================================================
# MySQL
# ============================================================

# MySQL is installed on THIS SAME VPS.
#
# Because Marzban Docker uses:
#
# network_mode: host
#
# the container can reach MySQL through 127.0.0.1.

DB_HOST="127.0.0.1"
DB_PORT="3306"

DB_NAME="marzban"
DB_USER="admin"
DB_PASS="adminpass"

ok "Inputs saved."
info "MySQL: ${DB_USER}@${DB_HOST}:${DB_PORT}/${DB_NAME}"


# ============================================================
# MySQL Check
# ============================================================

section "3 / 7  MySQL Check"

step "Checking MySQL..."

if ! command -v mysql >/dev/null 2>&1; then
    warn "MySQL client not found."

    step "Installing MySQL client..."

    DEBIAN_FRONTEND=noninteractive apt-get install -y default-mysql-client

    if [ $? -ne 0 ]; then
        die "Could not install MySQL client."
    fi
fi


# Check TCP port
if nc -z -w3 "$DB_HOST" "$DB_PORT" >/dev/null 2>&1; then
    ok "MySQL port ${DB_PORT} is reachable."
else
    fail "MySQL is not reachable at ${DB_HOST}:${DB_PORT}."

    echo ""
    info "Current MySQL listeners:"

    ss -lntp | grep 3306 || true

    echo ""

    die "Start MySQL before running this installer."
fi


# Check credentials
step "Checking database login..."

if MYSQL_PWD="$DB_PASS" mysql \
    -h "$DB_HOST" \
    -P "$DB_PORT" \
    -u "$DB_USER" \
    -e "SELECT 1;" >/dev/null 2>&1; then

    ok "MySQL login successful."

else
    fail "Cannot login to MySQL."
    info "Expected user: $DB_USER"
    info "Expected database: $DB_NAME"

    echo ""
    echo "Check the MySQL user/password:"
    echo ""
    echo "  User:     $DB_USER"
    echo "  Password: $DB_PASS"
    echo ""

    exit 1
fi


# Check/create DB
step "Checking database..."

if MYSQL_PWD="$DB_PASS" mysql \
    -h "$DB_HOST" \
    -P "$DB_PORT" \
    -u "$DB_USER" \
    -e "USE \`${DB_NAME}\`;" >/dev/null 2>&1; then

    ok "Database ${DB_NAME} exists."

else
    warn "Database ${DB_NAME} does not exist."

    step "Creating database..."

    if MYSQL_PWD="$DB_PASS" mysql \
        -h "$DB_HOST" \
        -P "$DB_PORT" \
        -u "$DB_USER" \
        -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" >/dev/null 2>&1; then

        ok "Database created."

    else
        die "Could not create database ${DB_NAME}."
    fi
fi


# ============================================================
# 4 / 7 Marzban
# ============================================================

section "4 / 7  Marzban"

if [ ! -d "/opt/marzban" ]; then

    step "Installing Marzban..."

    bash -c "$(curl -sL \
        https://github.com/Gozargah/Marzban-scripts/raw/master/marzban.sh)" @ install

    if [ $? -ne 0 ]; then
        die "Marzban installation failed."
    fi

    ok "Marzban installed."

else

    ok "Existing Marzban installation detected."

fi


# ---------- Docker compose ----------
step "Writing official Docker Compose configuration..."

rm -f /opt/marzban/Dockerfile

cat > /opt/marzban/docker-compose.yml <<'COMPOSE'
services:

  marzban:

    image: gozargah/marzban:latest

    restart: always

    env_file:
      - .env

    network_mode: host

    volumes:
      - /var/lib/marzban:/var/lib/marzban
COMPOSE

ok "Docker Compose ready."


# ============================================================
# 5 / 7 SSL
# ============================================================

section "5 / 7  SSL Certificate"

CERT_DIR="/var/lib/marzban/certs"
CERT_FILE="${CERT_DIR}/fullchain.pem"
KEY_FILE="${CERT_DIR}/privkey.pem"

mkdir -p "$CERT_DIR"


# ---------- DNS ----------
step "Checking DNS..."

DOMAIN_IP=$(dig +short A "$DOMAIN" | tail -n1)

if [ -z "$DOMAIN_IP" ]; then

    die "No DNS A record found for ${DOMAIN}."

fi

info "${DOMAIN} → ${DOMAIN_IP}"


# ---------- acme.sh ----------
ACME="$HOME/.acme.sh/acme.sh"

if [ ! -x "$ACME" ]; then

    step "Installing acme.sh..."

    curl https://get.acme.sh | sh -s email="$EMAIL"

    if [ ! -x "$ACME" ]; then
        die "acme.sh installation failed."
    fi

    ok "acme.sh installed."

else

    ok "acme.sh already installed."

fi


"$ACME" --set-default-ca --server letsencrypt >/dev/null 2>&1 || true


# ---------- Certificate check ----------
step "Checking existing certificate..."

CERT_EXISTS=0

if "$ACME" --list 2>/dev/null \
    | awk 'NR > 1 {print $1}' \
    | grep -Fxq "$DOMAIN"; then

    CERT_EXISTS=1

fi


if [ "$CERT_EXISTS" = "1" ]; then

    ok "Existing SSL certificate found for ${DOMAIN}."

else

    info "No existing certificate found."
    step "Issuing Let's Encrypt certificate..."

    # Port 80 must be free for standalone mode.

    PORT80_PID=$(ss -lntp 2>/dev/null | grep ':80 ' || true)

    if [ -n "$PORT80_PID" ]; then

        warn "Port 80 is currently in use:"
        echo "$PORT80_PID"
        echo ""

        die "Free Port 80 before issuing the certificate."

    fi


    if "$ACME" --issue \
        -d "$DOMAIN" \
        --standalone; then

        ok "SSL certificate issued."

    else

        fail "SSL certificate issuance failed."
        fail "Check:"
        echo "  • DNS A record"
        echo "  • VPS firewall"
        echo "  • Provider firewall"
        echo "  • Port 80"

        exit 1

    fi

fi


# ---------- Install cert ----------
step "Installing SSL certificate for Marzban..."

if "$ACME" --install-cert \
    -d "$DOMAIN" \
    --fullchain-file "$CERT_FILE" \
    --key-file "$KEY_FILE"; then

    chmod 644 "$CERT_FILE"
    chmod 600 "$KEY_FILE"

    ok "SSL certificate installed."

else

    die "Could not install SSL certificate."

fi


if [ ! -s "$CERT_FILE" ]; then
    die "fullchain.pem is missing."
fi

if [ ! -s "$KEY_FILE" ]; then
    die "privkey.pem is missing."
fi

ok "SSL files verified."


# ============================================================
# Subscription template
# ============================================================

step "Installing subscription template..."

mkdir -p /var/lib/marzban/templates/subscription/

wget -q -N \
    -P /var/lib/marzban/templates/subscription/ \
    https://raw.githubusercontent.com/yannaing86tt/template/main/subscription/index.html

if [ $? -eq 0 ]; then
    ok "Subscription template installed."
else
    warn "Could not download custom subscription template."
fi


# ============================================================
# 6 / 7 Environment
# ============================================================

section "6 / 7  Environment"

ENV_FILE="/opt/marzban/.env"

touch "$ENV_FILE"


update_env() {

    local key="$1"
    local value="$2"

    if grep -qE "^[[:space:]]*#?[[:space:]]*${key}[[:space:]]*=" "$ENV_FILE"; then

        sed -i \
            "s|^[[:space:]]*#*[[:space:]]*${key}[[:space:]]*=.*|${key} = \"${value}\"|" \
            "$ENV_FILE"

    else

        echo "${key} = \"${value}\"" >> "$ENV_FILE"

    fi
}


# ---------- DB password URL encoding ----------
DB_PASS_ENC=$(printf '%s' "$DB_PASS" | python3 -c \
'import sys,urllib.parse; print(urllib.parse.quote(sys.stdin.read(),safe=""))')

DB_URL="mysql+pymysql://${DB_USER}:${DB_PASS_ENC}@${DB_HOST}:${DB_PORT}/${DB_NAME}"


step "Writing Marzban environment..."

update_env "UVICORN_HOST" "0.0.0.0"
update_env "UVICORN_PORT" "8000"

update_env "UVICORN_SSL_CERTFILE" "$CERT_FILE"
update_env "UVICORN_SSL_KEYFILE" "$KEY_FILE"

update_env "SQLALCHEMY_DATABASE_URL" "$DB_URL"

update_env "TELEGRAM_API_TOKEN" "$BOT_TOKEN"
update_env "TELEGRAM_ADMIN_ID" "$ADMIN_ID"

update_env "SUB_PROFILE_TITLE" "$SUB_TITLE"

update_env \
    "XRAY_SUBSCRIPTION_URL_PREFIX" \
    "https://${DOMAIN}:8000"

update_env \
    "CUSTOM_TEMPLATES_DIRECTORY" \
    "/var/lib/marzban/templates/"

update_env \
    "SUBSCRIPTION_PAGE_TEMPLATE" \
    "subscription/index.html"


# Remove old typo
sed -i '/^UNICORN_SSL_/d' "$ENV_FILE"

ok ".env configured."


# ============================================================
# Xray
# ============================================================

step "Generating Reality keys..."

KEYS=""

if docker ps -a --format '{{.Names}}' \
    | grep -qx "marzban-marzban-1"; then

    KEYS=$(docker exec marzban-marzban-1 \
        xray x25519 2>/dev/null || true)

fi


if [ -z "$KEYS" ] && \
   docker ps -a --format '{{.Names}}' \
   | grep -qx "marzban-1"; then

    KEYS=$(docker exec marzban-1 \
        xray x25519 2>/dev/null || true)

fi


if [ -z "$KEYS" ]; then

    warn "Xray unavailable in Docker."
    step "Downloading temporary Xray binary..."

    curl -L \
        -o /tmp/xray.zip \
        https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip

    if [ $? -ne 0 ]; then
        die "Could not download Xray."
    fi

    unzip -o /tmp/xray.zip \
        xray \
        -d /tmp/ >/dev/null

    chmod +x /tmp/xray

    KEYS=$(/tmp/xray x25519)

fi


PRIV=$(echo "$KEYS" \
    | awk '/Private key:/ {print $3; exit}')

PUB=$(echo "$KEYS" \
    | awk '/Public key:/ {print $3; exit}')

SID=$(openssl rand -hex 4)


if [ -z "$PRIV" ] || [ -z "$PUB" ]; then

    die "Could not generate Reality keys."

fi

ok "Reality keys generated."


# ============================================================
# Xray config
# ============================================================

step "Writing xray_config.json..."

cat > /var/lib/marzban/xray_config.json <<EOF
{
  "log": {
    "loglevel": "warning"
  },

  "routing": {
    "rules": [
      {
        "type": "field",
        "ip": [
          "geoip:private"
        ],
        "outboundTag": "BLOCK"
      }
    ]
  },

  "inbounds": [

    {
      "tag": "VLESS WS TLS",
      "listen": "0.0.0.0",
      "port": 2083,
      "protocol": "vless",

      "settings": {
        "clients": [],
        "decryption": "none"
      },

      "streamSettings": {

        "network": "ws",
        "security": "tls",

        "tlsSettings": {

          "certificates": [
            {
              "certificateFile": "$CERT_FILE",
              "keyFile": "$KEY_FILE"
            }
          ]

        },

        "wsSettings": {
          "path": "/vless"
        }

      }
    },


    {
      "tag": "VLESS REALITY",
      "listen": "0.0.0.0",
      "port": 443,
      "protocol": "vless",

      "settings": {
        "clients": [],
        "decryption": "none"
      },

      "streamSettings": {

        "network": "tcp",
        "security": "reality",

        "realitySettings": {

          "show": false,

          "dest": "www.cloudflare.com:443",

          "xver": 0,

          "serverNames": [
            "www.cloudflare.com"
          ],

          "privateKey": "$PRIV",

          "publicKey": "$PUB",

          "shortIds": [
            "$SID"
          ]

        }

      },

      "sniffing": {

        "enabled": true,

        "destOverride": [
          "http",
          "tls"
        ]

      }

    },


    {
      "tag": "VMess WS TLS",
      "listen": "0.0.0.0",
      "port": 8443,
      "protocol": "vmess",

      "settings": {
        "clients": []
      },

      "streamSettings": {

        "network": "ws",
        "security": "tls",

        "tlsSettings": {

          "certificates": [
            {
              "certificateFile": "$CERT_FILE",
              "keyFile": "$KEY_FILE"
            }
          ]

        },

        "wsSettings": {
          "path": "/vmess"
        }

      }
    },


    {
      "tag": "Trojan TLS",
      "listen": "0.0.0.0",
      "port": 2053,
      "protocol": "trojan",

      "settings": {
        "clients": []
      },

      "streamSettings": {

        "network": "tcp",
        "security": "tls",

        "tlsSettings": {

          "certificates": [
            {
              "certificateFile": "$CERT_FILE",
              "keyFile": "$KEY_FILE"
            }
          ]

        }

      }

    },


    {
      "tag": "VLESS TCP",
      "listen": "0.0.0.0",
      "port": 9850,
      "protocol": "vless",

      "settings": {
        "clients": [],
        "decryption": "none"
      },

      "streamSettings": {
        "network": "tcp",
        "security": "none"
      },

      "sniffing": {

        "enabled": true,

        "destOverride": [
          "http",
          "tls"
        ]

      }

    },


    {
      "tag": "VMESS TCP",
      "listen": "0.0.0.0",
      "port": 4427,
      "protocol": "vmess",

      "settings": {
        "clients": []
      },

      "streamSettings": {
        "network": "tcp",
        "security": "none"
      },

      "sniffing": {

        "enabled": true,

        "destOverride": [
          "http",
          "tls"
        ]

      }

    },


    {
      "tag": "TROJAN TCP",
      "listen": "0.0.0.0",
      "port": 9094,
      "protocol": "trojan",

      "settings": {
        "clients": []
      },

      "streamSettings": {
        "network": "tcp",
        "security": "none"
      }

    },


    {
      "tag": "Shadowsocks TCP UDP",
      "listen": "0.0.0.0",
      "port": 1080,
      "protocol": "shadowsocks",

      "settings": {
        "clients": [],
        "network": "tcp,udp"
      }

    }

  ],

  "outbounds": [

    {
      "protocol": "freedom",
      "tag": "DIRECT"
    },

    {
      "protocol": "blackhole",
      "tag": "BLOCK"
    }

  ]

}
EOF

ok "Xray configuration written."


# ============================================================
# 7 / 7 Finalize
# ============================================================

section "7 / 7  Finalize"

step "Starting Marzban..."

cd /opt/marzban || exit 1

docker compose pull

docker compose up -d --force-recreate

if [ $? -ne 0 ]; then
    die "Docker Compose failed."
fi


# ---------- Wait ----------
step "Waiting for Marzban..."

READY=0

for i in $(seq 1 30); do

    if docker compose ps 2>/dev/null \
        | grep -q "Up"; then

        READY=1
        break

    fi

    sleep 2

done


if [ "$READY" != "1" ]; then

    fail "Marzban did not start correctly."

    echo ""
    docker compose logs --tail=100

    exit 1

fi

ok "Marzban container is running."


# ---------- Check restart loop ----------
sleep 5

if docker compose ps \
    | grep -qi "Restarting"; then

    fail "Marzban is restarting."

    docker compose logs --tail=100

    exit 1

fi


# ---------- Admin ----------
step "Creating admin user..."

if marzban cli admin create \
    --username "$ADMIN_USER" \
    --password "$ADMIN_PASS" \
    --sudo; then

    ok "Admin user created."

else

    warn "Admin creation skipped."
    warn "The account may already exist."

fi


# ---------- Cleanup ----------
rm -f /tmp/xray.zip \
      /tmp/xray \
      2>/dev/null || true


# ============================================================
# Finished
# ============================================================

echo ""
line

echo -e "${GREEN}${BOLD}  ✓ Setup complete${RESET}"

line

echo ""
echo -e "  ${BOLD}Dashboard${RESET}"
echo -e "  https://${DOMAIN}:8000/dashboard"
echo ""

echo -e "  ${BOLD}Username${RESET}"
echo -e "  ${ADMIN_USER}"
echo ""

echo -e "  ${BOLD}Database${RESET}"
echo -e "  ${DB_USER}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
echo ""

echo -e "  ${BOLD}SSL Certificate${RESET}"
echo -e "  ${CERT_FILE}"
echo ""

echo -e "  ${BOLD}SSL Private Key${RESET}"
echo -e "  ${KEY_FILE}"
echo ""

echo -e "  ${BOLD}Xray Config${RESET}"
echo -e "  /var/lib/marzban/xray_config.json"
echo ""

line

echo ""
echo -e "${GREEN}Open the dashboard and create your users.${RESET}"
echo ""
