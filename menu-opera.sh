#!/bin/sh
# Меню управления Opera-Proxy (Keenetic / Entware)
# Дизайн и архитектура по образцу:
#   https://github.com/rndnaame/awg-compressed
#   https://github.com/rndnaame/awg-compressed/blob/main/install-compressed.sh
#
# Запуск:
#   sh menu-opera.sh
#   curl -sL <url>/menu-opera.sh | sh

# ---------------------------------------------------------------------------
# UI (цвета как у awg-compressed; NO_COLOR=1 — без ANSI)
# ---------------------------------------------------------------------------
green="\033[92m"
red="\033[91m"
yellow="\033[93m"
light_blue="\033[96m"
bold="\033[1m"
reset="\033[0m"

HL_UPD='\033[1;93m'
HL_RST='\033[0m'

if [ -n "$NO_COLOR" ]; then
  green=""; red=""; yellow=""; light_blue=""; bold=""; reset=""
  HL_UPD=""; HL_RST=""
fi

ask() {
  prompt="$1"
  default="$2"
  if [ -r /dev/tty ]; then
    printf "%s" "$prompt" > /dev/tty
    read -r answer < /dev/tty || answer="$default"
  else
    answer="$default"
  fi
  [ -z "$answer" ] && answer="$default"
  echo "$answer"
}

yes_no() {
  # $1 prompt, $2 default y|n → 1|0
  a=$(ask "$1" "$2")
  case "$a" in
    y|Y|yes|YES|д|Д) echo 1 ;;
    *) echo 0 ;;
  esac
}

print_banner() {
  clear 2>/dev/null || true
  printf '%b\n' "${light_blue}================================================${reset}"
  printf '%b\n' "${light_blue}Opera-Proxy — меню управления (Keenetic/Entware)${reset}"
  printf '%b\n' "${light_blue}================================================${reset}"
  echo ""
}

# ---------------------------------------------------------------------------
# Определение состояния
# ---------------------------------------------------------------------------
detect_arch() {
  A=$(opkg print-architecture 2>/dev/null | sort -k3 -nr | awk '$2!="all"{print $2;exit}')
  case "$A" in
    aarch64*|arm*) ARCH=aarch64; ARCH_REPO="aarch64" ;;
    mipsel*)       ARCH=mipsel;  ARCH_REPO="mipsel"  ;;
    mips*)         ARCH=mips;    ARCH_REPO="mips"    ;;
    *)
      ARCH=""
      ARCH_REPO=""
      ;;
  esac
}

detect_installed() {
  OP_BIN="/opt/sbin/opera-proxy"
  OP_INIT="/opt/etc/init.d/S99opera-proxy"
  OP_CONF="/opt/etc/opera-proxy.conf"
  FIX_SCRIPT="/opt/fix_opera_tunnel.sh"

  CUR_VER=""
  if [ -x "$OP_BIN" ]; then
    CUR_VER=$("$OP_BIN" -version 2>/dev/null | head -n1 || echo "unknown")
  fi

  SVC_RUNNING=0
  if [ -x "$OP_INIT" ]; then
    if pgrep -f "[o]pera-proxy" >/dev/null 2>&1 || \
       "$OP_INIT" status 2>/dev/null | grep -qiE 'running|started|active'; then
      SVC_RUNNING=1
    fi
  fi

  T2S0_UP=0
  if ip link show t2s0 2>/dev/null | grep -q "state UP"; then
    T2S0_UP=1
  elif ifconfig t2s0 2>/dev/null | grep -q "UP"; then
    T2S0_UP=1
  fi

  FIX_EXISTS=0
  [ -f "$FIX_SCRIPT" ] && FIX_EXISTS=1
}

show_status() {
  detect_arch
  detect_installed

  echo "Сейчас на роутере:"
  if [ -n "$ARCH" ]; then
    printf "   Архитектура : %s (%s)\n" "$A" "$ARCH"
  else
    echo "   Архитектура : не определена"
  fi

  if [ -n "$CUR_VER" ]; then
    printf "   opera-proxy : %b%s%b\n" "$green" "$CUR_VER" "$reset"
  else
    printf "   opera-proxy : %bне установлен%b\n" "$red" "$reset"
  fi

  if [ -x "$OP_INIT" ]; then
    if [ "$SVC_RUNNING" = "1" ]; then
      printf "   Сервис      : %bзапущен%b\n" "$green" "$reset"
    else
      printf "   Сервис      : %bостановлен%b\n" "$yellow" "$reset"
    fi
  else
    printf "   Сервис      : %bнет init-скрипта%b\n" "$red" "$reset"
  fi

  if [ "$T2S0_UP" = "1" ]; then
    printf "   t2s0 (Proxy0): %bUP%b\n" "$green" "$reset"
  else
    printf "   t2s0 (Proxy0): %bDOWN / нет%b\n" "$yellow" "$reset"
  fi

  if [ "$FIX_EXISTS" = "1" ]; then
    printf "   Fix-скрипт  : %bесть%b (%s)\n" "$green" "$reset" "$FIX_SCRIPT"
  else
    printf "   Fix-скрипт  : %bнет%b\n" "$yellow" "$reset"
  fi
  echo ""
}

# ---------------------------------------------------------------------------
# Общие: Proxy0 + проверка туннеля
# ---------------------------------------------------------------------------
configure_proxy0() {
  echo ""
  echo "→ Настройка интерфейса Proxy0 (t2s0) через ndmc ..."
  if command -v ndmc >/dev/null 2>&1; then
    ndmc -c "interface Proxy0" 2>/dev/null || true
    ndmc -c "interface Proxy0 proxy protocol socks5" 2>/dev/null || true
    ndmc -c "interface Proxy0 proxy socks5" 2>/dev/null || true
    ndmc -c "interface Proxy0 proxy upstream 127.0.0.1 18080" 2>/dev/null || true
    ndmc -c "interface Proxy0 ip global auto" 2>/dev/null || true
    ndmc -c "interface Proxy0 description OperaProxy" 2>/dev/null || true
    ndmc -c "interface Proxy0 up" 2>/dev/null || true
    ndmc -c "system configuration save" 2>/dev/null || true
    echo "   ✓ Команды ndmc выполнены"
  else
    echo "   ⚠ ndmc не найден — настройте Proxy0 вручную"
  fi
}

check_tunnel_quick() {
  echo ""
  echo "→ Проверка туннеля (t2s0) ..."
  sleep 3
  _ok=0
  if curl --interface t2s0 -s -m 8 myip.wtf 2>/dev/null; then
    echo ""
    _ok=1
  fi
  if curl --interface t2s0 -s -m 8 2ip.io 2>/dev/null; then
    echo ""
    _ok=1
  fi
  if [ "$_ok" = "0" ]; then
    echo "⚠ Туннель пока не отвечает (подождите или запустите Fix)"
  else
    echo "✅ Туннель отвечает"
  fi
}

# ---------------------------------------------------------------------------
# [1] Установить Opera-proxy (официальный, sw.ext.io)
# ---------------------------------------------------------------------------
install_opera_proxy() {
  print_banner
  printf '%b\n' "${bold}[1] Установка Opera-proxy (официальный)${reset}"
  echo ""

  detect_arch
  if [ -z "$ARCH" ]; then
    echo "❌ Неизвестная архитектура. Нужны: aarch64 / mipsel / mips"
    opkg print-architecture 2>/dev/null || true
    return 1
  fi

  echo "Архитектура: $A → $ARCH"
  echo ""

  # Репозиторий
  echo "→ Добавление репозитория sw.ext.io ..."
  mkdir -p /opt/etc/opkg
  echo "src/gz sw http://sw.ext.io/ent/$ARCH" > /opt/etc/opkg/sw.ext.io.conf
  echo "   ✓ /opt/etc/opkg/sw.ext.io.conf"

  echo ""
  echo "→ opkg update ..."
  opkg update || {
    echo "⚠ opkg update завершился с ошибкой (продолжаем)"
  }

  echo ""
  echo "→ Установка пакета opera-proxy ..."
  if opkg install opera-proxy; then
    echo "✅ Пакет установлен"
  else
    echo "❌ Не удалось установить opera-proxy"
    return 1
  fi

  echo ""
  echo "→ Запуск сервиса ..."
  /opt/etc/init.d/S99opera-proxy start 2>/dev/null || true
  sleep 2

  configure_proxy0
  check_tunnel_quick

  echo ""
  echo "=== Установка завершена ==="
}

# ---------------------------------------------------------------------------
# [2] Установить Opera-proxy UPX (сжатый, GitHub)
# ---------------------------------------------------------------------------
install_opera_compressed() {
  print_banner
  printf '%b\n' "${bold}[2] Установка Opera-proxy UPX (сжатый)${reset}"
  echo ""

  detect_arch
  if [ -z "$ARCH" ]; then
    echo "❌ Неизвестная архитектура. Нужны: aarch64 / mipsel / mips"
    opkg print-architecture 2>/dev/null || true
    return 1
  fi

  case "$ARCH" in
    aarch64) IPK_SUFFIX="aarch64-3.10" ;;
    mipsel)  IPK_SUFFIX="mipsel-3.4" ;;
    mips)    IPK_SUFFIX="mips-3.4" ;;
    *)
      echo "❌ Нет сжатого IPK для архитектуры: $ARCH"
      return 1
      ;;
  esac

  echo "Архитектура: $A → $ARCH ($IPK_SUFFIX)"
  echo "Источник: https://github.com/rndnaame/opera-proxy/releases"
  echo ""

  # Найти последний релиз (make_latest) и IPK под архитектуру
  echo "→ Поиск сжатого IPK ..."
  _html=$(curl -sL --connect-timeout 15 --max-time 30 \
    "https://github.com/rndnaame/opera-proxy/releases/latest" 2>/dev/null || true)
  if [ -z "$_html" ]; then
    _html=$(curl -sL --connect-timeout 15 --max-time 30 \
      "https://ghfast.top/https://github.com/rndnaame/opera-proxy/releases/latest" 2>/dev/null || true)
  fi

  # tag из URL вида /releases/tag/op-1.29.0-1
  REL_TAG=$(echo "$_html" | grep -oE 'releases/tag/op-[0-9][^\"'\''<> /]+' | head -1 | sed 's|releases/tag/||')
  IPK_NAME=$(echo "$_html" | grep -oE "opera-proxy_[0-9][^\"'<> ]+_${IPK_SUFFIX}_compressed\\.ipk" | head -1)

  # fallback: страница конкретного тега / expanded_assets
  if [ -z "$IPK_NAME" ] && [ -n "$REL_TAG" ]; then
    _html2=$(curl -sL --connect-timeout 15 --max-time 30 \
      "https://github.com/rndnaame/opera-proxy/releases/expanded_assets/${REL_TAG}" 2>/dev/null || true)
    IPK_NAME=$(echo "$_html2" | grep -oE "opera-proxy_[0-9][^\"'<> ]+_${IPK_SUFFIX}_compressed\\.ipk" | head -1)
  fi

  if [ -z "$IPK_NAME" ] || [ -z "$REL_TAG" ]; then
    echo "❌ Сжатый IPK для $IPK_SUFFIX не найден"
    echo "   Проверьте: https://github.com/rndnaame/opera-proxy/releases"
    return 1
  fi

  echo "   Релиз: $REL_TAG"
  echo "   Найден: $IPK_NAME"
  URL="https://github.com/rndnaame/opera-proxy/releases/download/${REL_TAG}/${IPK_NAME}"
  TMP_IPK="/tmp/${IPK_NAME}"

  echo ""
  echo "→ Скачивание ..."
  rm -f "$TMP_IPK"
  _dl_ok=0
  for _try_url in \
    "$URL" \
    "https://ghfast.top/${URL}" \
    "https://gh-proxy.com/${URL}"
  do
    echo "   ↻ $_try_url"
    if command -v curl >/dev/null 2>&1; then
      curl -fL --connect-timeout 15 --max-time 120 -o "$TMP_IPK" "$_try_url" 2>/dev/null && _dl_ok=1
    fi
    if [ "$_dl_ok" != "1" ] && command -v wget >/dev/null 2>&1; then
      wget -q -T 30 -O "$TMP_IPK" "$_try_url" 2>/dev/null && _dl_ok=1
    fi
    [ -s "$TMP_IPK" ] && _dl_ok=1
    [ "$_dl_ok" = "1" ] && break
    rm -f "$TMP_IPK"
  done

  if [ ! -s "$TMP_IPK" ]; then
    echo "❌ Не удалось скачать $IPK_NAME"
    return 1
  fi
  echo "   ✓ $(du -h "$TMP_IPK" | awk '{print $1}')"

  echo ""
  echo "→ Установка $IPK_NAME ..."
  if opkg install --force-reinstall "$TMP_IPK" 2>/dev/null || opkg install "$TMP_IPK"; then
    echo "✅ Пакет установлен (UPX)"
  else
    echo "❌ opkg install не удался"
    rm -f "$TMP_IPK"
    return 1
  fi
  rm -f "$TMP_IPK"

  echo ""
  echo "→ Запуск сервиса ..."
  /opt/etc/init.d/S99opera-proxy start 2>/dev/null || true
  sleep 2

  configure_proxy0
  check_tunnel_quick

  echo ""
  echo "=== Установка сжатой версии завершена ==="
}

# ---------------------------------------------------------------------------
# [3] Обновить Opera-proxy (opkg)
# ---------------------------------------------------------------------------
upgrade_opera_proxy() {
  print_banner
  printf '%b\n' "${bold}[3] Обновление Opera-proxy (opkg)${reset}"
  echo ""

  if ! opkg list-installed 2>/dev/null | grep -q '^opera-proxy '; then
    echo "❌ Пакет opera-proxy не установлен."
    echo "   Сначала выполните установку (пункт 1)."
    return 1
  fi

  _cur=$(opkg list-installed 2>/dev/null | awk '/^opera-proxy /{print $3; exit}')
  echo "Текущая версия: ${_cur:-unknown}"
  echo ""

  echo "→ opkg update ..."
  if ! opkg update; then
    echo "⚠ opkg update завершился с ошибкой (продолжаем)"
  fi

  echo ""
  echo "→ opkg upgrade opera-proxy ..."
  if opkg upgrade opera-proxy; then
    _new=$(opkg list-installed 2>/dev/null | awk '/^opera-proxy /{print $3; exit}')
    if [ -n "$_cur" ] && [ -n "$_new" ] && [ "$_cur" = "$_new" ]; then
      echo "✅ Уже актуальная версия: $_new"
    else
      echo "✅ Обновлено: ${_cur:-?} → ${_new:-ok}"
    fi
  else
    echo "⚠ opkg upgrade не применил изменений (возможно, уже последняя версия)"
  fi

  echo ""
  echo "→ Перезапуск сервиса ..."
  /opt/etc/init.d/S99opera-proxy restart 2>/dev/null && echo "   ✓ Сервис перезапущен" || echo "   ⚠ Не удалось перезапустить"
  echo ""
  echo "=== Готово ==="
}

# ---------------------------------------------------------------------------
# [4] Обновление Bin Opera-Proxy из GitHub
# ---------------------------------------------------------------------------
update_opera_bin() {
  print_banner
  printf '%b\n' "${bold}[4] Обновление opera-proxy из GitHub${reset}"
  echo ""

  INSTALL_PATH="/opt/sbin/opera-proxy"
  if [ ! -f "$INSTALL_PATH" ]; then
    echo "❌ opera-proxy не найден. Обновление отменено."
    return 1
  fi

  CURRENT=$("$INSTALL_PATH" -version 2>/dev/null | head -n1 || echo "unknown")
  echo "Найден: $INSTALL_PATH (текущая: $CURRENT)"

  LATEST=$(curl -s -I -L https://github.com/Alexey71/opera-proxy/releases/latest 2>/dev/null \
    | grep -oE "tag/v?[0-9.]+" | head -n1 | sed "s/tag\///")
  [ -z "$LATEST" ] && LATEST=$(wget -q -O - --spider https://github.com/Alexey71/opera-proxy/releases/latest 2>&1 \
    | grep -oE "tag/v?[0-9.]+" | head -n1 | sed "s/tag\///")
  echo "Последняя: ${LATEST:-unknown}"

  CURRENT_NORM=${CURRENT#v}
  LATEST_NORM=${LATEST#v}

  if [ -n "$LATEST_NORM" ] && [ "$CURRENT_NORM" = "$LATEST_NORM" ]; then
    echo "✅ Версия уже актуальная ($CURRENT)"
    if [ "$(yes_no "Принудительно обновить? [y/N]: " "n")" != "1" ]; then
      echo "Обновление отменено."
      return 0
    fi
    echo "🔄 Принудительное обновление..."
  fi

  echo "🔄 Начинаем обновление..."

  A=$(opkg print-architecture 2>/dev/null | sort -k3 -nr | awk '$2!="all"{print $2;exit}')
  case $A in
    aarch64*) ARCH_DL=linux-arm64 ;;
    mipsel*)  ARCH_DL=linux-mipsle ;;
    mips*)    ARCH_DL=linux-mips ;;
    *)
      echo "❌ Неизвестная архитектура: ${A:-пусто}"
      return 1
      ;;
  esac

  TMP="/tmp/opera-proxy.new"
  URL="https://github.com/Alexey71/opera-proxy/releases/latest/download/opera-proxy.${ARCH_DL}"

  echo "⬇️ Скачивание $URL ..."
  rm -f "$TMP"
  if command -v curl >/dev/null 2>&1; then
    curl -L -f --connect-timeout 20 -o "$TMP" "$URL" || true
  fi
  if [ ! -s "$TMP" ] && command -v wget >/dev/null 2>&1; then
    wget --timeout=20 -q -O "$TMP" "$URL" || true
  fi
  if [ ! -s "$TMP" ]; then
    echo "❌ Ошибка скачивания"
    return 1
  fi

  chmod +x "$TMP"

  if [ "$(yes_no "Сжать UPX? [y/N]: " "n")" = "1" ]; then
    if ! command -v upx >/dev/null 2>&1; then
      echo "→ Установка upx ..."
      opkg update >/dev/null 2>&1 || true
      opkg install upx >/dev/null 2>&1 || true
    fi
    if command -v upx >/dev/null 2>&1; then
      echo "🔧 Сжатие..."
      upx --lzma --best "$TMP" 2>/dev/null || true
    else
      echo "⚠ upx недоступен, пропускаем сжатие"
    fi
  fi

  mv -f "$TMP" "$INSTALL_PATH"
  echo "✅ Обновлено → $($INSTALL_PATH -version 2>/dev/null | head -n1)"

  echo "🔄 Перезапуск..."
  /opt/etc/init.d/S99opera-proxy restart 2>/dev/null && echo "Сервис перезапущен" || true

  sleep 5
  echo "🌐 Проверка t2s0:"
  curl --interface t2s0 -s -m 8 2ip.io 2>/dev/null || echo "2ip.io: нет"
  echo ""
  curl --interface t2s0 -s -m 8 ifconfig.co 2>/dev/null || echo "ifconfig.co: нет"
  echo ""
  echo "=== Готово ==="
}

# ---------------------------------------------------------------------------
# [5] Fix Opera (+socks5)
# ---------------------------------------------------------------------------
fix_opera() {
  print_banner
  printf '%b\n' "${bold}[5] Fix Opera (+socks5)${reset}"
  echo ""

  if [ -f /opt/fix_opera_tunnel.sh ]; then
    echo "→ Найден /opt/fix_opera_tunnel.sh — запускаем..."
    echo ""
    sh /opt/fix_opera_tunnel.sh
    return $?
  fi

  echo "→ Файл fix-скрипта отсутствует. Создаём..."
  echo ""

  if [ ! -f /opt/etc/init.d/S99opera-proxy ]; then
    echo "✗ opera-proxy не установлен!"
    return 1
  fi

  cat > /opt/fix_opera_tunnel.sh << 'FIXSCRIPT'
#!/bin/sh
TAG="opera-proxy"; LOG="/var/log/opera-tunnel.log"
mkdir -p "$(dirname "$LOG")"
log(){ ts="$(date "+%Y-%m-%d %H:%M:%S")"; echo "[$ts] $2" | tee -a "$LOG"; logger -p user."$1" -t "$TAG" "$2" 2>/dev/null || true; }
show_config(){ [ -f /opt/etc/opera-proxy.conf ] && log notice "   Параметры: $(cat /opt/etc/opera-proxy.conf)"; }

IP=$(curl --interface t2s0 -m 8 --connect-timeout 5 -s http://api.ipify.org 2>/dev/null)
if echo "$IP" | grep -qE "^[0-9]{1,3}(\.[0-9]{1,3}){3}$"; then log warn "✓ Туннель работает! IP: $IP"; show_config; exit 0; fi

log err "✗ Туннель не работает"

if ! ip link show t2s0 2>/dev/null | grep -q "state UP"; then
  log warn "Интерфейс t2s0 DOWN!"; echo -n "Включить Proxy0? (y/n): "; read -r a
  case $a in [Yy]*) ndmc -c interface Proxy0 up && ndmc -c system configuration save; sleep 5;; *) log warn "Отменено"; exit 1;; esac
fi

/opt/etc/init.d/S99opera-proxy stop 2>/dev/null; killall -9 opera-proxy opera-proxy-monitor 2>/dev/null; sleep 4

TEMP=/tmp/s5.txt; rm -f "$TEMP"
curl -s -L -m 20 -o "$TEMP" https://databay.com/free-proxy-list/socks5.txt || curl -s -L -m 20 -o "$TEMP" https://raw.githubusercontent.com/TheSpeedX/PROXY-List/master/socks5.txt

PROXY_COUNT=$(grep -cE "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+" "$TEMP" 2>/dev/null || echo 0)
log warn "Проверка скачанного списка прокси ($PROXY_COUNT шт.)"

COUNT=0; P1=""; P2=""; P3=""
while IFS= read -r p && [ $COUNT -lt 3 ]; do
  p=$(echo "$p" | tr -d "\r" | sed -E "s|^socks5?h?://||;s|[[:space:]]||g")
  echo "$p" | grep -qE "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+$" || continue
  if curl -x "socks5h://$p" -m 10 --connect-timeout 7 -s -o /dev/null -w "%{http_code}" http://api.ipify.org 2>/dev/null | grep -q "^200$"; then
    COUNT=$((COUNT+1)); eval "P$COUNT=\$p"
  fi
done < "$TEMP"

[ -z "$P1" ] && [ -s "$TEMP" ] && P1=$(head -n1 "$TEMP" | tr -d "\r" | sed -E "s|^socks5?h?://||;s|[[:space:]]||g")
P2=${P2:-$P1}; P3=${P3:-$P1}

start(){ echo "OPTIONS=\"-socks-mode -country EU $1\"" > /opt/etc/opera-proxy.conf; /opt/etc/init.d/S99opera-proxy stop 2>/dev/null; killall -9 opera-proxy 2>/dev/null; sleep 3; /opt/etc/init.d/S99opera-proxy start; }

SUCCESS=0
for p in "$P1" "$P2" "$P3"; do
  [ -z "$p" ] && continue
  log warn "Пробуем $p"; start "-api-proxy socks5://$p"; sleep 10
  for i in $(seq 1 8); do
    IP=$(curl --interface t2s0 -m 10 --connect-timeout 6 -s http://api.ipify.org 2>/dev/null)
    if echo "$IP" | grep -qE "^[0-9]{1,3}(\.[0-9]{1,3}){3}$"; then
      log warn "✓ УСПЕШНО! Прокси: $p"; log warn "   IP: $IP"; show_config
      ndmc -c interface Proxy0 ping-check profile default && ndmc -c system configuration save
      SUCCESS=1; exit 0
    fi
    sleep 2
  done
done

[ $SUCCESS -eq 0 ] && log err "Не удалось восстановить туннель"
FIXSCRIPT

  chmod +x /opt/fix_opera_tunnel.sh

  if [ ! -f /opt/etc/init.d/S10cron ] && [ ! -f /opt/bin/cron ]; then
    echo "Устанавливаем cron..."
    opkg update >/dev/null 2>&1 || true
    opkg install cron >/dev/null 2>&1 && echo "cron успешно установлен" || echo "⚠ не удалось установить cron"
  else
    echo "cron уже установлен"
  fi

  mkdir -p /opt/etc/cron.hourly
  cat > /opt/etc/cron.hourly/fix_opera_tunnel << 'CRON'
#!/bin/sh
/opt/fix_opera_tunnel.sh
CRON
  chmod +x /opt/etc/cron.hourly/fix_opera_tunnel

  echo "✅ Скрипт создан: /opt/fix_opera_tunnel.sh"
  echo "Cron настроен (каждый час)"
  echo ""
  echo "Запускаем скрипт..."
  echo ""
  /opt/fix_opera_tunnel.sh
}

# ---------------------------------------------------------------------------
# [6] Остановить / Запустить сервис
# ---------------------------------------------------------------------------
toggle_service() {
  print_banner
  printf '%b\n' "${bold}[6] Управление сервисом opera-proxy${reset}"
  echo ""

  if [ ! -x /opt/etc/init.d/S99opera-proxy ]; then
    echo "❌ Init-скрипт /opt/etc/init.d/S99opera-proxy не найден"
    echo "   Сначала установите opera-proxy (пункт 1)"
    return 1
  fi

  detect_installed
  if [ "$SVC_RUNNING" = "1" ]; then
    echo "Сервис сейчас: запущен"
    echo ""
    if [ "$(yes_no "Остановить сервис? [Y/n]: " "y")" = "1" ]; then
      /opt/etc/init.d/S99opera-proxy stop
      killall -9 opera-proxy opera-proxy-monitor 2>/dev/null || true
      echo "✅ Сервис остановлен"
    else
      echo "Отменено."
    fi
  else
    echo "Сервис сейчас: остановлен"
    echo ""
    if [ "$(yes_no "Запустить сервис? [Y/n]: " "y")" = "1" ]; then
      /opt/etc/init.d/S99opera-proxy start
      sleep 2
      if pgrep -f "[o]pera-proxy" >/dev/null 2>&1; then
        echo "✅ Сервис запущен"
      else
        echo "⚠ Команда start выполнена, но процесс не обнаружен"
      fi
    else
      echo "Отменено."
    fi
  fi
}

# ---------------------------------------------------------------------------
# [7] Проверить прокси
# ---------------------------------------------------------------------------
check_proxy() {
  print_banner
  printf '%b\n' "${bold}[7] Проверка прокси (через t2s0)${reset}"
  echo ""

  detect_installed

  # Статус интерфейса
  if [ "$T2S0_UP" = "1" ]; then
    printf "   Интерфейс t2s0 : %bUP%b\n" "$green" "$reset"
  else
    printf "   Интерфейс t2s0 : %bDOWN / отсутствует%b\n" "$red" "$reset"
    echo ""
    echo "⚠ Без активного t2s0 проверка через Proxy0 невозможна."
    echo "   Включите Proxy0 или выполните Fix (пункт 5)."
    return 1
  fi

  if [ "$SVC_RUNNING" = "1" ]; then
    printf "   Сервис         : %bзапущен%b\n" "$green" "$reset"
  else
    printf "   Сервис         : %bостановлен%b\n" "$yellow" "$reset"
  fi
  echo ""

  printf '%b\n' "${light_blue}────────────────────────────────────────────────${reset}"
  printf '%b\n' "${bold}  IP-сервисы${reset}"
  printf '%b\n' "${light_blue}────────────────────────────────────────────────${reset}"
  echo ""

  _ok_count=0

  # --- myip.wtf ---
  printf "  ▶ myip.wtf  ... "
  _out=$(curl --interface t2s0 -s -m 10 --connect-timeout 6 myip.wtf 2>/dev/null)
  if [ -n "$_out" ]; then
    printf '%bOK%b\n' "$green" "$reset"
    echo "$_out" | sed 's/^/    /'
    _ok_count=$((_ok_count + 1))
  else
    printf '%bнет ответа%b\n' "$red" "$reset"
  fi
  echo ""

  # --- 2ip.io ---
  printf "  ▶ 2ip.io    ... "
  _out=$(curl --interface t2s0 -s -m 10 --connect-timeout 6 2ip.io 2>/dev/null)
  if [ -n "$_out" ]; then
    printf '%bOK%b\n' "$green" "$reset"
    _ip=$(echo "$_out" | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}' | head -1)
    if [ -n "$_ip" ]; then
      echo "    IP: $_ip"
    else
      echo "$_out" | head -5 | sed 's/^/    /'
    fi
    _ok_count=$((_ok_count + 1))
  else
    printf '%bнет ответа%b\n' "$red" "$reset"
  fi
  echo ""

  printf '%b\n' "${light_blue}────────────────────────────────────────────────${reset}"
  printf '%b\n' "${bold}  Telegram${reset}"
  printf '%b\n' "${light_blue}────────────────────────────────────────────────${reset}"
  echo ""

  # --- web.telegram.org ---
  printf "  ▶ web.telegram.org  ... "
  _code=$(curl --interface t2s0 -s -o /dev/null -w "%{http_code}" -m 12 --connect-timeout 7 \
    -L https://web.telegram.org 2>/dev/null)
  case "$_code" in
    200|301|302|303|307|308)
      printf '%bOK%b  (HTTP %s)\n' "$green" "$reset" "$_code"
      _ok_count=$((_ok_count + 1))
      ;;
    000|"")
      printf '%bнет ответа%b\n' "$red" "$reset"
      ;;
    *)
      printf '%bHTTP %s%b\n' "$yellow" "$_code" "$reset"
      ;;
  esac
  echo ""

  # Итоговая сводка
  printf '%b\n' "${light_blue}────────────────────────────────────────────────${reset}"
  if [ "$_ok_count" -ge 2 ]; then
    printf "  Итог: %bтуннель работает%b  (%s/3 проверок)\n" "$green" "$reset" "$_ok_count"
  elif [ "$_ok_count" -eq 1 ]; then
    printf "  Итог: %bчастично%b  (%s/3) — возможны проблемы\n" "$yellow" "$reset" "$_ok_count"
  else
    printf "  Итог: %bтуннель не отвечает%b  (0/3)\n" "$red" "$reset"
    echo "        Попробуйте Fix (пункт 5) или перезапуск сервиса (пункт 6)."
  fi
  echo ""
}

# ---------------------------------------------------------------------------
# [88] Удалить Opera-proxy
# ---------------------------------------------------------------------------
remove_opera_proxy() {
  print_banner
  printf '%b\n' "${bold}[88] Удаление Opera-proxy${reset}"
  echo ""

  if ! opkg list-installed 2>/dev/null | grep -q '^opera-proxy '; then
    echo "⚠ Пакет opera-proxy не установлен."
  else
    _cur=$(opkg list-installed 2>/dev/null | awk '/^opera-proxy /{print $3; exit}')
    echo "Будет удалён пакет: opera-proxy (${_cur:-?})"
    echo ""
    if [ "$(yes_no "Удалить opera-proxy? [y/N]: " "n")" != "1" ]; then
      echo "Отменено."
      return 0
    fi

    echo ""
    echo "→ Удаление интерфейса Proxy0 ..."
    if command -v ndmc >/dev/null 2>&1; then
      ndmc -c "no interface Proxy0" 2>/dev/null && echo "   ✓ no interface Proxy0" || echo "   ⚠ Proxy0 не найден или уже удалён"
      ndmc -c "system configuration save" 2>/dev/null && echo "   ✓ Конфигурация сохранена" || echo "   ⚠ Не удалось сохранить конфигурацию"
    else
      echo "   ⚠ ndmc не найден — удалите Proxy0 вручную"
    fi

    echo ""
    echo "→ Остановка сервиса ..."
    /opt/etc/init.d/S99opera-proxy stop 2>/dev/null || true
    killall -9 opera-proxy opera-proxy-monitor 2>/dev/null || true

    echo "→ opkg remove --autoremove opera-proxy ..."
    if opkg remove --autoremove opera-proxy; then
      echo "✅ Пакет удалён"
    else
      echo "⚠ opkg remove завершился с ошибкой"
    fi
  fi

  # Репозиторий
  REPO_CONF="/opt/etc/opkg/sw.ext.io.conf"
  if [ -f "$REPO_CONF" ]; then
    echo ""
    echo "Найден репозиторий: $REPO_CONF"
    cat "$REPO_CONF" 2>/dev/null | sed 's/^/   /'
    echo ""
    if [ "$(yes_no "Удалить репозиторий sw.ext.io? [y/N]: " "n")" = "1" ]; then
      rm -f "$REPO_CONF"
      echo "✅ Репозиторий удалён"
    else
      echo "→ Репозиторий оставлен"
    fi
  else
    echo ""
    echo "Репозиторий sw.ext.io.conf не найден — пропускаем."
  fi

  # Опционально: fix-скрипт и cron
  if [ -f /opt/fix_opera_tunnel.sh ] || [ -f /opt/etc/cron.hourly/fix_opera_tunnel ]; then
    echo ""
    if [ "$(yes_no "Удалить fix-скрипт и cron-задачу? [y/N]: " "n")" = "1" ]; then
      rm -f /opt/fix_opera_tunnel.sh
      rm -f /opt/etc/cron.hourly/fix_opera_tunnel
      echo "✅ Fix-скрипт и cron удалены"
    else
      echo "→ Fix-скрипт и cron оставлены"
    fi
  fi

  echo ""
  echo "=== Удаление завершено ==="
}

# ---------------------------------------------------------------------------
# Главное меню
# ---------------------------------------------------------------------------
run_menu() {
  while true; do
    print_banner
    show_status

    printf '%b\n' "${yellow}Выберите действие:${reset}"
    echo ""
    echo "  [1]  Установить Opera-proxy (официальный)"
    echo "  [2]  Установить Opera-proxy UPX (сжатый)"
    echo "  [3]  Обновить Opera-proxy (opkg)"
    echo "  [4]  Обновление Bin Opera-Proxy из GitHub"
    echo "  [5]  Fix Opera (+socks5)"
    echo "  [6]  Остановить / Запустить сервис"
    echo "  [7]  Проверить прокси"
    echo "  [88] Удалить"
    echo "  [0]  Выход"
    echo ""

    choice=$(ask "Выбор [0-7 / 88], Enter = выход: " "0")
    case "$choice" in
      1)
        install_opera_proxy
        ask "Нажмите Enter для возврата в меню... " ""
        ;;
      2)
        install_opera_compressed
        ask "Нажмите Enter для возврата в меню... " ""
        ;;
      3)
        upgrade_opera_proxy
        ask "Нажмите Enter для возврата в меню... " ""
        ;;
      4)
        update_opera_bin
        ask "Нажмите Enter для возврата в меню... " ""
        ;;
      5)
        fix_opera
        ask "Нажмите Enter для возврата в меню... " ""
        ;;
      6)
        toggle_service
        ask "Нажмите Enter для возврата в меню... " ""
        ;;
      7)
        check_proxy
        ask "Нажмите Enter для возврата в меню... " ""
        ;;
      88)
        remove_opera_proxy
        ask "Нажмите Enter для возврата в меню... " ""
        ;;
      0|n|N|q|Q|"")
        echo "Выход."
        exit 0
        ;;
      *)
        echo "Неверный выбор."
        sleep 1
        ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
  # Если stdin — труба (curl|sh), перенаправляем на /dev/tty для меню
  if [ -r /dev/tty ]; then
    exec </dev/tty >/dev/tty 2>/dev/tty
  fi
  run_menu
}

main "$@"
