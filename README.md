<div align="center">

# 🎭 Opera-Proxy для Keenetic / Entware

**Меню управления SOCKS5-прокси на базе Opera VPN**

`menu-opera.sh` — интерактивный shell-скрипт для установки, настройки и диагностики
[opera-proxy](https://github.com/Alexey71/opera-proxy) на роутерах Keenetic с Entware.

![Version](https://img.shields.io/badge/меню-1.2.5-green?style=for-the-badge)
![Platform](https://img.shields.io/badge/платформа-Keenetic%20%2F%20Entware-blue?style=for-the-badge)
![Shell](https://img.shields.io/badge/sh-posix%20(sh%2C%20ash%2C%20bash)-informational?style=for-the-badge&logo=gnubash&logoColor=white)
![License](https://img.shields.io/badge/статус-поддержка%20активна-brightgreen?style=for-the-badge)

</div>

---

## 📋 О проекте

Скрипт разворачивает и обслуживает локальный **SOCKS5-прокси**, построенный на бесплатных
серверах Opera VPN (регионы EU / AS / AM), и интегрирует его с туннельным интерфейсом
**t2sN (ProxyN)** прошивки Keenetic/NDM.

Основные возможности:

- 🚀 Установка бинарника из репозитория `sw.ext.io` или **UPX-сжатой версии** из GitHub Actions этого репозитория
- 🔧 Автономная настройка: конфиг `/opt/etc/opera-proxy.conf`, init-скрипт с логированием в системный журнал Keenetic
- 🔍 Диагностика туннеля: 4 теста через SOCKS5 и интерфейс t2sN (myip.wtf, 2p.io, Telegram, Google)
- ⚙️ Интерактивная настройка всех параметров конфига с авто-пересборкой `OPTIONS` и синхронизацией порта с t2sN
- 🔄 Самообновление скрипта с зеркалами на случай блокировки raw.githubusercontent.com

> Фичи и дизайн частично вдохновлены проектами
> [rndnaame/awg-compressed](https://github.com/rndnaame/awg-compressed) и
> [Libziks/Opera-proxy](https://github.com/Libziks/Opera-proxy).

---

## ⚡ Быстрый старт

Подключитесь к роутеру по SSH (root) и выполните:

```sh
curl -sL https://raw.githubusercontent.com/rndnaame/opera-proxy/main/menu-opera.sh | sh
```

Если GitHub недоступен, используйте зеркало из меню `[99]`, либо скачайте файл
на компьютер и загрузите на роутер:

```sh
scp menu-opera.sh root@192.168.1.1:/tmp/
sh /tmp/menu-opera.sh
```

Требования: Entware (`/opt`), утилиты `curl`, `ndmc` (входит в KeeneticOS),
свободный порт `18080` (по умолчанию).

---

## 🧭 Главное меню

| Пункт | Действие | Описание |
|:-----:|----------|----------|
| **[1]** | Установить Opera-proxy | Выбор источника: репозиторий `sw.ext.io` или UPX-сжатый бинарник из GitHub Actions; создаёт конфиг и init-скрипт `S99opera-proxy` |
| **[2]** | Обновить Opera-proxy (opkg) | Штатное обновление пакета через opkg |
| **[3]** | Обновление Bin из GitHub | Замена бинарника на актуальный UPX-сжатый из releases этого репозитория |
| **[4]** | Fix Opera (+socks5) | Починка конфигурации: socks5-upstream для интерфейса ProxyN/t2sN, порты, состояние сервиса |
| **[5]** | Остановить / Запустить сервис | Управление демоном; при остановке t2sN уходит в **DOWN**, при запуске поднимается в **UP** (через `ndmc`) |
| **[6]** | Проверить прокси | Диагностика туннеля (см. ниже) + сверка портов конфиг ↔ процесс ↔ t2sN |
| **[7]** | Настройка конфига | Просмотр и интерактивное изменение параметров (см. ниже) |
| **[88]** | Удалить | Остановка сервиса, удаление бинарника/конфига/init-скрипта, чистка интерфейсов Opera по description |
| **[99]** | Обновить скрипт | Самообновление `menu-opera.sh` с GitHub (при недоступности — зеркала ghfast.top / gh-proxy.com) |
| **[0]** | Выход | |

---

## 🔍 Пункт [6] — проверка прокси

Пункт выполняет до **4 тестов** и показывает сводку `N/4`:

1. `http://myip.wtf/text` — полный отчёт IP/страна **через SOCKS5** `127.0.0.1:<BIND_PORT>`
2. `https://2ip.io` — проверка геолокации **через SOCKS5**
3. `https://web.telegram.org` — доступность Telegram (**DNS тоже через прокси**, `--socks5-hostname`)
4. `https://connectivitycheck.gstatic.com/generate_204` — доступность Google **через интерфейс t2sN** (`--interface`)

Дополнительно:

- **Сверка портов**: порт в конфиге (`BIND_PORT`), фактический порт запущенного процесса
  и upstream-порт интерфейса t2sN. При расхождении — предложение исправить порт t2s,
  перезапустить сервис и повторить тест.
- Если хотя бы одна проверка прошла, а t2sN в состоянии **DOWN** — предложение поднять
  интерфейс (`ndmc ... up`) и повторить проверку заново.
- Конфиг в выводе не печатается — показывается только команда запуска процесса
  (`/proc/<pid>/cmdline`).

---

## ⚙️ Пункт [7] — настройка конфига

Текущие параметры выводятся таблицей; изменения — нумерованным подменю.
После любой правки `OPTIONS` пересобирается автоматически.

```text
[1] Регион (COUNTRY)          → [1] EU (Европа)  [2] AS (Азия)  [3] AM (Америка)
[2] BIND_ADDR                 → IPv4-адрес прослушивания (0.0.0.0 = вся сеть)
[3] BIND_PORT                 → с проверкой и синхронизацией upstream t2sN-интерфейса Opera
[4] OBFUSCATE + FAKE_SNI      → обход ТСПУ/DPI (yes/no + домен фейкового SNI)
[5] BOOTSTRAP_DNS             → DoH-серверы для первичного поиска серверов Opera
[6] SERVER_SELECT             → random | fastest
[7] VERBOSITY (уровень логов) → см. таблицу ниже
```

При изменении **BIND_PORT** ([3]) скрипт проверяет upstream найденного t2sN-интерфейса
Opera и при расхождении предлагает обновить его (`ndmc interface ProxyN proxy upstream
127.0.0.1 <порт>` + сохранение конфигурации + перезапуск сервиса). Дефолтный порт везде — **18080**.

### 📊 Уровни логирования (`-verbosity`)

По справке opera-proxy:

| Значение | Уровень | Описание |
|:--------:|---------|----------|
| `10` | debug | Подробная отладка |
| `20` | info | Информационный (default в opera-proxy) |
| `30` | warn | Предупреждения и выше (рекомендуется) |
| `40` | error | Только ошибки |
| `50` | critical | Только критические |
| `60` | silent | Полное отсутствие вывода |

---

## 📄 Конфигурация

Файл `/opt/etc/opera-proxy.conf`:

```sh
# Регион: EU (Европа), AS (Азия), AM (Америка)
COUNTRY="EU"

# Адрес и порт (0.0.0.0 — доступен роутеру и всей домашней сети)
BIND_ADDR="0.0.0.0"
BIND_PORT="18080"

# Обход блокировок ТСПУ/DPI в РФ
OBFUSCATE="yes"
FAKE_SNI="2gis.com"

# Защищённый DoH DNS для первичного поиска серверов
BOOTSTRAP_DNS="https://dns.google/dns-query,https://1.1.1.1/dns-query"

# Выбор сервера: random (случайный) или fastest (быстрый)
SERVER_SELECT="random"

# Уровень логов: 10=debug, 20=info, 30=warn, 40=error, 50=critical, 60=silent
VERBOSITY="30"

# ── Автогенерация OPTIONS для Entware init.d / rc.func ────────
OPTIONS="-socks-mode -country $COUNTRY -bind-address ${BIND_ADDR}:${BIND_PORT} \
-server-selection $SERVER_SELECT -verbosity $VERBOSITY -bootstrap-dns $BOOTSTRAP_DNS"
if [ "$OBFUSCATE" = "yes" ] && [ -n "$FAKE_SNI" ]; then
    OPTIONS="$OPTIONS -fake-SNI $FAKE_SNI"
fi
```

После ручных изменений: `/opt/etc/init.d/S99opera-proxy restart`.

---

## 📝 Логирование в журнал Keenetic

Стандартный `rc.func` из Entware **не пишет stderr демона в syslog**, поэтому в журнале
Keenetic («Мониторинг → Журнал») было тихо. Скрипт заменяет `S99opera-proxy` на
wrapper-скрипт, который запускает демон конвейером:

```sh
( opera-proxy $OPTIONS 2>&1 | logger -t opera-proxy ) &
```

Логи появляются в журнале с меткой `opera-proxy`. Включение/отключение — из пункта **[7]**
(`LOG_TO_SYSLOG="yes"` в конфиге).

> ℹ️ Сообщения вида `unrecognized command` / `EOF` в логах — это health-check запросы NDM
> Keenetic к SOCKS-порту, а не ошибки работы туннеля.

---

## 🤖 GitHub Actions

Workflow [`compress-opera.yml`](.github/workflows/compress-opera.yml) автоматически:

1. Находит свежий `.ipk` с `opera-proxy` в репозитории `Alexey71/opera-proxy` (зеркало sw.ext.io)
2. Извлекает бинарник и сжимает его **UPX**
3. Публикует релиз с `opera-proxy_<версия>_<arch>` — пункт **[3]** меню обновляется именно оттуда

---

## 🛠 Отладка

```sh
# статус сервиса и процесс
/opt/etc/init.d/S99opera-proxy status
ps w | grep opera-proxy

# какой порт реально слушает демон
cat /proc/$(pidof opera-proxy)/cmdline | tr '\0' ' '; echo

# состояние t2s-интерфейсов
ip link show | grep -A1 t2s

# логи в журнале системы
logger -s -t test "проверка syslog"   # должна появиться запись
```

Типовые проблемы:

| Симптом | Решение |
|---------|---------|
| Тесты через SOCKS проходят, но трафик идёт без прокси | Пункт **[4]** (Fix) или **[6]** — синхронизируйте upstream-порт t2sN |
| Пустой журнал Keenetic | Включите syslog-логирование в **[7]**, затем `restart` |
| Много `[E]: unrecognized command` в логах при verbosity 10 | Норма: health-check NDM; поднимите уровень до 30 |
| GitHub недоступен для п. [99]/[3] | Используйте зеркала ghfast.top / gh-proxy.com (встроены в скрипт) |

---

## ⚠️ Дисклеймер

Проект использует публичные SOCKS5-серверы Opera VPN. Это **не официальный** сервис Opera:
без гарантий доступности, скорости и конфиденциальности. Не передавайте через туннель
чувствительные данные (пароли, банковские сессии) без дополнительного шифрования.
Используйте на свой страх и риск и соблюдайте законодательство вашей страны.

---

## 🙏 Благодарности

- [Alexey71/opera-proxy](https://github.com/Alexey71/opera-proxy) — основной бинарник
- [Libziks/Opera-proxy](https://github.com/Libziks/Opera-proxy) — источник ряда идей и фич
- [rndnaame/awg-compressed](https://github.com/rndnaame/awg-compressed) — дизайн меню и архитектура скрипта

---

<div align="center">

**⬆ Обновление одним движением: пункт `[99]` в меню**

Made with ❤️ for Keenetic community

</div>
