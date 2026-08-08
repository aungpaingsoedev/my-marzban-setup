# Marzban One Line Setup (APS)

One-line installer for [Marzban](https://github.com/Gozargah/Marzban) with SSL, Telegram bot, custom subscription template, and multi-protocol Xray config.

## Features

- Installs Marzban automatically
- Issues SSL certificate via ESSL
- Configures `.env` (dashboard TLS, Telegram, subscription)
- Custom subscription page template
- Creates admin user
- Generates Reality keys and writes `xray_config.json`

### Protocols included

| Protocol | Mode | Port |
|----------|------|------|
| VLESS | Reality | 443 |
| VLESS | WS + TLS | 2083 |
| VLESS | TCP | 9850 |
| VMess | WS + TLS | 8443 |
| VMess | TCP | 4427 |
| Trojan | TLS | 2053 |
| Trojan | TCP | 9094 |
| Shadowsocks | TCP/UDP | 1080 |

## Requirements

- Ubuntu / Debian VPS
- Root (or `sudo`) access
- Domain pointed to the server IP
- Telegram Bot Token & Admin ID (optional but prompted)

## Quick Start

```bash
bash <(curl -sL https://raw.githubusercontent.com/YOUR_USER/marzban-one-line-setup/main/marzban-one-line-setup.sh)
```

Or run locally:

```bash
chmod +x marzban-one-line-setup.sh
sudo ./marzban-one-line-setup.sh
```

## What you will be asked

1. Domain name (e.g. `mar.example.com`)
2. Email for SSL
3. Telegram Bot Token
4. Telegram Admin ID
5. Subscription title
6. Admin username
7. Admin password

## After install

- **Dashboard:** `https://YOUR_DOMAIN:8000/dashboard`
- **Config file:** `/var/lib/marzban/xray_config.json`
- **Env file:** `/opt/marzban/.env`
- **SSL certs:** `/var/lib/marzban/certs/YOUR_DOMAIN/`

Restart Marzban anytime:

```bash
marzban restart
```

## Notes

- Port **443** is used by VLESS Reality; open the listed ports in your firewall.
- Reality short ID and keys are generated on each run.
- Re-running the script will overwrite `xray_config.json` with a fresh config.
