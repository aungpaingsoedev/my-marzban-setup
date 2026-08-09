# Marzban One Line Setup (APS)

ဒီ script က [Marzban](https://github.com/Gozargah/Marzban) ကို တစ်ကြိမ်တည်းနဲ့ အလိုအလျောက် install လုပ်ပေးပါတယ်။

SSL၊ Telegram bot၊ subscription template၊ protocol တွေနဲ့ **remote MySQL** ပါ အဆင်သင့် ပြင်ပေးပါတယ်။

## ဘာတွေ လုပ်ပေးလဲ

- Marzban install
- SSL certificate ထုတ်
- `.env` ဖိုင် ပြင်
- Remote MySQL database ချိတ်
- Subscription page template ထည့်
- Admin account ဖန်တီး
- Reality key ထုတ်ပြီး `xray_config.json` ရေး

### Protocol များ

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

## လိုအပ်ချက်များ

- Ubuntu / Debian VPS
- Root (သို့) `sudo` အသုံးပြုခွင့်
- Domain ကို server IP နဲ့ ချိတ်ထားရမယ်
- တခြား server ပေါ်က MySQL (remote access ဖွင့်ထားရမယ်)
- Telegram Bot Token နဲ့ Admin ID (လိုချင်ရင်)

## ဘယ်လို run မလဲ

```bash
bash <(curl -sL https://raw.githubusercontent.com/aungpaingsoedev/my-marzban-setup/main/marzban-one-line-setup.sh)
```

သို့မဟုတ် local မှာ:

```bash
chmod +x marzban-one-line-setup.sh
sudo ./marzban-one-line-setup.sh
```

## မေးမယ့် အချက်များ

1. Domain name (ဥပမာ `mar.example.com`)
2. SSL အတွက် Email
3. Telegram Bot Token
4. Telegram Admin ID
5. Subscription title
6. Admin username
7. Admin password

> MySQL က script ထဲမှာ သတ်မှတ်ထားပါတယ် (`130.94.42.207` / `marzban`).

## Install ပြီးရင်

- **Dashboard:** `https://YOUR_DOMAIN:8000/dashboard`
- **Config:** `/var/lib/marzban/xray_config.json`
- **Env:** `/opt/marzban/.env`
- **SSL:** `/var/lib/marzban/certs/YOUR_DOMAIN/`

Marzban restart လုပ်ချင်ရင်:

```bash
marzban restart
```

## မှတ်ချက်

- Port **443** က VLESS Reality အတွက် သုံးပါတယ်။ Firewall မှာ port တွေ ဖွင့်ထားပါ။
- MySQL server မှာ Marzban VPS IP ကနေ remote connect ခွင့်ပြုထားရမယ်။
- Reality key တွေကို run တိုင်း အသစ် ထုတ်ပေးပါတယ်။
- Script ကို ပြန် run ရင် `xray_config.json` ကို overwrite လုပ်ပါမယ်။
