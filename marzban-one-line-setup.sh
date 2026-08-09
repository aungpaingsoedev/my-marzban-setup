#!/bin/bash

# Clear screen
clear

# --- Banner Section ---
echo -e "\e[1;36m"
echo "       █████╗ ██████╗ ███████╗"
echo "      ██╔══██╗██╔══██╗██╔════╝"
echo "      ███████║██████╔╝███████╗"
echo "      ██╔══██║██╔═══╝ ╚════██║"
echo "      ██║  ██║██║     ███████║"
echo "      ╚═╝  ╚═╝╚═╝     ╚══════╝"
echo -e "\e[0m"
echo "           Marzban One Line Setup"
echo "--------------------------------------------------"
echo -e "\e[1;33m  Installing Protocols:\e[0m"
echo "  🔹 VLESS (Reality & WS TLS)"
echo "  🔹 VMess (WS TLS & TCP)"
echo "  🔹 Trojan (TLS & TCP)"
echo "  🔹 Shadowsocks"
echo "--------------------------------------------------"

# Necessary Package Check
echo "📦 Checking necessary packages..."
sudo apt update && sudo apt install -y curl socat wget sed unzip

# Inputs
read -p "Enter Domain Name (e.g., mar.example.com): " DOMAIN
read -p "Enter Email for SSL: " EMAIL
read -p "Enter Telegram Bot Token: " BOT_TOKEN
read -p "Enter Telegram Admin ID: " ADMIN_ID
read -p "Enter Subscription Title: " SUB_TITLE
read -p "Create Admin Username: " ADMIN_USER
read -s -p "Create Admin Password: " ADMIN_PASS
echo -e "\n--------------------------------------------------"

echo "🚀 Installing Marzban..."
sudo bash -c "$(curl -sL https://github.com/Gozargah/Marzban-scripts/raw/master/marzban.sh)" @ install

echo "🔐 Generating SSL Certificates..."
sudo bash -c "$(curl -sL https://raw.githubusercontent.com/erfjab/ESSL/master/essl.sh)" @ --install
sudo essl "$EMAIL" "$DOMAIN" marzban

echo "🎨 Setting up Custom Template..."
sudo mkdir -p /var/lib/marzban/templates/subscription/
sudo wget -N -P /var/lib/marzban/templates/subscription/ https://raw.githubusercontent.com/yannaing86tt/template/main/subscription/index.html

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

echo "📝 Updating .env configuration..."
update_env "UVICORN_HOST" "0.0.0.0"
update_env "UVICORN_PORT" "8000"
update_env "UVICORN_SSL_CERTFILE" "/var/lib/marzban/certs/$DOMAIN/fullchain.pem"
update_env "UVICORN_SSL_KEYFILE" "/var/lib/marzban/certs/$DOMAIN/privkey.pem"
update_env "TELEGRAM_API_TOKEN" "$BOT_TOKEN"
update_env "TELEGRAM_ADMIN_ID" "$ADMIN_ID"
update_env "SUB_PROFILE_TITLE" "$SUB_TITLE"
update_env "XRAY_SUBSCRIPTION_URL_PREFIX" "https://$DOMAIN:8000"
update_env "CUSTOM_TEMPLATES_DIRECTORY" "/var/lib/marzban/templates/"
update_env "SUBSCRIPTION_PAGE_TEMPLATE" "subscription/index.html"

# Remove any old typo entries
sudo sed -i "/^UNICORN_SSL_/d" "$ENV_FILE"

echo "🔑 Reality Keys ထုတ်နေပါတယ်..."

# --- Get Reality Keys ---
KEYS=$(docker exec marzban-marzban-1 xray x25519 2>/dev/null || docker exec marzban-1 xray x25519 2>/dev/null)

if [ -z "$KEYS" ]; then
    echo "🌐 Docker ထဲမှာ xray မရှိလို့ အပြင်ကနေ Download ဆွဲနေပါတယ်..."
    curl -L -o /tmp/xray.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip &>/dev/null
    unzip -o /tmp/xray.zip xray -d /tmp/ &>/dev/null
    chmod +x /tmp/xray
    KEYS=$(/tmp/xray x25519)
fi

PRIV=$(echo "$KEYS" | grep "Private key" | cut -d ' ' -f 3)
PUB=$(echo "$KEYS" | grep "Public key" | cut -d ' ' -f 3)
SID=$(openssl rand -hex 4)

if [ -z "$PRIV" ]; then
    echo -e "\e[1;31m❌ Error: Reality Keys ထုတ်လို့ မရခဲ့ပါ။\e[0m"
    exit 1
fi

echo -e "\e[1;32m✅ Keys Generated Successfully.\e[0m"

# --- Create xray_config.json ---
echo "📡 Configuring protocols..."
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
                        "certificateFile": "/var/lib/marzban/certs/$DOMAIN/fullchain.pem",
                        "keyFile": "/var/lib/marzban/certs/$DOMAIN/privkey.pem"
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
                        "certificateFile": "/var/lib/marzban/certs/$DOMAIN/fullchain.pem",
                        "keyFile": "/var/lib/marzban/certs/$DOMAIN/privkey.pem"
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
                        "certificateFile": "/var/lib/marzban/certs/$DOMAIN/fullchain.pem",
                        "keyFile": "/var/lib/marzban/certs/$DOMAIN/privkey.pem"
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

echo "✅ JSON File Updated."

echo "🔄 Restarting Marzban to apply changes..."
marzban restart

# Cleanup
rm -rf /tmp/xray.zip /tmp/xray 2>/dev/null

# Wait for Marzban to wake up before creating admin
sleep 5

echo "👤 Creating Admin User..."
marzban cli admin create --username "$ADMIN_USER" --password "$ADMIN_PASS" --sudo || echo "Admin setup skipped."

echo "--------------------------------------------------"
echo -e "\e[1;32m🔥 Protocols Configuration Complete! 🔥\e[0m"
echo -e "\e[1;32m✅ Installation Completed Successfully!\e[0m"
echo "🌐 Dashboard: https://$DOMAIN:8000/dashboard"
echo "👤 Username: $ADMIN_USER"
echo "--------------------------------------------------"
