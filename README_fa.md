# لطفا از نسخه 2 استفاده کنید: https://github.com/Sir-MmD/RTX-VPN/tree/v2
#
## [English](/README.md) | [فارسی](/README_fa.md)
# L2TP/OpenVPN Server with Xray + Rathole + tun2socks Tunnel
# RTX-VPN = (Rathole-tun2socks-Xray) VPN
![App Screenshot](https://raw.githubusercontent.com/Sir-MmD/RTX-VPN/refs/heads/v1/screenshots/menu.png)
## این اسکریپت چی هستش؟

این اسکریپت یک راه حل برای راه اندازی تانل و سرور L2TP/OpenVPN در مناطق محدود شده هستش (مثل ایران و چین)

هدف ایجاد یک تانل Xray-Core بصورت Reverse شده (توسط rathole) هستش تا ترافیک قابل شناسایی نباشه

و البته دوستانی که نیاز به کانکشن L2TP/OpenVPN برای راه اندازی اینترنت آزاد روی مودم دارند میتونند از این اسکریپت نهایت استفاده رو ببرند!

## دیاگرام:
![App Screenshot](https://raw.githubusercontent.com/Sir-MmD/RTX-VPN/refs/heads/v1/diagram.PNG)

## چطوری کار میکنه؟
به دو سرور نیاز داریم: یک سرور برای کانکشن ورودی ترافیک L2TP/OpenVPN (سرور ایران) و یکی برای سرور Edge (سرور خارج). سرور اول (سرور تانل) سروری هستش که محدودیتی در اتصال ورودی L2TP/OpenVPN در اون برخلاف سرور Edge (سرور خارج) که نمیشه بصورت مستقیم بهش متصل شد وجود نداره.

سرور Edge اولین کانکشن رو به سرور تانل بصورت Reverse با استفاده از VLESS + WebSocket(WS) توسط Xray-Core ایجاد میکنه، که یک پروکسی SOCKS5 روی سرور تانل (ایران) مهیا میشه. حالا با استفاده از tun2socks ترافیک این پروکسی SOCKS5 رو به یک کارت شبکه مجازی انتقال میدیم.

و در آخر با استفاده از Policy-Based Routing (PBR) ترافیک ورودی L2TP/OpenVPN رو به کارت شبکه مجازی که توسط tun2socks ایجاد شده بود هدایت میکنیم.

## دونیت
🔹USDT-TRC20: ```TEUsjU22rAb3TZNaecEBJAhZXQsFZYU7vv```

🔹TRX: ```TEUsjU22rAb3TZNaecEBJAhZXQsFZYU7vv```

🔹LTC: ```LS7rJ6nMWwgw9FWpMjSnYa1bAPdzK7bJLM```

🔹BTC: ```1D4cSHY95FoHExSicKYmjeVzdLLxhjTTqs```

🔹ETH: ```0x03fde84612e0d572db7a18efeeec590ad3fa5dfb```

## آموزش نصب
https://youtu.be/Djc6CfClCvM
## نصب
```bash
git clone -b v1 https://github.com/Sir-MmD/RTX-VPN.git
chmod -R +x RTX-VPN
cd RTX-VPN
./rtxvpn_setup.sh
```
## مدیریت کاربر ها
```bash
./rtxvpn_manage.sh
```
## سیستم عامل های پشتیبانی شده
این اسکریپت از تمامی سیستم عامل های Debian بیس که از systemd استفاده میکنند پشتیبانی میکنه

## تنظیمات تانل: Xray-core
این اسکریپت بصورت پیشفرض از کانفیگ 'VLESS + WS' برای Xray-Core استفاده میکنه. میتونید کانفیگ دلخواهتون رو در ```/opt/xray_edge.json``` برای سرور Edge (خارج) و ```/opt/xray_tunnel.json``` برای سرور تانل (ایران) اعمال کنید
## تنظیمات تانل: rathole
شما همچنین میتونید تنظیمات مربوط به تانل rathole رو در مسیر ```/opt/rathole_edge.toml``` برای سرور Edge (خارج) و ```/opt/rathole_tunnel.toml``` برای سرور تانل (ایران) اعمال کنید
## نکته مهم
به هیچ عنوان ip pool مربوط به vpn server هارو تغییر ندید! اما اگر تغییری ایجاد کردید، حتما باید ip pool جدید در ```rtxvpn_setup.sh``` هم اعمال بشه

## سرویس های Systemd: سرور تانل (ایران)
tun2socks L2TP Routing: ```tun2socks_l2tp_setup.service```

tun2socks Interface for L2TP Service: ```tun2socks_l2tp_interface.service```

tun2socks OpenVPN Routing Service: ```tun2socks_openvpn_setup.service```

tun2socks Interface for OpenVPN Service: ```tun2socks_openvpn_interface.service```

Xray-Core Tunnel Service: ```xray_tunnel.service```

rathole Tunnel Service: ```rathole_tunnel.service```

## سرویس های Systemd: سرور Edge (خارج)
Xray-Core Edge Service: ```xray_edge.service```

rathole Edge Service: ```rathole_edge.service```

## تست سرعت: L2TP
![App Screenshot](https://raw.githubusercontent.com/Sir-MmD/RTX-VPN/refs/heads/v1/screenshots/l2tp/speedtest.jpg)
## تست سرعت: OpenVPN
![App Screenshot](https://raw.githubusercontent.com/Sir-MmD/RTX-VPN/refs/heads/v1/screenshots/openvpn/speedtest.jpg)
## نکته: پهنای باند اینترنتی که با اون تست شده دارای 35 مگابیت دانلود و 9 مگابیت آپلود بوده

همچنین عکس تست DNS Leak از سایت https://dnsleaktest.com موجوده که میتونید به پوشه 'screenshots' مراجعه کنید
## کپی رایت
اسکریپت نصب L2TP:

https://github.com/bedefaced/vpn-install

اسکریپت نصب OpenVPN:

https://github.com/angristan/openvpn-install

Xray-Core: https://github.com/XTLS/Xray-core

rathole: https://github.com/rapiz1/rathole

tun2socks: https://github.com/bedefaced/vpn-install
