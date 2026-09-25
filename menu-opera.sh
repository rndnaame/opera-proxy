#!/bin/sh
# Меню управления Opera-Proxy (Keenetic / Entware)
# Дизайн и архитектура по образцу:
#   https://github.com/rndnaame/awg-compressed
#   https://github.com/rndnaame/awg-compressed/blob/main/install-compressed.sh
#
# Запуск:
#   sh menu-opera.sh
#   curl -sL https://raw.githubusercontent.com/rndnaame/opera-proxy/main/menu-opera.sh | sh
#
# История версий:
#   1.1.3 — пункт [6]: убран вывод конфига, добавлена 4-я проверка google.com через t2S
#   1.1.2 — пункт [6]: проверка прокси через локальный SOCKS5 (127.0.0.1) вместо t2S
#   1.1.0 — conf SNI/DoH/COUNTRY, умный ProxyX, удаление по description, t2sN
#   1.0.0 — базовое меню: install/UPX/Fix/check/remove/[99]

MENU_VERSION="1.1.3"

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
  printf '%b\n' "${light_blue}Opera-Proxy (Keenetic/Entware) версия меню: ${bold}${MENU_VERSION}${reset}${light_blue}${reset}"
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

  find_opera_iface 2>/dev/null || IFACE="Proxy0"
  T2S=$(iface_to_t2s "$IFACE")
  T2S0_UP=0
  if ip link show "$T2S" 2>/dev/null | grep -q "state UP"; then
    T2S0_UP=1
  elif ifconfig "$T2S" 2>/dev/null | grep -q "UP"; then
    T2S0_UP=1
  fi
  if [ "$T2S0_UP" = "1" ]; then
    printf "   %s (%s): %bUP%b\n" "$T2S" "$IFACE" "$green" "$reset"
  else
    printf "   %s (%s): %bDOWN / нет%b\n" "$T2S" "$IFACE" "$yellow" "$reset"
  fi

  if [ "$FIX_EXISTS" = "1" ]; then
    printf "   Fix-скрипт  : %bесть%b (%s)\n" "$green" "$reset" "$FIX_SCRIPT"
  else
    printf "   Fix-скрипт  : %bнет%b\n" "$yellow" "$reset"
  fi
  echo ""
}

# ---------------------------------------------------------------------------
# Conf (SNI + DoH + COUNTRY) + умный ProxyX
# ---------------------------------------------------------------------------
OP_CONF_FILE="/opt/etc/opera-proxy.conf"
IFACE_DESC="OperaProxy"
BIND_PORT_DEFAULT="18080"

# Записать conf (SNI/DoH/COUNTRY). Не затирает существующий без force.
write_opera_conf() {
  _force="${1:-}"
  if [ -f "$OP_CONF_FILE" ] && [ "$_force" != "force" ]; then
    # уже есть — только убедимся, что OPTIONS собирается
    if ! grep -q 'fake-SNI\|BOOTSTRAP_DNS\|COUNTRY=' "$OP_CONF_FILE" 2>/dev/null; then
      echo "   ⚠ старый conf без SNI/DoH — обновляем (force)"
      _force="force"
    else
      echo "   conf уже есть: $OP_CONF_FILE"
      return 0
    fi
  fi
  _api_extra=""
  if [ -f "$OP_CONF_FILE" ]; then
    _api_extra=$(grep -oE '\-api-proxy[[:space:]]+[^"[:space:]]+' "$OP_CONF_FILE" 2>/dev/null | head -1 || true)
  fi
  cat > "$OP_CONF_FILE" << 'CONFEOF'
# Конфигурация opera-proxy (Keenetic / Entware)
# После правок: /opt/etc/init.d/S99opera-proxy restart

# Регион: EU | AM | AS
COUNTRY="EU"

# 127.0.0.1 — только роутер; 0.0.0.0 — вся LAN
BIND_ADDR="127.0.0.1"
BIND_PORT="18080"

# Обход ТСПУ/DPI
OBFUSCATE="yes"
FAKE_SNI="2gis.com"

# DoH для поиска серверов Opera
BOOTSTRAP_DNS="https://dns.google/dns-query,https://1.1.1.1/dns-query"

# random | fastest
SERVER_SELECT="random"
VERBOSITY="30"

# Сборка OPTIONS (раскрывается при source conf)
OPTIONS="-socks-mode -country $COUNTRY -bind-address ${BIND_ADDR}:${BIND_PORT} -server-selection $SERVER_SELECT -verbosity $VERBOSITY -bootstrap-dns $BOOTSTRAP_DNS"
if [ "$OBFUSCATE" = "yes" ] && [ -n "$FAKE_SNI" ]; then
  OPTIONS="$OPTIONS -fake-SNI $FAKE_SNI"
fi
CONFEOF
  if [ -n "$_api_extra" ]; then
    {
      echo ""
      echo "# api-proxy (добавлено Fix)"
      echo "OPTIONS=\"\$OPTIONS $_api_extra\""
    } >> "$OP_CONF_FILE"
  fi
  echo "   ✓ conf: $OP_CONF_FILE (SNI/DoH/COUNTRY)"
}

# Найти ProxyX с description Opera/OperaProxy или первый свободный
find_opera_iface() {
  IFACE=""
  if ! command -v ndmc >/dev/null 2>&1; then
    IFACE="Proxy0"
    return 0
  fi
  _rc=$(ndmc -c "show running-config" 2>/dev/null || echo "")
  if [ -n "$_rc" ]; then
    IFACE=$(printf '%s\n' "$_rc" | awk '
      /^interface Proxy[0-9]+/ { cur=$2 }
      /description.*(OperaProxy|Opera)/ { print cur; exit }
    ')
  fi
  if [ -z "$IFACE" ] && [ -n "$_rc" ]; then
    for i in 0 1 2 3 4 5 6 7 8 9; do
      if ! printf '%s\n' "$_rc" | grep -q "^interface Proxy$i"; then
        IFACE="Proxy$i"
        break
      fi
    done
  fi
  [ -z "$IFACE" ] && IFACE="Proxy0"
}

# Proxy0 → t2s0, Proxy1 → t2s1, ...
iface_to_t2s() {
  _if="${1:-Proxy0}"
  _n=$(echo "$_if" | sed -n 's/^Proxy\([0-9]\+\)$/\1/p')
  [ -z "$_n" ] && _n=0
  echo "t2s$_n"
}

opera_iface_exists() {
  # true только если уже есть iface с description Opera/OperaProxy
  if ! command -v ndmc >/dev/null 2>&1; then
    return 1
  fi
  _rc=$(ndmc -c "show running-config" 2>/dev/null || echo "")
  printf '%s\n' "$_rc" | awk '
    /^interface Proxy[0-9]+/ { cur=$2 }
    /description.*(OperaProxy|Opera)/ { found=1 }
    END { exit found?0:1 }
  ' 2>/dev/null
}

configure_proxy0() {
  echo ""
  find_opera_iface
  _bind="${BIND_PORT_DEFAULT}"
  if [ -f "$OP_CONF_FILE" ]; then
    # shellcheck: extract BIND_PORT
    _bp=$(sed -n 's/^BIND_PORT="\([^"]*\)".*/\1/p' "$OP_CONF_FILE" | head -1)
    [ -n "$_bp" ] && _bind="$_bp"
  fi

  if opera_iface_exists; then
    echo "→ Интерфейс $IFACE (Opera) уже есть — настройку пропускаем"
    return 0
  fi

  echo "→ Настройка интерфейса $IFACE через ndmc (upstream 127.0.0.1:${_bind}) ..."
  if command -v ndmc >/dev/null 2>&1; then
    ndmc -c "interface $IFACE" 2>/dev/null || true
    ndmc -c "interface $IFACE proxy protocol socks5" 2>/dev/null || true
    ndmc -c "interface $IFACE proxy socks5" 2>/dev/null || true
    ndmc -c "no interface $IFACE proxy socks5-udp" 2>/dev/null || true
    ndmc -c "no interface $IFACE authentication" 2>/dev/null || true
    ndmc -c "no interface $IFACE authentication identity" 2>/dev/null || true
    ndmc -c "no interface $IFACE authentication password" 2>/dev/null || true
    ndmc -c "interface $IFACE proxy upstream 127.0.0.1 ${_bind}" 2>/dev/null || true
    ndmc -c "interface $IFACE ip global auto" 2>/dev/null || true
    ndmc -c "interface $IFACE description $IFACE_DESC" 2>/dev/null || true
    ndmc -c "interface $IFACE up" 2>/dev/null || true
    ndmc -c "system configuration save" 2>/dev/null || true
    echo "   ✓ $IFACE настроен (description=$IFACE_DESC, socks5-udp off)"
  else
    echo "   ⚠ ndmc не найден — настройте Proxy вручную"
  fi
}

check_tunnel_quick() {
  find_opera_iface 2>/dev/null || IFACE="Proxy0"
  T2S=$(iface_to_t2s "$IFACE")
  echo ""
  echo "→ Проверка туннеля ($T2S / $IFACE) ..."
  sleep 3
  _ok=0
  if curl --interface "$T2S" -s -m 8 myip.wtf 2>/dev/null; then
    echo ""
    _ok=1
  fi
  if curl --interface "$T2S" -s -m 8 2ip.io 2>/dev/null; then
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
  echo "→ Конфиг opera-proxy (SNI/DoH/COUNTRY) ..."
  write_opera_conf

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
  echo "→ Конфиг opera-proxy (SNI/DoH/COUNTRY) ..."
  write_opera_conf

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
  find_opera_iface 2>/dev/null || IFACE="Proxy0"
  T2S=$(iface_to_t2s "$IFACE")
  echo "🌐 Проверка $T2S ($IFACE):"
  curl --interface "$T2S" -s -m 8 2ip.io 2>/dev/null || echo "2ip.io: нет"
  echo ""
  curl --interface "$T2S" -s -m 8 ifconfig.co 2>/dev/null || echo "ifconfig.co: нет"
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

# IFACE/T2S задаются выше в fix-скрипте; fallback Proxy0/t2s0
[ -z "$IFACE" ] && IFACE="Proxy0"
[ -z "$T2S" ] && T2S="t2s0"

# Проверка IP через Keenetic tunnel iface
check_ip() {
  LAST_IP=$(curl --interface "$T2S" -m 10 --connect-timeout 6 -s http://api.ipify.org 2>/dev/null)
  echo "$LAST_IP" | grep -qE "^[0-9]{1,3}(\.[0-9]{1,3}){3}$"
}

check_telegram() {
  code=$(curl --interface "$T2S" -s -o /dev/null -w "%{http_code}" -m 12 --connect-timeout 7 \
    -L https://web.telegram.org 2>/dev/null)
  case "$code" in
    200|301|302|303|307|308) return 0 ;;
    *) return 1 ;;
  esac
}

# Проверка напрямую через локальный SOCKS opera-proxy (без Proxy0)
LOCAL_SOCKS="127.0.0.1:18080"
check_ip_local() {
  LAST_IP=$(curl --socks5-hostname "$LOCAL_SOCKS" -m 10 --connect-timeout 6 -s https://api.ipify.org 2>/dev/null)
  echo "$LAST_IP" | grep -qE "^[0-9]{1,3}(\.[0-9]{1,3}){3}$"
}

check_telegram_local() {
  code=$(curl --socks5-hostname "$LOCAL_SOCKS" -s -o /dev/null -w "%{http_code}" -m 12 --connect-timeout 7 \
    -L https://web.telegram.org 2>/dev/null)
  case "$code" in
    200|301|302|303|307|308) return 0 ;;
    *) return 1 ;;
  esac
}

# Полная проверка туннеля Keenetic (t2s0)
tunnel_ok() {
  if ! check_ip; then
    log err "✗ IP через $T2S: нет"
    return 1
  fi
  log warn "✓ IP: $LAST_IP"
  if ! check_telegram; then
    log err "✗ Telegram через $T2S: нет"
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

# IFACE по description Opera/OperaProxy → t2sN
IFACE="Proxy0"
_rc=$(ndmc -c "show running-config" 2>/dev/null || echo "")
_found=$(printf '%s\n' "$_rc" | awk '
  /^interface Proxy[0-9]+/ { cur=$2 }
  /description.*(OperaProxy|Opera)/ { print cur; exit }
')
[ -n "$_found" ] && IFACE="$_found"
_n=$(echo "$IFACE" | sed -n 's/^Proxy\([0-9][0-9]*\)$/\1/p')
[ -z "$_n" ] && _n=0
T2S="t2s$_n"
log notice "Интерфейс: $IFACE ($T2S)"

proxy0_down() {
  log warn "$IFACE → down (тишина в журнале на время подбора)"
  ndmc -c "interface $IFACE down" 2>/dev/null || true
  /opt/etc/init.d/S99opera-proxy stop 2>/dev/null || true
  killall -9 opera-proxy opera-proxy-monitor 2>/dev/null || true
  sleep 2
}

proxy0_up() {
  log warn "$IFACE → up"
  ndmc -c "interface $IFACE up" 2>/dev/null || true
  ndmc -c "system configuration save" 2>/dev/null || true
  sleep 3
}

# Порядок: down → списки → отбор → up → тест Opera
proxy0_down

TEMP=/tmp/s5.raw
POOL=/tmp/s5.pool
CACHE="/opt/etc/opera-s5.cache"
rm -f "$TEMP" "$POOL"
: > "$TEMP"

# Скачать URL; для GitHub — зеркала ghfast / gh-proxy
curl_get() {
  _u="$1"
  _out="$2"
  rm -f "$_out"
  if curl -sL -m 12 --connect-timeout 6 -o "$_out" "$_u" 2>/dev/null && [ -s "$_out" ]; then
    return 0
  fi
  case "$_u" in
    https://raw.githubusercontent.com/*)
      for _px in \
        "https://ghfast.top/$_u" \
        "https://gh-proxy.com/$_u" \
        "https://mirror.ghproxy.com/$_u"
      do
        rm -f "$_out"
        if curl -sL -m 15 --connect-timeout 8 -o "$_out" "$_px" 2>/dev/null && [ -s "$_out" ]; then
          return 0
        fi
      done
      ;;
  esac
  rm -f "$_out"
  return 1
}

fetch_list() {
  _url="$1"
  _label="$2"
  _tmp="/tmp/s5.src"
  if curl_get "$_url" "$_tmp"; then
    _n=$(grep -cE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+' "$_tmp" 2>/dev/null || echo 0)
    if [ "$_n" -gt 0 ] 2>/dev/null; then
      log notice "   + $_label: $_n"
      cat "$_tmp" >> "$TEMP"
      return 0
    fi
  fi
  log notice "   − $_label: недоступен"
  return 1
}

log warn "Загрузка списков socks5..."
GOT=0
fetch_list "https://raw.githubusercontent.com/monosans/proxy-list/main/proxies/socks5.txt" "monosans" && GOT=1
fetch_list "https://raw.githubusercontent.com/proxmint/free-proxy-list/main/proxies/socks5.txt" "proxmint" && GOT=1
fetch_list "https://api.proxyscrape.com/v2/?request=displayproxies&protocol=socks5&timeout=3000&country=all" "proxyscrape≤3s" && GOT=1
fetch_list "https://raw.githubusercontent.com/jetkai/proxy-list/main/online-proxies/txt/proxies-socks5.txt" "jetkai" && GOT=1
fetch_list "https://raw.githubusercontent.com/relayglass/free-proxy-list/main/protocol/socks5/socks5.txt" "relayglass" && GOT=1
# запасной крупный список (если качественные недоступны)
if [ "$GOT" = "0" ]; then
  fetch_list "https://raw.githubusercontent.com/TheSpeedX/PROXY-List/master/socks5.txt" "TheSpeedX" && GOT=1
  fetch_list "https://raw.githubusercontent.com/hookzof/socks5_list/master/proxy.txt" "hookzof" && GOT=1
fi

# Нормализация
sed -E 's/\r//g; s|^socks5?h?://||; s/[[:space:]]+//g; s/#.*//' "$TEMP" 2>/dev/null \
  | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}:[0-9]+' \
  | sort -u > /tmp/s5.norm

_norm_n=$(wc -l < /tmp/s5.norm 2>/dev/null | tr -d ' ')
if [ -n "$_norm_n" ] && [ "$_norm_n" -ge 5 ]; then
  # обновить кэш
  mkdir -p "$(dirname "$CACHE")" 2>/dev/null || true
  cp /tmp/s5.norm "$CACHE" 2>/dev/null || true
  log notice "   кэш обновлён: $CACHE ($_norm_n)"
else
  # fallback на кэш
  if [ -s "$CACHE" ]; then
    log warn "Источники недоступны — берём кэш $CACHE"
    cp "$CACHE" /tmp/s5.norm
    _norm_n=$(wc -l < /tmp/s5.norm 2>/dev/null | tr -d ' ')
  fi
fi

awk 'BEGIN{srand()} {print rand() "\t" $0}' /tmp/s5.norm 2>/dev/null \
  | sort -n \
  | cut -f2- > "$POOL"

PROXY_COUNT=$(wc -l < "$POOL" 2>/dev/null | tr -d ' ')
log warn "Пул после unique: ${PROXY_COUNT:-0} шт."

if [ -z "$PROXY_COUNT" ] || [ "$PROXY_COUNT" -lt 3 ]; then
  log err "Нет списка socks5 (сеть/GitHub недоступны, кэш пуст)"
  exit 1
fi

# Быстрая проверка socks5: сначала HTTP (быстрее), потом HTTPS
socks5_ok() {
  _p="$1"
  _code=$(curl -x "socks5h://$_p" -m 3 --connect-timeout 2 -s -o /dev/null -w "%{http_code}" \
    http://api.ipify.org 2>/dev/null)
  [ "$_code" = "200" ] && return 0
  _code=$(curl -x "socks5h://$_p" -m 4 --connect-timeout 2 -s -o /dev/null -w "%{http_code}" \
    https://api.ipify.org 2>/dev/null)
  [ "$_code" = "200" ] && return 0
  return 1
}

# Последовательный отбор (надёжнее на busybox, чем parallel &)
NEED=3
MAX_TEST=50
COUNT=0
TESTED=0
CANDS=""

log warn "Отбор socks5 (последовательно, макс ${MAX_TEST}, stop at ${NEED})..."

while IFS= read -r p && [ "$COUNT" -lt "$NEED" ] && [ "$TESTED" -lt "$MAX_TEST" ]; do
  [ -z "$p" ] && continue
  case " $CANDS " in *" $p "*) continue ;; esac
  TESTED=$((TESTED + 1))
  # прогресс каждые 10
  if [ $((TESTED % 10)) -eq 0 ]; then
    log notice "   ... проверено $TESTED, найдено $COUNT"
  fi
  if socks5_ok "$p"; then
    COUNT=$((COUNT + 1))
    CANDS="$CANDS $p"
    log notice "   кандидат #$COUNT: $p  (проверено $TESTED)"
  fi
done < "$POOL"

# Второй проход, если пусто
if [ "$COUNT" -lt 1 ]; then
  log warn "0 кандидатов — второй проход (+50)..."
  tail -n +$((TESTED + 1)) "$POOL" > /tmp/s5.pool2 2>/dev/null || true
  if [ -s /tmp/s5.pool2 ]; then
    while IFS= read -r p && [ "$COUNT" -lt "$NEED" ] && [ "$TESTED" -lt 100 ]; do
      [ -z "$p" ] && continue
      case " $CANDS " in *" $p "*) continue ;; esac
      TESTED=$((TESTED + 1))
      if socks5_ok "$p"; then
        COUNT=$((COUNT + 1))
        CANDS="$CANDS $p"
        log notice "   кандидат #$COUNT: $p  (проверено $TESTED)"
      fi
    done < /tmp/s5.pool2
  fi
fi

log warn "Отбор: найдено $COUNT за $TESTED проверок"

if [ -z "$CANDS" ] || [ "$COUNT" -lt 1 ]; then
  log err "Нет пригодных socks5 — список мёртв или недоступен"
  exit 1
fi
for _c in $CANDS; do
  log notice "   → $_c"
done

# Собрать OPTIONS из conf + -api-proxy (не затирать SNI/DoH)
start() {
  _extra="$1"
  CONF=/opt/etc/opera-proxy.conf
  if [ -f "$CONF" ] && grep -q 'COUNTRY=\|fake-SNI\|BOOTSTRAP_DNS' "$CONF" 2>/dev/null; then
    # убрать старый -api-proxy из conf, пересобрать
    COUNTRY="EU"; BIND_ADDR="127.0.0.1"; BIND_PORT="18080"
    OBFUSCATE="yes"; FAKE_SNI="2gis.com"
    BOOTSTRAP_DNS="https://dns.google/dns-query,https://1.1.1.1/dns-query"
    SERVER_SELECT="random"; VERBOSITY="30"
    # shellcheck: source conf vars
    # извлекаем значения без выполнения if/OPTIONS
    eval "$(grep -E '^(COUNTRY|BIND_ADDR|BIND_PORT|OBFUSCATE|FAKE_SNI|BOOTSTRAP_DNS|SERVER_SELECT|VERBOSITY)=' "$CONF" 2>/dev/null)"
    OPTIONS="-socks-mode -country $COUNTRY -bind-address ${BIND_ADDR}:${BIND_PORT} -server-selection $SERVER_SELECT -verbosity $VERBOSITY -bootstrap-dns $BOOTSTRAP_DNS"
    [ "$OBFUSCATE" = "yes" ] && [ -n "$FAKE_SNI" ] && OPTIONS="$OPTIONS -fake-SNI $FAKE_SNI"
    [ -n "$_extra" ] && OPTIONS="$OPTIONS $_extra"
    # сохранить conf с актуальным OPTIONS
    {
      echo "# auto by fix_opera_tunnel"
      echo "COUNTRY=\"$COUNTRY\""
      echo "BIND_ADDR=\"$BIND_ADDR\""
      echo "BIND_PORT=\"$BIND_PORT\""
      echo "OBFUSCATE=\"$OBFUSCATE\""
      echo "FAKE_SNI=\"$FAKE_SNI\""
      echo "BOOTSTRAP_DNS=\"$BOOTSTRAP_DNS\""
      echo "SERVER_SELECT=\"$SERVER_SELECT\""
      echo "VERBOSITY=\"$VERBOSITY\""
      echo "OPTIONS=\"$OPTIONS\""
    } > "$CONF"
  else
    echo "OPTIONS=\"-socks-mode -country EU -bind-address 127.0.0.1:18080 $_extra\"" > "$CONF"
  fi
  /opt/etc/init.d/S99opera-proxy stop 2>/dev/null
  killall -9 opera-proxy 2>/dev/null
  sleep 2
  /opt/etc/init.d/S99opera-proxy start
}

# IFACE остаётся down; проверка через local SOCKS :18080
SUCCESS=0
for p in $CANDS; do
  [ -z "$p" ] && continue
  log warn "Пробуем socks5://$p"
  start "-api-proxy socks5://$p"
  sleep 6
  i=1
  while [ "$i" -le 6 ]; do
    if check_ip_local; then
      log warn "✓ IP (socks 18080): $LAST_IP"
      if check_telegram_local; then
        log warn "✓ Telegram (socks 18080): OK"
        log warn "✓ УСПЕШНО! Прокси: $p  IP: $LAST_IP"
        show_config
        proxy0_up
        ndmc -c "interface $IFACE ping-check profile default" 2>/dev/null
        ndmc -c "system configuration save" 2>/dev/null
        SUCCESS=1
        exit 0
      fi
      log notice "   IP ок, Telegram нет — ждём..."
    fi
    sleep 2
    i=$((i + 1))
  done
  log warn "   $p — не подошёл"
done

[ "$SUCCESS" -eq 0 ] && log err "Не удалось восстановить туннель"
log warn "$IFACE остаётся down — Fix снова или поднимите интерфейс вручную"
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
# [6] Проверить прокси (через локальный SOCKS5 127.0.0.1)
# ---------------------------------------------------------------------------
check_proxy() {
  print_banner
  find_opera_iface 2>/dev/null || IFACE="Proxy0"
  T2S=$(iface_to_t2s "$IFACE")
  printf '%b\n' "${bold}[6] Проверка прокси через SOCKS5 (127.0.0.1)${reset}"
  echo ""

  detect_installed

  # Определяем адрес локального SOCKS5 из конфига (BIND_ADDR/BIND_PORT)
  _socks_host="127.0.0.1"
  _socks_port="18080"
  if [ -f "$OP_CONF_FILE" ]; then
    _bp=$(sed -n 's/^BIND_PORT="\([^"]*\)".*/\1/p' "$OP_CONF_FILE" | head -1)
    [ -n "$_bp" ] && _socks_port="$_bp"
    _ba=$(sed -n 's/^BIND_ADDR="\([^"]*\)".*/\1/p' "$OP_CONF_FILE" | head -1)
    # 0.0.0.0 — слушает всю систему, для клиента подключаемся на localhost
    if [ -n "$_ba" ] && [ "$_ba" != "0.0.0.0" ]; then
      _socks_host="$_ba"
    fi
  fi
  LOCAL_SOCKS_CHECK="${_socks_host}:${_socks_port}"
  printf "   SOCKS5 proxy    : %b%s%b\n" "$light_blue" "$LOCAL_SOCKS_CHECK" "$reset"

  # Проверка: интерфейс t2S (информативно, без него тоже можно работать через SOCKS)
  _up=0
  if ip link show "$T2S" 2>/dev/null | grep -q "state UP"; then
    _up=1
  elif ifconfig "$T2S" 2>/dev/null | grep -q "UP"; then
    _up=1
  fi
  if [ "$_up" = "1" ]; then
    printf "   Интерфейс %s  : %bUP%b\n" "$T2S" "$green" "$reset"
  else
    printf "   Интерфейс %s  : %bDOWN / отсутствует%b (проверяем напрямую через SOCKS)\n" "$T2S" "$yellow" "$reset"
  fi

  # Жив ли порт SOCKS5 на 127.0.0.1
  _port_ok=0
  if command -v netstat >/dev/null 2>&1; then
    netstat -ltn 2>/dev/null | grep -qE "[:.]${_socks_port}[[:space:]]" && _port_ok=1
  fi
  if [ "$_port_ok" = "0" ] && command -v ss >/dev/null 2>&1; then
    ss -ltn 2>/dev/null | grep -qE "[:.]${_socks_port}[[:space:]]" && _port_ok=1
  fi
  if [ "$_port_ok" = "0" ] && command -v nc >/dev/null 2>&1; then
    nc -z -w 2 "$_socks_host" "$_socks_port" 2>/dev/null && _port_ok=1
  fi
  if [ "$_port_ok" = "1" ]; then
    printf "   Порт %s        : %bслушается%b\n" "$_socks_port" "$green" "$reset"
  elif [ "$SVC_RUNNING" = "1" ]; then
    printf "   Порт %s        : %bне проверен%b (сервис запущен, пробуем запросы)\n" "$_socks_port" "$yellow" "$reset"
  else
    printf "   Порт %s        : %bне слушается%b\n" "$_socks_port" "$red" "$reset"
    echo ""
    echo "⚠ Локальный SOCKS5 ($LOCAL_SOCKS_CHECK) недоступен."
    echo "   Запустите сервис (пункт 5) или выполните Fix (пункт 4)."
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
  printf '%b\n' "${bold}  IP-сервисы (через SOCKS5 $LOCAL_SOCKS_CHECK)${reset}"
  printf '%b\n' "${light_blue}────────────────────────────────────────────────${reset}"
  echo ""

  _ok_count=0

  # --- myip.wtf ---
  printf "  ▶ myip.wtf  ... "
  _out=$(curl --socks5-hostname "$LOCAL_SOCKS_CHECK" -s -m 10 --connect-timeout 6 myip.wtf 2>/dev/null)
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
  _out=$(curl --socks5-hostname "$LOCAL_SOCKS_CHECK" -s -m 10 --connect-timeout 6 2ip.io 2>/dev/null)
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
  _code=$(curl --socks5-hostname "$LOCAL_SOCKS_CHECK" -s -o /dev/null -w "%{http_code}" -m 12 --connect-timeout 7 \
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

  printf '%b\n' "${light_blue}────────────────────────────────────────────────${reset}"
  printf '%b\n' "${bold}  Google (через интерфейс $T2S)${reset}"
  printf '%b\n' "${light_blue}────────────────────────────────────────────────${reset}"
  echo ""

  # --- google.com через t2S-интерфейс ---
  printf "  ▶ google.com ($T2S)  ... "
  _code=$(curl --interface "$T2S" -s -o /dev/null -w "%{http_code}" -m 12 --connect-timeout 7 \
    https://www.google.com/generate_204 2>/dev/null)
  case "$_code" in
    204|200|301|302|303|307|308)
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
  if [ "$_ok_count" -ge 3 ]; then
    printf "  Итог: %bпрокси работает%b  (%s/4 проверок)\n" "$green" "$reset" "$_ok_count"
  elif [ "$_ok_count" -ge 1 ]; then
    printf "  Итог: %bчастично%b  (%s/4) — возможны проблемы\n" "$yellow" "$reset" "$_ok_count"
  else
    printf "  Итог: %bпрокси не отвечает%b  (0/4)\n" "$red" "$reset"
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
    echo "→ Удаление интерфейса Opera (по description) ..."
    if command -v ndmc >/dev/null 2>&1; then
      _rc=$(ndmc -c "show running-config" 2>/dev/null || echo "")
      _del=$(printf '%s\n' "$_rc" | awk '
        /^interface Proxy[0-9]+/ { cur=$2 }
        /description.*(OperaProxy|Opera)/ { print cur; exit }
      ')
      if [ -n "$_del" ]; then
        ndmc -c "no interface $_del" 2>/dev/null && echo "   ✓ no interface $_del" || echo "   ⚠ не удалось удалить $_del"
      else
        # fallback Proxy0
        ndmc -c "no interface Proxy0" 2>/dev/null && echo "   ✓ no interface Proxy0 (fallback)" || echo "   ⚠ интерфейс Opera не найден"
      fi
      ndmc -c "system configuration save" 2>/dev/null && echo "   ✓ Конфигурация сохранена" || echo "   ⚠ Не удалось сохранить конфигурацию"
    else
      echo "   ⚠ ndmc не найден — удалите Proxy вручную"
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
  echo "Текущая версия: $MENU_VERSION"
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
