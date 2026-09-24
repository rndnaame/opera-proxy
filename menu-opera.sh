#!/bin/sh
# Меню управления Opera-Proxy (Keenetic / Entware)
# Дизайн и архитектура по образцу:
#   https://github.com/rndnaame/awg-compressed
#   https://github.com/rndnaame/awg-compressed/blob/main/install-compressed.sh
#
# Запуск:
#   sh menu-opera.sh
#   curl -sL https://raw.githubusercontent.com/rndnaame/opera-proxy/main/menu-opera.sh | sh

# URL для самообновления (пункт 99)
SCRIPT_URL="${SCRIPT_URL:-https://raw.githubusercontent.com/rndnaame/opera-proxy/main/menu-opera.sh}"
SCRIPT_URL_MIRRORS="https://ghfast.top/https://raw.githubusercontent.com/rndnaame/opera-proxy/main/menu-opera.sh https://gh-proxy.com/https://raw.githubusercontent.com/rndnaame/opera-proxy/main/menu-opera.sh"

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
proxy0_exists() {
  # t2s0 или интерфейс Proxy0 уже есть — повторно создавать не нужно
  if ip link show t2s0 >/dev/null 2>&1; then
    return 0
  fi
  if ifconfig t2s0 >/dev/null 2>&1; then
    return 0
  fi
  if command -v ndmc >/dev/null 2>&1; then
    ndmc -c "show interface Proxy0" 2>/dev/null | grep -qi 'Proxy0\|interface' && return 0
  fi
  return 1
}

configure_proxy0() {
  echo ""
  if proxy0_exists; then
    echo "→ Proxy0 / t2s0 уже есть — настройку интерфейса пропускаем"
    return 0
  fi
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

# Версия на sw.ext.io (для ARCH)
fetch_mirror_ver() {
  _arch="$1"
  curl -sL --connect-timeout 10 --max-time 20 "https://sw.ext.io/ent/${_arch}/" 2>/dev/null \
    | grep -oE "opera-proxy_[0-9][^\"'<> ]+_" \
    | sed 's/^opera-proxy_//;s/_$//' \
    | sort -V | tail -1
}

# Версия UPX-релиза (rndnaame/opera-proxy)
fetch_upx_meta() {
  # выставляет UPX_VER, UPX_TAG, UPX_IPK (для текущего IPK_SUFFIX)
  UPX_VER=""; UPX_TAG=""; UPX_IPK=""
  _html=$(curl -sL --connect-timeout 15 --max-time 30 \
    "https://github.com/rndnaame/opera-proxy/releases/latest" 2>/dev/null || true)
  [ -z "$_html" ] && _html=$(curl -sL --connect-timeout 15 --max-time 30 \
    "https://ghfast.top/https://github.com/rndnaame/opera-proxy/releases/latest" 2>/dev/null || true)
  UPX_TAG=$(echo "$_html" | grep -oE 'releases/tag/op-[0-9][^\"'\''<> /]+' | head -1 | sed 's|releases/tag/||')
  UPX_IPK=$(echo "$_html" | grep -oE "opera-proxy_[0-9][^\"'<> ]+_${IPK_SUFFIX}_compressed\\.ipk" | head -1)
  if [ -z "$UPX_IPK" ] && [ -n "$UPX_TAG" ]; then
    _html2=$(curl -sL --connect-timeout 15 --max-time 30 \
      "https://github.com/rndnaame/opera-proxy/releases/expanded_assets/${UPX_TAG}" 2>/dev/null || true)
    UPX_IPK=$(echo "$_html2" | grep -oE "opera-proxy_[0-9][^\"'<> ]+_${IPK_SUFFIX}_compressed\\.ipk" | head -1)
  fi
  [ -n "$UPX_IPK" ] && UPX_VER=$(echo "$UPX_IPK" | sed -n "s/^opera-proxy_\([^_]*\)_.*/\1/p")
  [ -z "$UPX_VER" ] && [ -n "$UPX_TAG" ] && UPX_VER=$(echo "$UPX_TAG" | sed 's/^op-//')
}

# ---------------------------------------------------------------------------
# [1] Установить Opera-proxy (подменю)
# ---------------------------------------------------------------------------
do_install_official() {
  echo ""
  echo "→ Добавление репозитория sw.ext.io ..."
  mkdir -p /opt/etc/opkg
  echo "src/gz sw http://sw.ext.io/ent/$ARCH" > /opt/etc/opkg/sw.ext.io.conf
  echo "   ✓ /opt/etc/opkg/sw.ext.io.conf"

  echo ""
  echo "→ opkg update ..."
  opkg update || echo "⚠ opkg update завершился с ошибкой (продолжаем)"

  echo ""
  if opkg list-installed 2>/dev/null | grep -q '^opera-proxy '; then
    echo "→ Обновление пакета opera-proxy (без переустановки) ..."
  else
    echo "→ Установка пакета opera-proxy ..."
  fi
  # без --force-reinstall: opkg сам обновит, не удаляя «с нуля»
  if opkg install opera-proxy; then
    echo "✅ Готово"
  else
    echo "❌ Не удалось установить/обновить opera-proxy"
    return 1
  fi

  echo ""
  echo "→ Запуск сервиса ..."
  /opt/etc/init.d/S99opera-proxy restart 2>/dev/null \
    || /opt/etc/init.d/S99opera-proxy start 2>/dev/null || true
  sleep 2

  configure_proxy0
  check_tunnel_quick
  echo ""
  echo "=== Готово ==="
}

do_install_upx() {
  echo ""
  echo "→ Поиск сжатого IPK ..."
  fetch_upx_meta
  if [ -z "$UPX_IPK" ] || [ -z "$UPX_TAG" ]; then
    echo "❌ Сжатый IPK для $IPK_SUFFIX не найден"
    echo "   https://github.com/rndnaame/opera-proxy/releases"
    return 1
  fi
  echo "   Релиз: $UPX_TAG"
  echo "   Найден: $UPX_IPK"

  URL="https://github.com/rndnaame/opera-proxy/releases/download/${UPX_TAG}/${UPX_IPK}"
  TMP_IPK="/tmp/${UPX_IPK}"

  echo ""
  echo "→ Скачивание ..."
  rm -f "$TMP_IPK"
  _dl_ok=0
  for _try_url in "$URL" "https://ghfast.top/${URL}" "https://gh-proxy.com/${URL}"; do
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
    echo "❌ Не удалось скачать $UPX_IPK"
    return 1
  fi
  echo "   ✓ $(du -h "$TMP_IPK" | awk '{print $1}')"

  echo ""
  if opkg list-installed 2>/dev/null | grep -q '^opera-proxy '; then
    echo "→ Обновление $UPX_IPK (без force-reinstall) ..."
  else
    echo "→ Установка $UPX_IPK ..."
  fi
  # обычный install: при новой версии — upgrade; при той же — opkg может отказать
  if opkg install "$TMP_IPK"; then
    echo "✅ Готово (UPX)"
  else
    # та же версия — мягкая переустановка только по согласию не делаем; пробуем --force-reinstall
    # только если версии совпали и install отказал
    echo "⚠ Обычная установка не прошла, пробуем обновление пакета ..."
    if opkg install --force-reinstall "$TMP_IPK"; then
      echo "✅ Готово (UPX, reinstall)"
    else
      echo "❌ opkg install не удался"
      rm -f "$TMP_IPK"
      return 1
    fi
  fi
  rm -f "$TMP_IPK"

  echo ""
  echo "→ Запуск сервиса ..."
  /opt/etc/init.d/S99opera-proxy restart 2>/dev/null \
    || /opt/etc/init.d/S99opera-proxy start 2>/dev/null || true
  sleep 2

  configure_proxy0
  check_tunnel_quick
  echo ""
  echo "=== Готово ==="
}

install_opera_menu() {
  print_banner
  printf '%b\n' "${bold}[1] Установить Opera-proxy${reset}"
  echo ""

  detect_arch
  detect_installed
  if [ -z "$ARCH" ]; then
    echo "❌ Неизвестная архитектура. Нужны: aarch64 / mipsel / mips"
    opkg print-architecture 2>/dev/null || true
    return 1
  fi

  case "$ARCH" in
    aarch64) IPK_SUFFIX="aarch64-3.10" ;;
    mipsel)  IPK_SUFFIX="mipsel-3.4" ;;
    mips)    IPK_SUFFIX="mips-3.4" ;;
    *) IPK_SUFFIX="" ;;
  esac

  echo "Архитектура: $A → $ARCH"
  if [ -n "$CUR_VER" ]; then
    echo "Сейчас установлено: $CUR_VER"
  else
    echo "Сейчас установлено: нет"
  fi
  echo ""

  echo "→ Определение доступных версий ..."
  MIRROR_VER=$(fetch_mirror_ver "$ARCH")
  fetch_upx_meta

  echo ""
  printf '%b\n' "${yellow}Доступные версии для установки:${reset}"
  echo ""
  if [ -n "$MIRROR_VER" ]; then
    echo "  [1]  С репозитория sw.ext.io   (${MIRROR_VER})"
  else
    echo "  [1]  С репозитория sw.ext.io   (версия не определена)"
  fi
  if [ -n "$UPX_VER" ]; then
    echo "  [2]  Сжатая версия UPX         (${UPX_VER})"
  else
    echo "  [2]  Сжатая версия UPX         (не найдена)"
  fi
  echo "  [0]  Назад"
  echo ""

  sub=$(ask "Выбор [0-2]: " "0")
  case "$sub" in
    1) do_install_official ;;
    2)
      if [ -z "$IPK_SUFFIX" ]; then
        echo "❌ Нет сжатого IPK для архитектуры: $ARCH"
        return 1
      fi
      do_install_upx
      ;;
    0|"") echo "→ Назад" ;;
    *) echo "Неверный выбор." ;;
  esac
}

# ---------------------------------------------------------------------------
# [2] Обновить Opera-proxy (opkg)
# ---------------------------------------------------------------------------
upgrade_opera_proxy() {
  print_banner
  printf '%b\n' "${bold}[2] Обновление Opera-proxy (opkg)${reset}"
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
# [3] Обновление Bin Opera-Proxy из GitHub
# ---------------------------------------------------------------------------
update_opera_bin() {
  print_banner
  printf '%b\n' "${bold}[3] Обновление opera-proxy из GitHub${reset}"
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
# [4] Fix Opera (+socks5)
# ---------------------------------------------------------------------------
fix_opera() {
  print_banner
  printf '%b\n' "${bold}[4] Fix Opera (+socks5)${reset}"
  echo ""

  if [ ! -f /opt/etc/init.d/S99opera-proxy ]; then
    echo "✗ opera-proxy не установлен!"
    return 1
  fi

  echo "→ Обновляем /opt/fix_opera_tunnel.sh ..."
  cat > /opt/fix_opera_tunnel.sh << 'FIXSCRIPT'
#!/bin/sh
# Fix Opera tunnel: IP + Telegram; при провале — замена socks5
TAG="opera-proxy"
LOG="/var/log/opera-tunnel.log"
mkdir -p "$(dirname "$LOG")"

log() {
  ts="$(date "+%Y-%m-%d %H:%M:%S")"
  echo "[$ts] $2" | tee -a "$LOG"
  logger -p user."$1" -t "$TAG" "$2" 2>/dev/null || true
}

show_config() {
  [ -f /opt/etc/opera-proxy.conf ] && log notice "   Параметры: $(cat /opt/etc/opera-proxy.conf)"
}

# Проверка IP через t2s0 → 0 ок / 1 нет; печатает IP в LAST_IP
check_ip() {
  LAST_IP=$(curl --interface t2s0 -m 10 --connect-timeout 6 -s http://api.ipify.org 2>/dev/null)
  echo "$LAST_IP" | grep -qE "^[0-9]{1,3}(\.[0-9]{1,3}){3}$"
}

# Проверка Telegram через t2s0 → 0 ок / 1 нет
check_telegram() {
  code=$(curl --interface t2s0 -s -o /dev/null -w "%{http_code}" -m 12 --connect-timeout 7 \
    -L https://web.telegram.org 2>/dev/null)
  case "$code" in
    200|301|302|303|307|308) return 0 ;;
    *) return 1 ;;
  esac
}

# Полная проверка: IP + Telegram
tunnel_ok() {
  if ! check_ip; then
    log err "✗ IP через t2s0: нет"
    return 1
  fi
  log warn "✓ IP: $LAST_IP"
  if ! check_telegram; then
    log err "✗ Telegram (web.telegram.org) через t2s0: нет"
    return 1
  fi
  log warn "✓ Telegram: OK"
  return 0
}

# ── Быстрый выход, если всё уже работает ──
if tunnel_ok; then
  log warn "✓ Туннель работает (IP + Telegram)"
  show_config
  exit 0
fi

log err "✗ Туннель требует восстановления (IP и/или Telegram)"

# Proxy0 DOWN на время подбора — иначе в журнале сыпется socks5 session connect
proxy0_down() {
  log warn "Proxy0 → down (тишина в журнале на время подбора)"
  ndmc -c "interface Proxy0 down" 2>/dev/null || true
  /opt/etc/init.d/S99opera-proxy stop 2>/dev/null || true
  killall -9 opera-proxy opera-proxy-monitor 2>/dev/null || true
  sleep 2
}

proxy0_up() {
  log warn "Proxy0 → up"
  ndmc -c "interface Proxy0 up" 2>/dev/null || true
  ndmc -c "system configuration save" 2>/dev/null || true
  sleep 3
}

proxy0_down

# Источники: мало + недавно проверенные (не 3000 мёртвых)
TEMP=/tmp/s5.raw
POOL=/tmp/s5.pool
rm -f "$TEMP" "$POOL"
: > "$TEMP"

fetch_list() {
  _url="$1"
  _label="$2"
  _tmp="/tmp/s5.src"
  rm -f "$_tmp"
  if curl -sL -m 15 --connect-timeout 8 -o "$_tmp" "$_url" 2>/dev/null && [ -s "$_tmp" ]; then
    _n=$(grep -cE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+' "$_tmp" 2>/dev/null || echo 0)
    log notice "   + $_label: $_n"
    cat "$_tmp" >> "$TEMP"
    return 0
  fi
  log notice "   − $_label: недоступен"
  return 1
}

log warn "Загрузка качественных списков socks5..."
# monosans — hourly re-check, sorted by speed (~200)
fetch_list "https://raw.githubusercontent.com/monosans/proxy-list/main/proxies/socks5.txt" "monosans"
# proxmint — re-validated every 30 min (~400)
fetch_list "https://raw.githubusercontent.com/proxmint/free-proxy-list/main/proxies/socks5.txt" "proxmint"
# ProxyScrape — только timeout≤3s
fetch_list "https://api.proxyscrape.com/v2/?request=displayproxies&protocol=socks5&timeout=3000&country=all" "proxyscrape≤3s"
# jetkai online (~400)
fetch_list "https://raw.githubusercontent.com/jetkai/proxy-list/main/online-proxies/txt/proxies-socks5.txt" "jetkai"
# relayglass — check every 5 min (~100)
fetch_list "https://raw.githubusercontent.com/relayglass/free-proxy-list/main/protocol/socks5/socks5.txt" "relayglass"

# Нормализация, unique, перемешивание
sed -E 's/\r//g; s|^socks5?h?://||; s/[[:space:]]+//g; s/#.*//' "$TEMP" 2>/dev/null \
  | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}:[0-9]+' \
  | sort -u \
  | awk 'BEGIN{srand()} {print rand() "\t" $0}' \
  | sort -n \
  | cut -f2- > "$POOL"

PROXY_COUNT=$(wc -l < "$POOL" 2>/dev/null | tr -d ' ')
log warn "Пул после unique: ${PROXY_COUNT:-0} шт."

if [ -z "$PROXY_COUNT" ] || [ "$PROXY_COUNT" -lt 5 ]; then
  log err "Слишком мало прокси в пуле — источники недоступны?"
  exit 1
fi

# Проверка socks5 для -api-proxy: нужен HTTPS CONNECT (как к API Opera), не голый HTTP
socks5_ok() {
  _p="$1"
  # 1) HTTPS через socks5h (CONNECT) — ближе к реальному api-proxy
  _code=$(curl -x "socks5h://$_p" -m 6 --connect-timeout 3 -s -o /dev/null -w "%{http_code}" \
    https://api.ipify.org 2>/dev/null)
  [ "$_code" = "200" ] && return 0
  # 2) запасной HTTP (хуже, но лучше чем ничего)
  _code=$(curl -x "socks5h://$_p" -m 4 --connect-timeout 2 -s -o /dev/null -w "%{http_code}" \
    http://api.ipify.org 2>/dev/null)
  [ "$_code" = "200" ] && return 0
  return 1
}

# Отбор: HTTPS-проверка, без дублей, второй проход если пусто
NEED=5
MAX_TEST=80
COUNT=0
TESTED=0
CANDS=""

pick_candidates() {
  _max="$1"
  while IFS= read -r p && [ "$COUNT" -lt "$NEED" ] && [ "$TESTED" -lt "$_max" ]; do
    [ -z "$p" ] && continue
    # уже в списке?
    case " $CANDS " in *" $p "*) continue ;; esac
    TESTED=$((TESTED + 1))
    if socks5_ok "$p"; then
      COUNT=$((COUNT + 1))
      CANDS="$CANDS $p"
      log notice "   кандидат #$COUNT: $p  (проверено $TESTED, HTTPS/HTTP ok)"
    fi
  done < "$POOL"
}

log warn "Отбор socks5 для API (HTTPS CONNECT, макс ${MAX_TEST})..."
pick_candidates "$MAX_TEST"

# Второй проход: ещё 80, если мало кандидатов
if [ "$COUNT" -lt 2 ]; then
  log warn "Мало кандидатов ($COUNT) — второй проход (+80)..."
  # сдвиг «указателя»: пропускаем уже просмотренные через tail
  tail -n +$((TESTED + 1)) "$POOL" > /tmp/s5.pool2 2>/dev/null || true
  if [ -s /tmp/s5.pool2 ]; then
    POOL=/tmp/s5.pool2
    pick_candidates $((TESTED + 80))
  fi
fi

log warn "Отбор: найдено $COUNT живых (уникальных), проверено $TESTED"

# Только уникальные непустые — без P2=P1 дублей
if [ -z "$CANDS" ]; then
  log err "Нет пригодных socks5 (HTTPS) — список мёртв или недоступен"
  # Proxy0 остаётся down
  exit 1
fi

start() {
  echo "OPTIONS=\"-socks-mode -country EU $1\"" > /opt/etc/opera-proxy.conf
  /opt/etc/init.d/S99opera-proxy stop 2>/dev/null
  killall -9 opera-proxy 2>/dev/null
  sleep 2
  /opt/etc/init.d/S99opera-proxy start
}

SUCCESS=0
SEEN=""
for p in $CANDS; do
  [ -z "$p" ] && continue
  case " $SEEN " in *" $p "*) continue ;; esac
  SEEN="$SEEN $p"

  log warn "Пробуем socks5://$p"
  start "-api-proxy socks5://$p"
  sleep 8
  proxy0_up
  i=1
  while [ "$i" -le 10 ]; do
    if tunnel_ok; then
      log warn "✓ УСПЕШНО! Прокси: $p  IP: $LAST_IP  Telegram: OK"
      show_config
      ndmc -c "interface Proxy0 ping-check profile default" 2>/dev/null
      ndmc -c "system configuration save" 2>/dev/null
      SUCCESS=1
      exit 0
    fi
    sleep 2
    i=$((i + 1))
  done
  log warn "   $p — не подошёл как api-proxy (IP и/или Telegram)"
  proxy0_down
done

[ "$SUCCESS" -eq 0 ] && log err "Не удалось восстановить туннель (IP + Telegram)"
log warn "Proxy0 оставлен down — запустите Fix снова или поднимите интерфейс вручную"
exit 1
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

  echo "✅ Скрипт обновлён: /opt/fix_opera_tunnel.sh"
  echo "Cron настроен (каждый час)"
  echo ""
  echo "Запускаем скрипт..."
  echo ""
  /opt/fix_opera_tunnel.sh
}

# ---------------------------------------------------------------------------
# [5] Остановить / Запустить сервис
# ---------------------------------------------------------------------------
toggle_service() {
  print_banner
  printf '%b\n' "${bold}[5] Управление сервисом opera-proxy${reset}"
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
# [6] Проверить прокси
# ---------------------------------------------------------------------------
check_proxy() {
  print_banner
  printf '%b\n' "${bold}[6] Проверка прокси (через t2s0)${reset}"
  echo ""

  detect_installed

  # Статус интерфейса
  if [ "$T2S0_UP" = "1" ]; then
    printf "   Интерфейс t2s0 : %bUP%b\n" "$green" "$reset"
  else
    printf "   Интерфейс t2s0 : %bDOWN / отсутствует%b\n" "$red" "$reset"
    echo ""
    echo "⚠ Без активного t2s0 проверка через Proxy0 невозможна."
    echo "   Включите Proxy0 или выполните Fix (пункт 4)."
    return 1
  fi

  if [ "$SVC_RUNNING" = "1" ]; then
    printf "   Сервис         : %bзапущен%b\n" "$green" "$reset"
  else
    printf "   Сервис         : %bостановлен%b\n" "$yellow" "$reset"
  fi

  # Параметры запуска opera-proxy
  echo ""
  printf '%b\n' "${light_blue}────────────────────────────────────────────────${reset}"
  printf '%b\n' "${bold}  Параметры opera-proxy${reset}"
  printf '%b\n' "${light_blue}────────────────────────────────────────────────${reset}"
  if [ -f /opt/etc/opera-proxy.conf ]; then
    echo ""
    echo "  Конфиг: /opt/etc/opera-proxy.conf"
    while IFS= read -r _line || [ -n "$_line" ]; do
      [ -z "$_line" ] && continue
      echo "    $_line"
    done < /opt/etc/opera-proxy.conf
  else
    echo ""
    echo "  Конфиг: нет (/opt/etc/opera-proxy.conf)"
  fi
  # Фактическая командная строка процесса
  _cmdline=""
  _pid=$(pgrep -f "[o]pera-proxy" 2>/dev/null | head -1)
  if [ -n "$_pid" ] && [ -r "/proc/$_pid/cmdline" ]; then
    _cmdline=$(tr '\0' ' ' < "/proc/$_pid/cmdline" 2>/dev/null | sed 's/[[:space:]]*$//')
  fi
  if [ -z "$_cmdline" ]; then
    _cmdline=$(ps w 2>/dev/null | grep "[o]pera-proxy" | head -1 | sed 's/^[[:space:]]*[0-9]*[[:space:]]*//' || true)
  fi
  if [ -n "$_cmdline" ]; then
    echo ""
    echo "  Процесс (pid ${_pid:-?}):"
    echo "    $_cmdline"
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
    echo "        Попробуйте Fix (пункт 4) или перезапуск сервиса (пункт 5)."
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
# [99] Обновить скрипт меню
# ---------------------------------------------------------------------------
update_menu_script() {
  print_banner
  printf '%b\n' "${bold}[99] Обновление скрипта меню${reset}"
  echo ""
  echo "Источник: $SCRIPT_URL"
  echo ""

  TMP="/tmp/menu-opera.sh.new"
  rm -f "$TMP"

  _dl_ok=0
  for _u in "$SCRIPT_URL" $SCRIPT_URL_MIRRORS; do
    echo "→ Скачивание: $_u"
    if command -v curl >/dev/null 2>&1; then
      curl -fL --connect-timeout 15 --max-time 60 -o "$TMP" "$_u" 2>/dev/null && _dl_ok=1
    fi
    if [ "$_dl_ok" != "1" ] && command -v wget >/dev/null 2>&1; then
      wget -q -T 30 -O "$TMP" "$_u" 2>/dev/null && _dl_ok=1
    fi
    [ -s "$TMP" ] && head -1 "$TMP" | grep -q '^#!' && _dl_ok=1
    [ "$_dl_ok" = "1" ] && [ -s "$TMP" ] && break
    rm -f "$TMP"
    _dl_ok=0
  done

  if [ ! -s "$TMP" ] || ! head -1 "$TMP" | grep -q '^#!'; then
    echo "❌ Не удалось скачать актуальный скрипт"
    rm -f "$TMP"
    return 1
  fi

  # Куда ставить
  DEST=""
  case "$0" in
    /*)
      if [ -f "$0" ] && [ -w "$0" ]; then
        DEST="$0"
      fi
      ;;
    ./*|*)
      if [ -f "$0" ] && [ -w "$0" ]; then
        DEST="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/$(basename "$0")"
      fi
      ;;
  esac

  # Типичные пути, если запуск через curl|sh или $0 не файл
  if [ -z "$DEST" ] || [ ! -f "$DEST" ]; then
    for _try in \
      /opt/bin/menu-opera.sh \
      /opt/sbin/menu-opera.sh \
      /opt/etc/menu-opera.sh \
      ./menu-opera.sh
    do
      if [ -f "$_try" ] && [ -w "$_try" ]; then
        DEST="$_try"
        break
      fi
    done
  fi

  if [ -z "$DEST" ] || [ ! -f "$DEST" ]; then
    # Сохраняем в /opt/bin по умолчанию
    mkdir -p /opt/bin 2>/dev/null || true
    DEST="/opt/bin/menu-opera.sh"
    echo "→ Файл скрипта не найден — установка в $DEST"
  else
    echo "→ Обновление: $DEST"
    if cmp -s "$TMP" "$DEST" 2>/dev/null; then
      echo "✅ Уже актуальная версия"
      rm -f "$TMP"
      return 0
    fi
  fi

  chmod +x "$TMP"
  if mv -f "$TMP" "$DEST"; then
    chmod +x "$DEST"
    echo "✅ Скрипт обновлён: $DEST"
    echo ""
    if [ "$(yes_no "Перезапустить меню сейчас? [Y/n]: " "y")" = "1" ]; then
      echo "→ Перезапуск..."
      exec sh "$DEST"
    fi
  else
    echo "❌ Не удалось записать $DEST"
    rm -f "$TMP"
    return 1
  fi
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
    echo "  [1]  Установить Opera-proxy"
    echo "  [2]  Обновить Opera-proxy (opkg)"
    echo "  [3]  Обновление Bin Opera-Proxy из GitHub"
    echo "  [4]  Fix Opera (+socks5)"
    echo "  [5]  Остановить / Запустить сервис"
    echo "  [6]  Проверить прокси"
    echo "  [88] Удалить"
    echo "  [99] Обновить скрипт"
    echo "  [0]  Выход"
    echo ""

    choice=$(ask "Выбор [0-6 / 88 / 99], Enter = выход: " "0")
    case "$choice" in
      1)
        install_opera_menu
        ask "Нажмите Enter для возврата в меню... " ""
        ;;
      2)
        upgrade_opera_proxy
        ask "Нажмите Enter для возврата в меню... " ""
        ;;
      3)
        update_opera_bin
        ask "Нажмите Enter для возврата в меню... " ""
        ;;
      4)
        fix_opera
        ask "Нажмите Enter для возврата в меню... " ""
        ;;
      5)
        toggle_service
        ask "Нажмите Enter для возврата в меню... " ""
        ;;
      6)
        check_proxy
        ask "Нажмите Enter для возврата в меню... " ""
        ;;
      88)
        remove_opera_proxy
        ask "Нажмите Enter для возврата в меню... " ""
        ;;
      99)
        update_menu_script
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
