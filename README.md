<div align="center">

# 🎭 Opera-Proxy для Keenetic / Entware

**Меню управления SOCKS5-прокси на базе Opera VPN**

`menu-opera.sh` — интерактивный shell-скрипт для установки, настройки и диагностики
[opera-proxy](https://github.com/Alexey71/opera-proxy) на роутерах Keenetic с Entware.

![Version](https://img.shields.io/badge/меню-1.3.44-green?style=for-the-badge)
![Platform](https://img.shields.io/badge/платформа-Keenetic%20%2F%20Entware-blue?style=for-the-badge)
![Shell](https://img.shields.io/badge/sh-posix%20(sh%2C%20ash%2C%20bash)-informational?style=for-the-badge&logo=gnubash&logoColor=white)
![License](https://img.shields.io/badge/статус-поддержка%20активна-brightgreen?style=for-the-badge)

</div>

---

## 📋 О проекте

Скрипт разворачивает и обслуживает локальный **SOCKS5-прокси** на серверах Opera VPN
(регионы EU / AS / AM) и связывает его с интерфейсом **t2sN (ProxyN)** Keenetic/NDM.

Основные возможности:

- 🚀 Установка из репозитория `sw.ext.io` или **UPX-сжатой** версии (GitHub Actions этого репозитория)
- 🔧 Конфиг `/opt/etc/opera-proxy.conf` (COUNTRY, SNI/DoH, BIND, API_PROXY, PING_CHECK, ROUTE_*)
- 🔍 Диагностика: myip.wtf, 2ip.io, Telegram, Google (t2sN); geo API_PROXY через ip-api.com
- 🛠 **Починка туннеля** — подбор socks5 api-proxy, cron раз в час
- 🛣 **Статические маршруты** `77.111.244/24` + `77.111.247/24` через VPN (без API_PROXY) для обхода DPI к API/endpoint’ам Opera
- 🔄 Самообновление скрипта `[99]` с зеркалами (ghfast / gh-proxy)

> Идеи и дизайн частично из
> [rndnaame/awg-compressed](https://github.com/rndnaame/awg-compressed) и
> [Libziks/Opera-proxy](https://github.com/Libziks/Opera-proxy).

---

## ⚡ Быстрый старт

SSH (root) на роутер:

```sh
curl -sL https://raw.githubusercontent.com/rndnaame/opera-proxy/main/menu-opera.sh | sh
```

Если GitHub недоступен — зеркало:

```sh
curl -sL https://ghfast.top/https://raw.githubusercontent.com/rndnaame/opera-proxy/main/menu-opera.sh | sh
```

Или файл на роутер:

```sh
scp menu-opera.sh root@192.168.1.1:/tmp/
sh /tmp/menu-opera.sh
```

**Требования:** Entware (`/opt`), `curl`, `ndmc`, порт **18080** (по умолчанию).

---

## 🧭 Главное меню

| Пункт | Действие | Описание |
|:-----:|----------|----------|
| **[1]** | Установить Opera-proxy | `sw.ext.io` или UPX с GitHub; conf + ProxyN/t2sN |
| **[2]** | Обновить Opera-proxy (opkg) | `opkg update` / upgrade, при необходимости `--force-downgrade` |
| **[3]** | Починить туннель | t2s / SOCKS / подбор api-proxy + cron hourly |
| **[4]** | Остановить / Запустить сервис | init.d + up/down t2sN |
| **[5]** | Проверить прокси | SOCKS + t2sN + Telegram + Google + geo API_PROXY |
| **[6]** | Настройка конфига | COUNTRY, BIND, SNI/DoH, API_PROXY, PING_CHECK, **маршруты [r]** |
| **[88]** | Удалить | пакет, Proxy по description, опционально маршруты / fix / repo |
| **[99]** | Обновить скрипт | `menu-opera.sh` с GitHub (+ зеркала) |
| **[0]** | Выход | |

---

## 🛣 Маршруты Opera — пункт [6] → [r]

При блокировке DPI registration/discover к `api2.sec-tunnel.com` и endpoint’ам `77.111.*`
можно направить эти сети в уже работающий VPN (WARP / AWG / OpkgTun) **без API_PROXY**.

**Сети по умолчанию:**

```text
77.111.247.0/24
77.111.244.0/24
```

**Команда (ndmc):**

```text
ip route <net> <mask> <WireguardN|OpkgTunN> auto
```

- **`auto`** — «Добавлять автоматически» (маршрут активен, когда интерфейс доступен)
- **comment `Opera`** — через RCI
- **несколько интерфейсов** (`1,2`) — failover: при down одного остаётся маршрут через другой

**Поддерживаемые интерфейсы** (в sysfs + RCI, только с **global ≠ false**):

| Linux | NDMS (ndmc) |
|-------|-------------|
| `nwgN` | `WireguardN` |
| `WireguardN` | как есть |
| `opkgtunN` | `OpkgTunN` |
| `awgN` / `awgmN` | как есть |

Параметры в conf:

```sh
ROUTE_VIA="nwg0"          # или "nwg0 nwg1"
ROUTE_NETS="77.111.247.0/24 77.111.244.0/24"
```

Подменю **[r]:**

| | |
|--|--|
| **[1]** | Выбрать iface(ы) и применить |
| **[2]** | Снять маршруты Opera |
| **[3]** | Статус (running-config 77.111) |
| **[4]** | Отключить API_PROXY |

Рекомендуется с маршрутами **отключить API_PROXY** и перезапустить сервис (**[s]** / **[4]**).

---

## 🔍 Пункт [5] — проверка прокси

Сводка `N/5` (или меньше, если без API_PROXY):

1. **myip.wtf** — через SOCKS `127.0.0.1:BIND_PORT`
2. **2ip.io** — через SOCKS
3. **Telegram** (`web.telegram.org`) — SOCKS + DNS через прокси
4. **Google** connectivity — через **t2sN** (`--interface`)
5. **API_PROXY** — geo через **ip-api.com** (IP, country, city)

Показываются статус сервиса, SOCKS-порт, состояние t2s / ProxyN.

---

## ⚙️ Пункт [6] — настройка конфига

```text
[1] COUNTRY          EU | AS | AM
[2] BIND_ADDR        127.0.0.1 | 0.0.0.0
[3] BIND_PORT        + синхронизация upstream t2sN
[4] OBFUSCATE + FAKE_SNI
[5] BOOTSTRAP_DNS    DoH
[6] SERVER_SELECT    random | fastest
[7] VERBOSITY
[8] API_PROXY        вручную / подбор / проверка / отключить
[9] PING_CHECK       default | custom (9.9.9.9:53)
[r] Маршруты Opera   77.111.* → VPN
[l] Показать conf
[s] Сохранить + restart
[x] Сброс к шаблону (без API_PROXY)
```

Файл: `/opt/etc/opera-proxy.conf` — после правок `OPTIONS` пересобирается автоматически.

---

## 🔧 Пункт [3] — починка туннеля

1. Проверка IP / Telegram через **t2sN**
2. При необходимости — локальный SOCKS `127.0.0.1:18080`
3. Если SOCKS мёртв — **подбор api-proxy** из кэша/публичных списков (параллельно)
4. Успешный socks5 пишется в conf, сервис перезапускается, ProxyN поднимается
5. Ставится **cron hourly**: `/opt/etc/cron.hourly/fix_opera_tunnel`

Скрипт `/opt/fix_opera_tunnel.sh` обновляется из меню только если содержимое изменилось
(меньше записей на flash).

---

## 📦 Установка и пакеты

- **Официальный IPK:** `http://sw.ext.io/ent/<arch>/` (aarch64 / mipsel / mips)
- **UPX:** релизы этого репозитория (`*_compressed.ipk`), CI перепаковывает с sw.ext.io
  и при необходимости подменяет bin из [Alexey71/opera-proxy](https://github.com/Alexey71/opera-proxy/releases)

Архитектуры Entware: `aarch64-3.10`, `mipsel-3.4`, `mips-3.4` (и варианты `_kn`).

---

## 📜 История версий меню (`menu-opera.sh`)

| Версия | Изменения |
|--------|-----------|
| **1.3.44** | test SOCKS после SNI: retry ~25 с (без ложных FAIL) |
| **1.3.43** | FAKE_SNI: пресеты, авто OBFUSCATE, тест SOCKS / перебор |
| **1.3.42** | статус: Режим API/маршруты; [r] apply → API off+restart; iface «без global» |
| **1.3.41** | [6] конфиг: пункты в таблице ([1]…[9]/[P]/[R]) |
| **1.3.40** | Маршруты: **nwg / Wireguard / opkgtun / awg**, фильтр RCI **global** |
| **1.3.39** | Маршруты: **auto** + comment **Opera**; multi-iface failover (`1,2`) |
| **1.3.38** | Только ndmc (без .bat); имена туннелей в выборе |
| **1.3.37** | Маршруты `77.111.244/247/24` через VPN, пункт **[6]→[r]** |
| **1.3.36** | Install: IPK с sw.ext.io + `--force-downgrade` |
| **1.3.35** | `--force-downgrade` при понижении версии |
| **1.3.34** | Fix: `apply_api_proxy` сохраняет `PING_CHECK` |
| **1.3.33** | `PING_CHECK`: default \| custom (9.9.9.9:53) |
| **1.3.32** | Fix recovery: 3 раунда, до 5 кандидатов |
| **1.3.31** | Кэш socks5: refresh если &lt;300 или старше 6 ч |
| **1.3.30** | Не перезаписывать fix-скрипт, если без изменений |
| **1.3.25+** | Параллельный отбор socks5; компактные логи; t2s-first логика |
| **1.3.14+** | API_PROXY: проверка / отключение; conf без legacy if-блока |
| **1.3.0** | Базовая линия 1.3.x (меню, fix, conf SNI/DoH) |
| **1.2.x** | syslog-wrapper, setsid (CTRL+C), t2s up/down |
| **1.1.x** | conf-меню, проверка через SOCKS, Proxy по description |
| **1.0.0** | Базовое меню install / Fix / check / remove / [99] |

Полный построчный changelog — в шапке `menu-opera.sh`.

---

## ⚠️ Дисклеймер

Проект использует публичные серверы Opera VPN. Это **не официальный** сервис Opera:
без гарантий доступности, скорости и конфиденциальности. Не передавайте через туннель
чувствительные данные без дополнительного шифрования. Используйте на свой страх и риск
и соблюдайте законодательство вашей страны.

---

## 🙏 Благодарности

- [Alexey71/opera-proxy](https://github.com/Alexey71/opera-proxy) — бинарник
- [Libziks/Opera-proxy](https://github.com/Libziks/Opera-proxy) — идеи и фичи
- [rndnaame/awg-compressed](https://github.com/rndnaame/awg-compressed) — дизайн меню

---

<div align="center">

**⬆ Обновление: пункт `[99]` в меню**

Made with ❤️ for Keenetic community

</div>
