# ⚠️ لطفا از پروژه جدید استفاده کنید https://github.com/Sir-MmD/vpn-ui

## [English](/README.md) | [فارسی](/README_fa.md)
# RTX-VPN v2 + SoftEther
# L2TP/OpenVPN/SSTP Server with Rathole + Tun2socks + Xray + Tunnel + SoftEther
# RTX-VPN = (Rathole-tun2socks-Xray) VPN
![App Screenshot](https://raw.githubusercontent.com/Sir-MmD/RTX-VPN/refs/heads/v2/menu.png)

## این اسکریپت  چی هستش؟
این اسکریپت یک راه حل برای راه اندازی تانل و سرور L2TP/OpenVPN/SSTP به همراه SoftEther در مناطق محدود شده هستش (مثل ایران و چین)

## پروتکل های پشتیبانی شده
- L2TP
- L2TP/IPSec
- OpenVPN
- SSTP
- Radius (برای مدیریت اکانت حرفه ای)

## دیاگرام
![App Screenshot](https://raw.githubusercontent.com/Sir-MmD/RTX-VPN/refs/heads/v2/diagram.png)

## چجوری کار میکنه؟
به دو سرور نیاز داریم: یک سرور برای کانکشن ورودی ترافیک L2TP/OpenVPN/SSTP به همراه SoftEther (سرور ایران) و یکی برای سرور Edge (سرور خارج). سرور اول (سرور تانل) سروری هستش که محدودیتی در اتصال ورودی L2TP/OpenVPN/SSTP در اون برخلاف سرور Edge (سرور خارج) که نمیشه بصورت مستقیم بهش متصل شد وجود نداره.

سرور Edge اولین کانکشن رو به سرور تانل بصورت Reverse (توسط Rathole) با استفاده از VLESS + WebSocket(WS) توسط Xray-Core ایجاد میکنه، که یک پروکسی SOCKS5 روی سرور تانل (ایران) مهیا میشه. حالا با استفاده از tun2socks ترافیک این پروکسی SOCKS5 رو به یک کارت شبکه مجازی انتقال میدیم.

و در آخر با استفاده از Policy-Based Routing (PBR) ترافیک ورودی L2TP/OpenVPN/SSTP رو به کارت شبکه مجازی که توسط tun2socks ایجاد شده بود هدایت میکنیم.

## دونیت
🔹USDT-TRC20: ```TEUsjU22rAb3TZNaecEBJAhZXQsFZYU7vv```

🔹TRX: ```TEUsjU22rAb3TZNaecEBJAhZXQsFZYU7vv```

🔹LTC: ```LS7rJ6nMWwgw9FWpMjSnYa1bAPdzK7bJLM```

🔹BTC: ```1D4cSHY95FoHExSicKYmjeVzdLLxhjTTqs```

🔹ETH: ```0x03fde84612e0d572db7a18efeeec590ad3fa5dfb```

## آموزش نصب
https://www.youtube.com/watch?v=TbIPd9ni1PU

## نصب
```bash
sh -c "$(wget https://raw.githubusercontent.com/Sir-MmD/RTX-VPN/v2/rtxvpn_v2.sh -O -)"
```

## سیستم عامل های پشتیبانی شده
این اسکریپت از تمامی سیستم عامل های Debian بیس که از systemd استفاده میکنند پشتیبانی میکنه

## تست سرعت
![App Screenshot](https://raw.githubusercontent.com/Sir-MmD/RTX-VPN/refs/heads/v2/speedtest.jpg)

## حل مشکل اتصال OpenVPN
کانفیگ OpenVPN تهیه شده از SoftEther از cipher قدیمی استفاده میکنه که برای حل این موضوع باید این متن رو زیر ```cipher AES-128-CBC``` در فایل کانفیگتون وارد کنید:
```bash
data-ciphers AES-128-CBC:AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305
```
همچنین توصیه میشه قسمت ```remote address``` رو با IP سرور یا دامنه شخصی جایگزین کنید

## تنظیمات توصیه شده برای SoftEther
- غیرفعال کردن DDNS سرور: ```declare DDnsClient: bool Disabled true```
- غیر فعال کردن WebUI سرور: ```bool DisableJsonRpcWebApi true```
- حذف پورت های غیر نیاز

## تنظیمات تانل: Xray-core
این اسکریپت بصورت پیشفرض از کانفیگ 'VLESS + WS' برای Xray-Core استفاده میکنه. میتونید کانفیگ دلخواهتون رو در ```/opt/rtxvpn_v2/edge/edge.json``` برای سرور Edge (خارج) و ```/opt/rtxvpn_v2/tunnel/tunnel.json``` برای سرور تانل (ایران) اعمال کنید

## تنظیمات تانل: rathole
شما همچنین میتونید تنظیمات مربوط به تانل rathole رو در مسیر ```/opt/rtxvpn_v2/edge/edge.toml``` برای سرور Edge (خارج) و ```/opt/rtxvpn_v2/tunnel/tunnel.toml``` برای سرور تانل (ایران) اعمال کنید

## سرویس های Systemd: سرور Edge (خارج)
RTX-VPN (Rathole + Xray): ```rtxvpn.service```

## سرویس های Systemd: سرور تانل (ایران)
RTX-VPN (Rathole + Tun2socks + Xray + PBR): ```rtxvpn.service```

SoftEther: ```softether.service```

Dnsmasq: ```dnsmasq.service```

## CopyRight
SoftEther: https://www.softether.org

Rathole: https://github.com/rapiz1/rathole

Tun2socks: https://github.com/bedefaced/vpn-install

Xray-Core: https://github.com/XTLS/Xray-core
