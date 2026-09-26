#!/bin/sh
# Меню управления Opera-Proxy (Keenetic / Entware)
#
# Запуск:
#   sh menu-opera.sh
#   curl -sL https://raw.githubusercontent.com/rndnaame/opera-proxy/main/menu-opera.sh | sh
#
# История версий: см. README.md (раздел «История версий меню»)
#   https://github.com/rndnaame/opera-proxy/blob/main/README.md

#   1.3.11 — убраны мёртвые хвосты: ARCH_REPO, HL_UPD/HL_RST, OP_CONF
#   1.3.12 — [5] API_PROXY: geo через ip-api.com вместо ipinfo.io
MENU_VERSION="1.3.12"

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

if [ -n "$NO_COLOR" ]; then
  green=""; red=""; yellow=""; light_blue=""; bold=""; reset=""
fi

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

# ask: пишет ответ в REPLY (без subshell — один процесс в ps)
ask() {
  prompt="$1"
  default="$2"
  if [ -r /dev/tty ]; then
    printf "%s" "$prompt" > /dev/tty
    read -r REPLY < /dev/tty || REPLY="$default"
  else
    REPLY="$default"
  fi
  [ -z "$REPLY" ] && REPLY="$default"
}

# yes_no: пишет 1|0 в YESNO (без subshell)
yes_no() {
  ask "$1" "$2"
  case "$REPLY" in
    y|Y|yes|YES|д|Д) YESNO=1 ;;
    *) YESNO=0 ;;
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
    aarch64*|arm*) ARCH=aarch64 ;;
    mipsel*)       ARCH=mipsel ;;
    mips*)         ARCH=mips ;;
    *)             ARCH="" ;;
  esac
}

detect_installed() {
  OP_BIN="/opt/sbin/opera-proxy"
  OP_INIT="/opt/etc/init.d/S99opera-proxy"
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

  # Состояние t2sN / IFACE считает show_status (через find_opera_iface)
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

  # Туннель ProxyN / t2sN: отдельно «нет интерфейса» и «опущен (DOWN)»
  find_opera_iface 2>/dev/null || IFACE="Proxy0"
  T2S=$(iface_to_t2s "$IFACE")
  _t2s_exists=0
  _t2s_up=0
  if ip link show "$T2S" >/dev/null 2>&1 || ifconfig "$T2S" >/dev/null 2>&1; then
    _t2s_exists=1
  fi
  if ip link show "$T2S" 2>/dev/null | grep -q "state UP"; then
    _t2s_up=1
  elif ifconfig "$T2S" 2>/dev/null | grep -q "UP"; then
    _t2s_up=1
  fi
  if [ "$_t2s_up" = "1" ]; then
    printf "   Туннель     : %s (%s)  %bUP%b\n" "$T2S" "$IFACE" "$green" "$reset"
  elif [ "$_t2s_exists" = "1" ]; then
    printf "   Туннель     : %s (%s)  %bопущен (DOWN)%b\n" "$T2S" "$IFACE" "$yellow" "$reset"
  else
    printf "   Туннель     : %bинтерфейс не создан%b  (ожидался %s / %s)\n" \
      "$yellow" "$reset" "$T2S" "$IFACE"
  fi

  if [ "$FIX_EXISTS" = "1" ]; then
    printf "   Автопочинка : %bвключена%b\n" "$green" "$reset"
  else
    printf "   Автопочинка : %bнет%b  (п.3 — починить туннель)\n" "$yellow" "$reset"
  fi
  echo ""
}

# ---------------------------------------------------------------------------
# Conf (SNI + DoH + COUNTRY) + умный ProxyX
# ---------------------------------------------------------------------------
OP_CONF_FILE="/opt/etc/opera-proxy.conf"
IFACE_DESC="OperaProxy"
BIND_PORT_DEFAULT="18080"

# Записать conf. Один источник правды — OPERA_CONF_TEMPLATE (ниже по файлу
# подставляется при первом вызове, если ещё не задан — локальный минимум).
write_opera_conf() {
  _force="${1:-}"
  if [ -f "$OP_CONF_FILE" ] && [ "$_force" != "force" ]; then
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
  if [ -n "${OPERA_CONF_TEMPLATE:-}" ]; then
    printf '%s\n' "$OPERA_CONF_TEMPLATE" > "$OP_CONF_FILE"
  else
    # шаблон ещё не объявлен (ранний вызов) — минимальный conf
    cat > "$OP_CONF_FILE" << 'CONFEOF'
COUNTRY="EU"
BIND_ADDR="127.0.0.1"
BIND_PORT="18080"
OBFUSCATE="yes"
FAKE_SNI="2gis.com"
BOOTSTRAP_DNS="https://dns.google/dns-query,https://1.1.1.1/dns-query"
SERVER_SELECT="random"
VERBOSITY="30"
OPTIONS="-socks-mode -country $COUNTRY -bind-address ${BIND_ADDR}:${BIND_PORT} -server-selection $SERVER_SELECT -verbosity $VERBOSITY -bootstrap-dns $BOOTSTRAP_DNS"
if [ "$OBFUSCATE" = "yes" ] && [ -n "$FAKE_SNI" ]; then
  OPTIONS="$OPTIONS -fake-SNI $FAKE_SNI"
fi
CONFEOF
  fi
  if [ -n "$_api_extra" ]; then
    {
      echo ""
      echo "# api-proxy (добавлено Fix)"
      _apival=$(printf '%s' "$_api_extra" | sed 's/^-api-proxy[[:space:]]*//;s#^socks5://##')
      echo "API_PROXY=\"$_apival\""
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

  ask "Выбор [0-2]: " "0"
  sub=$REPLY
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
# [3] Починить туннель (socks5 / api-proxy)
# ---------------------------------------------------------------------------
fix_opera() {
  print_banner
  printf '%b\n' "${bold}[3] Починить туннель${reset}"
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

# curl_get — скачивание URL (для GitHub — зеркала ghfast/gh-proxy).
# ВАЖНО: fix-скрипт пишется в файл отдельным heredoc и запускается cron'ом
# вне контекста menu-opera.sh, поэтому функция продублирована здесь.
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

show_config() {
  [ -f /opt/etc/opera-proxy.conf ] && log notice "   Параметры: $(cat /opt/etc/opera-proxy.conf)"
}

# IFACE по description Opera/OperaProxy → t2sN (сразу, до проверок)
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

# Проверка через локальный SOCKS opera-proxy (без t2sN)
LOCAL_SOCKS="127.0.0.1:$(sed -n 's/^[[:space:]]*BIND_PORT="\{0,1\}\([0-9]\{1,5\}\)"\{0,1\}.*/\1/p' /opt/etc/opera-proxy.conf 2>/dev/null | head -1)"
[ -z "$LOCAL_SOCKS" ] && LOCAL_SOCKS="127.0.0.1:18080"
case "$LOCAL_SOCKS" in *:*) : ;; *) LOCAL_SOCKS="127.0.0.1:18080" ;; esac
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

tunnel_ok() {
  if ! check_ip; then
    log err "✗ IP через $T2S: нет"
    return 1
  fi
  log warn "✓ IP ($T2S): $LAST_IP"
  if ! check_telegram; then
    log err "✗ Telegram через $T2S: нет"
    return 1
  fi
  log warn "✓ Telegram ($T2S): OK"
  return 0
}

socks_ok() {
  if ! check_ip_local; then
    log err "✗ IP через SOCKS $LOCAL_SOCKS: нет"
    return 1
  fi
  log warn "✓ IP (SOCKS): $LAST_IP"
  if ! check_telegram_local; then
    log err "✗ Telegram через SOCKS: нет"
    return 1
  fi
  log warn "✓ Telegram (SOCKS): OK"
  return 0
}

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

# ── Диагностика (не ломаем рабочий SOCKS из‑за DOWN t2s) ──
# 1) t2s OK            → выход
# 2) SOCKS OK, t2s нет → только поднять iface (без смены api-proxy)
# 3) SOCKS мёртв       → полный recovery (подбор socks5)

if tunnel_ok; then
  log warn "✓ Туннель работает (IP + Telegram через $T2S)"
  show_config
  exit 0
fi

if socks_ok; then
  log warn "✓ opera-proxy (SOCKS) работает — api-proxy не трогаем"
  log warn "→ Поднимаем $IFACE ($T2S), без смены socks5..."
  proxy0_up
  sleep 2
  if tunnel_ok; then
    log warn "✓ Туннель восстановлен (только $IFACE up)"
    show_config
    exit 0
  fi
  log err "✗ SOCKS жив, но $T2S после up всё ещё не ходит — полный recovery"
else
  log err "✗ SOCKS $LOCAL_SOCKS не отвечает — нужен подбор api-proxy"
fi

log err "✗ Туннель требует восстановления (подбор socks5)"

# Порядок: down → списки → отбор → local-test → up
proxy0_down

TEMP=/tmp/s5.raw
POOL=/tmp/s5.pool
CACHE="/opt/etc/opera-s5.cache"
rm -f "$TEMP" "$POOL"
: > "$TEMP"

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
    # сохранить conf с актуальным OPTIONS (+ API_PROXY отдельной переменной)
    _api_w=$(printf '%s' "$_extra" | sed 's/^-api-proxy[[:space:]]*//;s#^socks5://##')
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
      [ -n "$_api_w" ] && echo "API_PROXY=\"$_api_w\""
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
# [4] Остановить / Запустить сервис
# ---------------------------------------------------------------------------
# Управление состоянием t2s-интерфейса Opera из пунктов меню (v1.2.3):
# интерфейс ищется по upstream-порту (как в п.[5]), фолбэк — description Opera.
menu_iface_num_by_port() {
  # $1 = порт; печатает N для ProxyN, чей upstream = 127.0.0.1:<порт>
  _p="$1"
  command -v ndmc >/dev/null 2>&1 || return 0
  ndmc -c "show running-config" 2>/dev/null | awk -v p="$_p" '
    /^interface Proxy[0-9]+/ { cur=$2 }
    /proxy upstream 127\.0\.0\.1[ \t]+/ {
      n = $NF
      gsub(/[^0-9]/, "", n)
      if (n == p && cur != "") { sub(/^Proxy/, "", cur); print cur; exit }
    }'
}

menu_t2s_set_state() {
  # $1 = up|down
  _st="$1"
  command -v ndmc >/dev/null 2>&1 || return 0
  _bp=$(conf_get BIND_PORT)
  [ -z "$_bp" ] && _bp="$BIND_PORT_DEFAULT"
  _n=$(menu_iface_num_by_port "$_bp")
  if [ -z "$_n" ]; then
    find_opera_iface 2>/dev/null
    _n=$(echo "$IFACE" | sed -n 's/^Proxy\([0-9]\+\)$/\1/p')
    [ -z "$_n" ] && _n=0
  fi
  ndmc -c "interface Proxy$_n $_st" 2>/dev/null
  ndmc -c "system configuration save" 2>/dev/null
  echo "t2s$_n → $_st"
}

toggle_service() {
  print_banner
  printf '%b\n' "${bold}[4] Управление сервисом opera-proxy${reset}"
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
    yes_no "Остановить сервис? [Y/n]: " "y"
    if [ "$YESNO" = "1" ]; then
      /opt/etc/init.d/S99opera-proxy stop
      killall -9 opera-proxy opera-proxy-monitor 2>/dev/null || true
      # v1.2.3: опускаем t2s-интерфейс Opera (стандартный rc.func-скрипт сам не умеет)
      _t2s_msg=$(menu_t2s_set_state down)
      echo "✅ Сервис остановлен${_t2s_msg:+, $_t2s_msg}"
    else
      echo "Отменено."
    fi
  else
    echo "Сервис сейчас: остановлен"
    echo ""
    yes_no "Запустить сервис? [Y/n]: " "y"
    if [ "$YESNO" = "1" ]; then
      /opt/etc/init.d/S99opera-proxy start
      sleep 2
      if pgrep -f "[o]pera-proxy" >/dev/null 2>&1; then
        # v1.2.3: поднимаем t2s-интерфейс Opera (если init-скрипт стандартный/rc.func)
        _t2s_msg=$(menu_t2s_set_state up)
        echo "✅ Сервис запущен${_t2s_msg:+, $_t2s_msg}"
      else
        echo "⚠ Команда start выполнена, но процесс не обнаружен"
      fi
    else
      echo "Отменено."
    fi
  fi
}

# ---------------------------------------------------------------------------
# [5] Проверить прокси (через локальный SOCKS5 127.0.0.1)
# ---------------------------------------------------------------------------

# Порт, на который настроен upstream интерфейса ProxyN (t2sN) в Keenetic
iface_socks_port() {
  _if="${1:-Proxy0}"
  if ! command -v ndmc >/dev/null 2>&1; then
    echo ""
    return 0
  fi
  ndmc -c "show running-config" 2>/dev/null \
    | awk -v ifn="$_if" '
        $0 ~ "^interface " { cur = ($2 == ifn) ? 1 : 0 }
        cur && /proxy upstream/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+$/) { print $i; exit } }
      '
}

check_proxy_run() {
  find_opera_iface 2>/dev/null || IFACE="Proxy0"
  T2S=$(iface_to_t2s "$IFACE")
  printf '%b\n' "${bold}[5] Проверка прокси${reset}"
  echo ""

  detect_installed

  # Порт SOCKS5 из конфига (BIND_ADDR/BIND_PORT)
  _socks_host="127.0.0.1"
  _cfg_port=""
  if [ -f "$OP_CONF_FILE" ]; then
    _cfg_port=$(sed -n 's/^BIND_PORT="\([^"]*\)".*/\1/p' "$OP_CONF_FILE" | head -1)
    _ba=$(sed -n 's/^BIND_ADDR="\([^"]*\)".*/\1/p' "$OP_CONF_FILE" | head -1)
    # 0.0.0.0 — слушает всю систему, для клиента подключаемся на localhost
    if [ -n "$_ba" ] && [ "$_ba" != "0.0.0.0" ]; then
      _socks_host="$_ba"
    fi
  fi

  # Фактический порт из командной строки запущенного процесса (-bind-address addr:port)
  _proc_port=""
  _pid=$(pgrep -f "[o]pera-proxy" 2>/dev/null | head -1)
  _cmdline=""
  if [ -n "$_pid" ] && [ -r "/proc/$_pid/cmdline" ]; then
    _cmdline=$(tr '\0' ' ' < "/proc/$_pid/cmdline" 2>/dev/null | sed 's/[[:space:]]*$//')
  fi
  if [ -z "$_cmdline" ]; then
    _cmdline=$(ps w 2>/dev/null | grep "[o]pera-proxy" | head -1 | sed 's/^[[:space:]]*[0-9]*[[:space:]]*//' || true)
  fi
  if [ -n "$_cmdline" ]; then
    _proc_port=$(printf '%s' "$_cmdline" | sed -n 's/.*-bind-address[= ][^ :]*:\([0-9][0-9]*\).*/\1/p')
  fi

  # v1.2.14: API_PROXY (-api-proxy) из командной строки запущенного процесса
  _api_proc=""
  if [ -n "$_cmdline" ]; then
    _api_proc=$(printf '%s' "$_cmdline" | sed -n 's/.*-api-proxy[= ]socks5:\/\/\([^ "]*\).*/\1/p')
  fi

  # Порт, указанный в конфиге, если процесс не запущен
  _use_port="$_cfg_port"
  [ -n "$_proc_port" ] && _use_port="$_proc_port"
  [ -z "$_use_port" ] && _use_port="$BIND_PORT_DEFAULT"

  # Порт t2sN-интерфейса (upstream 127.0.0.1:<порт>)
  _t2s_port=$(iface_socks_port "$IFACE")

  LOCAL_SOCKS_CHECK="${_socks_host}:${_use_port}"

  # Проверка: интерфейс t2S (информативно, без него тоже можно работать через SOCKS)
  _up=0
  _t2s_exists=0
  if ip link show "$T2S" >/dev/null 2>&1; then _t2s_exists=1; fi
  if ifconfig "$T2S" >/dev/null 2>&1; then _t2s_exists=1; fi
  if ip link show "$T2S" 2>/dev/null | grep -q "state UP"; then
    _up=1
  elif ifconfig "$T2S" 2>/dev/null | grep -q "UP"; then
    _up=1
  fi

  # Жив ли порт SOCKS5
  _port_ok=0
  if command -v netstat >/dev/null 2>&1; then
    netstat -ltn 2>/dev/null | grep -qE "[:.]${_use_port}[[:space:]]" && _port_ok=1
  fi
  if [ "$_port_ok" = "0" ] && command -v ss >/dev/null 2>&1; then
    ss -ltn 2>/dev/null | grep -qE "[:.]${_use_port}[[:space:]]" && _port_ok=1
  fi
  if [ "$_port_ok" = "0" ] && command -v nc >/dev/null 2>&1; then
    nc -z -w 2 "$_socks_host" "$_use_port" 2>/dev/null && _port_ok=1
  fi

  # Согласованность портов: mismatch только если t2s/конфиг/процесс расходятся
  _port_mismatch=0
  if [ -n "$_t2s_port" ] && [ "$_t2s_port" != "$_use_port" ]; then _port_mismatch=1; fi
  if [ -n "$_cfg_port" ] && [ -n "$_proc_port" ] && [ "$_cfg_port" != "$_proc_port" ]; then
    _port_mismatch=1
  fi

  # --- Шапка (компактно): один SOCKS-порт; детали — только при расхождении ---
  if [ "$SVC_RUNNING" = "1" ]; then
    if [ -n "$_pid" ]; then
      printf "   Сервис   : %bзапущен%b  (pid %s)\n" "$green" "$reset" "$_pid"
    else
      printf "   Сервис   : %bзапущен%b\n" "$green" "$reset"
    fi
  else
    printf "   Сервис   : %bостановлен%b\n" "$yellow" "$reset"
  fi

  if [ "$_port_ok" = "1" ]; then
    printf "   SOCKS    : %s  %b✓ слушается%b\n" "$LOCAL_SOCKS_CHECK" "$green" "$reset"
  elif [ "$SVC_RUNNING" = "1" ]; then
    printf "   SOCKS    : %s  %b? не проверен%b (пробуем запросы)\n" "$LOCAL_SOCKS_CHECK" "$yellow" "$reset"
  else
    printf "   SOCKS    : %s  %b✗ не слушается%b\n" "$LOCAL_SOCKS_CHECK" "$red" "$reset"
  fi

  if [ "$_up" = "1" ]; then
    if [ -n "$_t2s_port" ]; then
      if [ "$_t2s_port" = "$_use_port" ]; then
        printf "   Туннель  : %s %bUP%b  →  127.0.0.1:%s\n" "$T2S" "$green" "$reset" "$_t2s_port"
      else
        printf "   Туннель  : %s %bUP%b  →  порт %s  %b⚠ ≠ SOCKS %s%b\n" \
          "$T2S" "$green" "$reset" "$_t2s_port" "$yellow" "$_use_port" "$reset"
      fi
    else
      printf "   Туннель  : %s %bUP%b\n" "$T2S" "$green" "$reset"
    fi
  else
    printf "   Туннель  : %s %bDOWN%b\n" "$T2S" "$yellow" "$reset"
  fi

  if [ "$_port_mismatch" = "1" ]; then
    printf "   Согласование портов:\n"
    printf "     конфиг   %s\n" "${_cfg_port:-—}"
    printf "     процесс  %s\n" "${_proc_port:-—}"
    printf "     %-8s %s\n" "$T2S" "${_t2s_port:-—}"
  fi

  if [ -n "$_api_proc" ]; then
    printf "   API      : socks5://%s\n" "$_api_proc"
  fi

  if [ "$CHECK_PROXY_VERBOSE" = "1" ] && [ -n "$_cmdline" ]; then
    printf '   Cmdline:\n'
    if command -v awk >/dev/null 2>&1; then
      printf '%s\n' "$_cmdline" | awk '{
        line=""; max=60;
        for (i=1;i<=NF;i++) {
          w=length($i) + (line=="" ? 0 : 1);
          if (length(line)+w > max && line != "") { print "     " line; line=$i; }
          else { line = (line=="" ? $i : line " " $i); }
        }
        if (line != "") print "     " line;
      }'
    else
      printf '%s\n' "$_cmdline" | sed -e 's/\(.\{60\}\) /\1\n/g' -e 's/^/     /'
    fi
  fi
  echo ""

  # Неисправности (порт / DOWN t2s) — чинятся до тестов за один проход
  _fix_applied=0
  _up_iface_applied=0

  if [ "$_port_mismatch" = "1" ] || [ "$_up" != "1" ]; then
    _ndmc_ok=0
    command -v ndmc >/dev/null 2>&1 && _ndmc_ok=1
    _q=""
    if [ "$_port_mismatch" = "1" ] && [ "$_up" != "1" ]; then
      printf '%b⚠ Порт SOCKS (%s) ≠ upstream-порт %s (%s)%b\n' \
        "$yellow" "$_use_port" "$T2S" "$_t2s_port" "$reset"
      printf '%b⚠ Интерфейс %s DOWN%b\n' "$yellow" "$T2S" "$reset"
      _q="   Исправить upstream $IFACE на 127.0.0.1:${_use_port}, поднять туннель ($IFACE up), перезапустить сервис и повторить тест? [Y/n]: "
    elif [ "$_port_mismatch" = "1" ]; then
      printf '%b⚠ Порт SOCKS (%s) ≠ upstream-порт %s (%s)%b\n' \
        "$yellow" "$_use_port" "$T2S" "$_t2s_port" "$reset"
      _q="   Исправить upstream $IFACE на 127.0.0.1:${_use_port}, перезапустить сервис и повторить тест? [Y/n]: "
    else
      printf '%b⚠ Интерфейс %s DOWN — трафик роутера через $IFACE не пойдёт, пока туннель опущен%b\n' \
        "$yellow" "$T2S" "$reset"
      _q="   Поднять туннель ($IFACE up) и повторить проверку? [Y/n]: "
    fi
    if [ "$_ndmc_ok" = "0" ]; then
      echo "   ⚠ ndmc не найден — исправьте вручную:"
      [ "$_port_mismatch" = "1" ] && echo "     interface $IFACE proxy upstream 127.0.0.1 ${_use_port}"
      [ "$_up" != "1" ] && echo "     interface $IFACE up"
    else
      yes_no "$_q" "y"
      if [ "$YESNO" = "1" ]; then
      if [ "$_port_mismatch" = "1" ]; then
        echo "→ ndmc: interface $IFACE proxy upstream 127.0.0.1 ${_use_port} ..."
        ndmc -c "interface $IFACE proxy upstream 127.0.0.1 ${_use_port}" 2>/dev/null || true
      fi
      # v1.2.9: сначала up, затем сохранение конфига и только потом restart сервиса
      _n=$(echo "$IFACE" | sed -n 's/^Proxy\([0-9]\+\)$/\1/p')
      [ -z "$_n" ] && _n=0
      if [ "$_up" != "1" ]; then
        echo "→ ndmc: interface Proxy$_n up ..."
        ndmc -c "interface Proxy$_n up" 2>/dev/null || true
        _up_iface_applied=1
      fi
      ndmc -c "system configuration save" 2>/dev/null || true
      if [ "$_port_mismatch" = "1" ]; then
        echo "→ /opt/etc/init.d/S99opera-proxy restart ..."
        /opt/etc/init.d/S99opera-proxy restart 2>/dev/null \
          || /opt/etc/init.d/"$(ls /opt/etc/init.d/ 2>/dev/null | grep -i opera-proxy | head -1)" restart 2>/dev/null \
          || echo "   ⚠ Не удалось перезапустить сервис"
      fi
      # v1.2.9: ждём фактического поднятия туннеля (до ~15 с) — раньше тесты шли
      # сразу после «up» и давали ложные 0/4 на первом проходе
      if [ "$_up_iface_applied" = "1" ]; then
        printf '→ Ожидание %s UP' "$T2S"
        _w=0
        while [ "$_w" -lt 15 ]; do
          sleep 1
          if ip link show "$T2S" 2>/dev/null | grep -q "state UP"; then break; fi
          ifconfig "$T2S" 2>/dev/null | grep -q "UP" && break
          printf '.'
          _w=$((_w + 1))
        done
        echo ""
      fi
      # ждём, пока сервис после restart снова слушает SOCKS-порт (до ~8 с)
      if [ "$_port_mismatch" = "1" ]; then
        _w=0
        while [ "$_w" -lt 8 ]; do
          _p=0
          if command -v netstat >/dev/null 2>&1; then
            netstat -ltn 2>/dev/null | grep -qE "[:.]${_use_port}[[:space:]]" && _p=1
          elif command -v ss >/dev/null 2>&1; then
            ss -ltn 2>/dev/null | grep -qE "[:.]${_use_port}[[:space:]]" && _p=1
          else
            nc -z -w 2 "$_socks_host" "$_use_port" 2>/dev/null && _p=1
          fi
          [ "$_p" = "1" ] && break
          sleep 1
          _w=$((_w + 1))
        done
      fi
      _fix_applied=1
      echo "→ Повторная проверка..."
      else
        echo "   Пропущено (тест продолжается как есть)."
      fi
    fi
    echo ""
  fi

  if [ "$_port_ok" = "0" ] && [ "$SVC_RUNNING" != "1" ]; then
    printf '%b⚠ Локальный SOCKS5 (%s) недоступен — запустите сервис (п.4) или Fix (п.3)%b\n' \
      "$red" "$LOCAL_SOCKS_CHECK" "$reset"
    echo ""
  fi

  # --- Тесты: компактный вывод, результат в одной строке ---
  _ok_count=0

  # myip.wtf
  printf '  %-18s' "myip.wtf:"
  _out=$(curl --socks5-hostname "$LOCAL_SOCKS_CHECK" -s -m 10 --connect-timeout 6 myip.wtf 2>/dev/null)
  _ip1=$(printf '%s\n' "$_out" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
  _ip2=$(printf '%s\n' "$_out" | grep -oE '([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}' | head -1)
  if [ -n "$_out" ]; then
    _ok_count=$((_ok_count + 1))
    printf '%bOK%b  %s\n' "$green" "$reset" "${_ip1:-${_ip2:-$(printf '%s' "$_out" | head -1 | cut -c1-40)}}"
  else
    printf '%bFAIL%b\n' "$red" "$reset"
  fi

  # 2ip.io
  printf '  %-18s' "2ip.io:"
  _out=$(curl --socks5-hostname "$LOCAL_SOCKS_CHECK" -s -m 10 --connect-timeout 6 2ip.io 2>/dev/null)
  _ip=$(printf '%s\n' "$_out" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
  if [ -n "$_out" ]; then
    _ok_count=$((_ok_count + 1))
    printf '%bOK%b  %s\n' "$green" "$reset" "${_ip:-$(printf '%s' "$_out" | head -1 | cut -c1-40)}"
  else
    printf '%bFAIL%b\n' "$red" "$reset"
  fi

  # web.telegram.org
  printf '  %-18s' "Telegram:"
  _code=$(curl --socks5-hostname "$LOCAL_SOCKS_CHECK" -s -o /dev/null -w "%{http_code}" -m 12 --connect-timeout 7 \
    -L https://web.telegram.org 2>/dev/null)
  case "$_code" in
    200|301|302|303|307|308)
      printf '%bOK%b  (HTTP %s)\n' "$green" "$reset" "$_code"
      _ok_count=$((_ok_count + 1)) ;;
    000|"")
      printf '%bFAIL%b\n' "$red" "$reset" ;;
    *)
      printf '%bHTTP %s%b\n' "$yellow" "$_code" "$reset" ;;
  esac

  # google.com через t2S-интерфейс
  printf '  %-18s' "Google ($T2S):"
  _code=$(curl --interface "$T2S" -s -o /dev/null -w "%{http_code}" -m 12 --connect-timeout 7 \
    https://www.google.com/generate_204 2>/dev/null)
  case "$_code" in
    204|200|301|302|303|307|308)
      printf '%bOK%b  (HTTP %s)\n' "$green" "$reset" "$_code"
      _ok_count=$((_ok_count + 1)) ;;
    000|"")
      printf '%bFAIL%b\n' "$red" "$reset" ;;
    *)
      printf '%bHTTP %s%b\n' "$yellow" "$_code" "$reset" ;;
  esac

  # API_PROXY: socks5h + ip-api.com (IP, countryCode, city)
  if [ -n "$_api_proc" ]; then
    printf '  %-18s' "API_PROXY:"
    _info=$(socks5_ipinfo "$_api_proc")
    if [ -n "$_info" ]; then
      printf '%bOK%b  %s\n' "$green" "$reset" "$_info"
      _ok_count=$((_ok_count + 1))
    elif socks5_alive "$_api_proc"; then
      printf '%bOK%b  (ip-api недоступен, прокси отвечает)\n' "$green" "$reset"
      _ok_count=$((_ok_count + 1))
    else
      printf '%bFAIL%b\n' "$red" "$reset"
    fi
  fi

  # Итоговая сводка
  echo ""
  if [ -n "$_api_proc" ]; then _tests_total=5; else _tests_total=4; fi
  if [ "$_ok_count" -ge $((_tests_total - 1)) ]; then
    printf "  %b✓ Прокси работает%b  (%s/%s)\n" "$green" "$reset" "$_ok_count" "$_tests_total"
  elif [ "$_ok_count" -ge 1 ]; then
    printf "  %b! Частично%b  (%s/%s) — возможны проблемы\n" "$yellow" "$reset" "$_ok_count" "$_tests_total"
  else
    printf "  %b✗ Прокси не отвечает%b  (0/%s)  (Fix — п.3, перезапуск — п.4)\n" "$red" "$reset" "$_tests_total"
    # v1.2.9: если тесты прогнаны ПОСЛЕ применения исправлений и всё равно 0/4 —
    # повторный полный прогон бессмысленен (дублирует вывод). Даём подсказку.
    if [ "${_fix_applied:-0}" = "1" ] || [ "${_up_iface_applied:-0}" = "1" ]; then
      _fix_applied=0; _up_iface_applied=0   # без дублирующего блока «ПОВТОРНАЯ ПРОВЕРКА»
      if [ "$_up" != "1" ]; then
        echo "     Туннель $T2S мог ещё не подняться — обождите ~10 с и повторите п.5."
      else
        echo "     Исправления применены, но тесты не прошли — повторите п.5 позже"
        echo "     или выполните Fix (п.3)."
      fi
    fi
  fi

  echo ""
}

# Точка входа пункта [5] (v1.2.10): ОДИН проход.
# Исправления (порт upstream / up туннеля / restart) применяются ДО тестов,
# затем сразу гоняются тесты — без дублирующего блока «ПОВТОРНАЯ ПРОВЕРКА».
check_proxy() {
  print_banner
  # Компактный вывод (v1.2.6); полный cmdline процесса — по флагу -v: ./menu-opera.sh 6 -v
  CHECK_PROXY_VERBOSE=0
  case "${CHECK_PROXY_ARG:-}" in -v|--verbose|v) CHECK_PROXY_VERBOSE=1 ;; esac
  check_proxy_run
}

# ---------------------------------------------------------------------------
# [6] Настройка конфига (/opt/etc/opera-proxy.conf)
# ---------------------------------------------------------------------------

# Шаблон конфига по умолчанию (параметры редактируются в подменю, п.6)
OPERA_CONF_TEMPLATE='# ─────────────────────────────────────────────────────
#  Конфигурация opera-proxy для Keenetic (SOCKS5)
#  После изменений: /opt/etc/init.d/S*opera-proxy restart
# ─────────────────────────────────────────────────────

# Регион: EU (Европа), AS (Азия), AM (Америка)
COUNTRY="EU"

# 127.0.0.1 — только роутер (Proxy/t2s); 0.0.0.0 — вся LAN
BIND_ADDR="127.0.0.1"
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
OPTIONS="-socks-mode -country $COUNTRY -bind-address ${BIND_ADDR}:${BIND_PORT} -server-selection $SERVER_SELECT -verbosity $VERBOSITY -bootstrap-dns $BOOTSTRAP_DNS"
if [ "$OBFUSCATE" = "yes" ] && [ -n "$FAKE_SNI" ]; then
    OPTIONS="$OPTIONS -fake-SNI $FAKE_SNI"
fi'

# Прочитать значение переменной из conf (без выполнения if/OPTIONS)
conf_get() {
  # $1 = имя переменной; печатает значение (или пусто)
  sed -n "s/^$1=\"\\{0,1\\}\\([^\"]*\\)\"\\{0,1\\}.*/\\1/p" "$OP_CONF_FILE" 2>/dev/null | head -1
}

conf_set() {
  # $1 = имя переменной, $2 = новое значение. Заменяет строку VAR="..." в conf.
  _tmpc="/tmp/opera-conf.$$.${RANDOM:-0}.tmp"
  awk -v k="$1" -v v="$2" '
    BEGIN { done = 0 }
    substr($0, 1, length(k) + 1) == k "=" { print k "=\"" v "\""; done = 1; next }
    { print }
    END { if (!done) print k "=\"" v "\"" }
  ' "$OP_CONF_FILE" > "$_tmpc" 2>/dev/null && mv "$_tmpc" "$OP_CONF_FILE" || rm -f "$_tmpc"
}

# Удалить все упоминания -api-proxy из конфига (строка OPTIONS и legacy-дописка
# Fix'а OPTIONS="$OPTIONS -api-proxy ..."). Используется при отключении API_PROXY,
# чтобы параметр не «возродился» в пересобранном OPTIONS.
strip_api_proxy_from_conf() {
  grep -v '^OPTIONS="\$OPTIONS -api-proxy' "$OP_CONF_FILE" > "/tmp/opera-conf.$$.${RANDOM:-0}.tmp" 2>/dev/null \
    && mv "/tmp/opera-conf.$$.${RANDOM:-0}.tmp" "$OP_CONF_FILE" \
    || rm -f "/tmp/opera-conf.$$.${RANDOM:-0}.tmp"
  sed -i 's/ -api-proxy[[:space:]]*socks5:\/\/[^"[:space:]]*//' "$OP_CONF_FILE" 2>/dev/null
}

# Пересборка OPTIONS из текущих параметров конфига (сохраняя -api-proxy).
# Вызывается автоматически после каждого изменения параметра.
rebuild_options() {
  local r_country r_bindaddr r_bindport r_obf r_sni r_doh r_srvsel r_verb r_opts r_api
  r_country=$(conf_get COUNTRY);      [ -z "$r_country" ] && r_country="EU"
  r_bindaddr=$(conf_get BIND_ADDR);   [ -z "$r_bindaddr" ] && r_bindaddr="0.0.0.0"
  r_bindport=$(conf_get BIND_PORT);   [ -z "$r_bindport" ] && r_bindport="$BIND_PORT_DEFAULT"
  r_obf=$(conf_get OBFUSCATE);        [ -z "$r_obf" ] && r_obf="yes"
  r_sni=$(conf_get FAKE_SNI)
  r_doh=$(conf_get BOOTSTRAP_DNS);    [ -z "$r_doh" ] && r_doh="https://dns.google/dns-query,https://1.1.1.1/dns-query"
  r_srvsel=$(conf_get SERVER_SELECT); [ -z "$r_srvsel" ] && r_srvsel="random"
  r_verb=$(conf_get VERBOSITY);       [ -z "$r_verb" ] && r_verb="30"
  r_opts="-socks-mode -country $r_country -bind-address ${r_bindaddr}:${r_bindport} -server-selection $r_srvsel -verbosity $r_verb -bootstrap-dns $r_doh"
  [ "$r_obf" = "yes" ] && [ -n "$r_sni" ] && r_opts="$r_opts -fake-SNI $r_sni"
  r_api=$(conf_get API_PROXY)
  if [ -n "$r_api" ]; then
    # legacy-дописка Fix'ом: OPTIONS="$OPTIONS -api-proxy ..." в конце конфига —
    # фактический апстрим хранится там, локальная переменная устарела
    _leg=$(grep '^OPTIONS="$OPTIONS -api-proxy' "$OP_CONF_FILE" 2>/dev/null | head -1 | sed 's/.*-api-proxy[[:space:]]*//;s#^socks5://##;s/"*$//')
    [ -n "$_leg" ] && r_api="$_leg"
  else
    # API_PROXY не задан (пусто или удалена при отключении): если -api-proxy
    # остался в старой строке OPTIONS / дописке Fix'а — удаляем их, чтобы
    # параметр не «возродился» при пересборке
    strip_api_proxy_from_conf
  fi
  [ -n "$r_api" ] && r_opts="$r_opts -api-proxy socks5://$r_api"
  conf_set OPTIONS "$r_opts"
}

# Текущий API_PROXY (IP:PORT, без префикса socks5://) из конфига.
# Пустая строка = не задан (в т.ч. после явного отключения).
conf_get_api_proxy() {
  # приоритет 1: дописка Fix'а OPTIONS="$OPTIONS -api-proxy socks5://..."
  _leg=$(grep '^OPTIONS="$OPTIONS -api-proxy' "$OP_CONF_FILE" 2>/dev/null | head -1 | sed 's/.*-api-proxy[[:space:]]*//;s#^socks5://##;s/"*$//')
  if [ -n "$_leg" ]; then printf '%s' "$_leg"; return 0; fi
  # приоритет 2: переменная API_PROXY (если её нет и в OPTIONS нет -api-proxy — пусто)
  _v=$(conf_get API_PROXY)
  if [ -n "$_v" ]; then printf '%s' "$_v"; return 0; fi
  # приоритет 3: -api-proxy внутри основной строки OPTIONS (legacy после Fix)
  case "$(conf_get OPTIONS)" in *'-api-proxy '*)
    _v=$(conf_get OPTIONS | sed 's/.*-api-proxy[[:space:]]*//;s#^socks5://##')
    printf '%s' "$_v"; return 0 ;;
  esac
  printf ''
}

# Записать/удалить API_PROXY + пересобрать OPTIONS. Пустое значение = отключить.
conf_set_api_proxy() {
  # $1 = "IP:PORT" или "" (отключить)
  if [ -n "$1" ]; then
    conf_set API_PROXY "$1"
  else
    _tmpc="/tmp/opera-conf.$$.${RANDOM:-0}.tmp"
    grep -v '^API_PROXY=' "$OP_CONF_FILE" > "$_tmpc" 2>/dev/null && mv "$_tmpc" "$OP_CONF_FILE" || rm -f "$_tmpc"
  fi
  rebuild_options
}

# Валидация "IP:PORT"
# Валидация HOST:PORT для апстрима (IP или localhost; IPv4 и IPv6 в скобках)
valid_ip_port() {
  case "$1" in
    ""|*[[:space:]]*) return 1 ;;
  esac
  # IPv6 в скобках: [::1]:1080 / [fd00::1]:18080
  case "$1" in
    \[*\]:*)
      _ip=${1%%\]:*}; _ip="${_ip#\[}"; _pt=${1##*\]:}
      case "$_ip" in *[!0-9a-fA-F:.]*) return 1 ;; esac
      case "$_pt" in ''|*[!0-9]*) return 1 ;; esac
      [ "$_pt" -ge 1 ] 2>/dev/null && [ "$_pt" -le 65535 ] 2>/dev/null || return 1
      return 0 ;;
  esac
  case "$1" in
    *:*) : ;;
    *) return 1 ;;
  esac
  _ip=${1%:*}; _pt=${1##*:}
  case "$_pt" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$_pt" -ge 1 ] 2>/dev/null && [ "$_pt" -le 65535 ] 2>/dev/null || return 1
  case "$_ip" in
    localhost) return 0 ;;
  esac
  case "$_ip" in
    *[!0-9.]*|"") return 1 ;;
  esac
  _octets=$(printf '%s' "$_ip" | awk -F. '{print NF}')
  [ "$_octets" = "4" ] || return 1
  _IFS=$IFS; IFS=.
  for _o in $_ip; do
    case "$_o" in
      ''|*[!0-9]*) IFS=$_IFS; return 1 ;;
    esac
    [ "$_o" -le 255 ] || { IFS=$_IFS; return 1; }
  done
  IFS=$_IFS
  return 0
}

# Проверка работоспособности socks5-прокси (IP:PORT) через HTTP и HTTPS
socks5_alive() {
  _sp="$1"
  _sc=$(curl -x "socks5h://$_sp" -m 4 --connect-timeout 3 -s -o /dev/null -w "%{http_code}" \
    http://api.ipify.org 2>/dev/null)
  [ "$_sc" = "200" ] && return 0
  _sc=$(curl -x "socks5h://$_sp" -m 5 --connect-timeout 3 -s -o /dev/null -w "%{http_code}" \
    https://api.ipify.org 2>/dev/null)
  [ "$_sc" = "200" ] && return 0
  return 1
}

# Через socks5h: ip-api.com → печатает "IP (CC, City)" или только IP; код 0 = OK
# Пример: 185.195.71.218 (CH, Hünenberg)
socks5_ipinfo() {
  _sp="$1"
  # free API: только HTTP; JSON: query, countryCode, city
  _j=$(curl -x "socks5h://$_sp" -m 8 --connect-timeout 5 -s "http://ip-api.com/json/?fields=status,message,query,countryCode,city" 2>/dev/null)
  [ -z "$_j" ] && _j=$(curl -x "socks5h://$_sp" -m 8 --connect-timeout 5 -s "http://ip-api.com/json/" 2>/dev/null)
  [ -z "$_j" ] && return 1
  # status != success → ошибка API
  echo "$_j" | grep -q '"status"[[:space:]]*:[[:space:]]*"success"' || return 1
  _ip=$(printf '%s' "$_j" | sed -n 's/.*"query"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  _cc=$(printf '%s' "$_j" | sed -n 's/.*"countryCode"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  _city=$(printf '%s' "$_j" | sed -n 's/.*"city"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  if [ -z "$_ip" ]; then
    _ip=$(printf '%s' "$_j" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
  fi
  [ -z "$_ip" ] && return 1
  if [ -n "$_cc" ] && [ -n "$_city" ]; then
    printf '%s (%s, %s)' "$_ip" "$_cc" "$_city"
  elif [ -n "$_cc" ]; then
    printf '%s (%s)' "$_ip" "$_cc"
  else
    printf '%s' "$_ip"
  fi
  return 0
}

# Подбор рабочего socks5 из публичных списков (как в Fix, но упрощённо).
# Аргументы: MAX_TEST (по умолчанию 80), NEED — сколько рабочих найти (по умолчанию 1).
# Пишет найденные "IP:PORT" построчно в /tmp/opera-s5-found
pick_socks5_pool() {
  _maxt="${1:-80}"; _need="${2:-1}"
  _temp=/tmp/s5.raw; _pool=/tmp/s5.pool; _cache="/opt/etc/opera-s5.cache"
  rm -f "$_temp" "$_pool" /tmp/opera-s5-found; : > "$_temp"
  echo "→ Загрузка списков socks5..."
  _got=0
  for _u in \
    "https://raw.githubusercontent.com/monosans/proxy-list/main/proxies/socks5.txt|monosans" \
    "https://raw.githubusercontent.com/proxmint/free-proxy-list/main/proxies/socks5.txt|proxmint" \
    "https://api.proxyscrape.com/v2/?request=displayproxies&protocol=socks5&timeout=3000&country=all|proxyscrape" \
    "https://raw.githubusercontent.com/jetkai/proxy-list/main/online-proxies/txt/proxies-socks5.txt|jetkai" \
    "https://raw.githubusercontent.com/relayglass/free-proxy-list/main/protocol/socks5/socks5.txt|relayglass"
  do
    _url=${_u%|*}; _lbl=${_u##*|}
    if curl_get "$_url" /tmp/s5.src; then
      _n=$(grep -cE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+' /tmp/s5.src 2>/dev/null || echo 0)
      if [ "$_n" -gt 0 ] 2>/dev/null; then
        echo "   + $_lbl: $_n"
        cat /tmp/s5.src >> "$_temp"; _got=1
      fi
    else
      echo "   − $_lbl: недоступен"
    fi
  done
  if [ "$_got" = "0" ]; then
    for _u in \
      "https://raw.githubusercontent.com/TheSpeedX/PROXY-List/master/socks5.txt|TheSpeedX" \
      "https://raw.githubusercontent.com/hookzof/socks5_list/master/proxy.txt|hookzof"
    do
      _url=${_u%|*}; _lbl=${_u##*|}
      curl_get "$_url" /tmp/s5.src && { cat /tmp/s5.src >> "$_temp"; _got=1; echo "   + $_lbl (запасной)"; }
    done
  fi
  sed -E 's/\r//g; s|^socks5?h?://||; s/[[:space:]]+//g; s/#.*//' "$_temp" 2>/dev/null \
    | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}:[0-9]+' | sort -u > /tmp/s5.norm
  _nn=$(wc -l < /tmp/s5.norm 2>/dev/null | tr -d ' ')
  if [ -n "$_nn" ] && [ "$_nn" -ge 5 ]; then
    mkdir -p "$(dirname "$_cache")" 2>/dev/null || true
    cp /tmp/s5.norm "$_cache" 2>/dev/null || true
  elif [ -s "$_cache" ]; then
    echo "⚠ Источники недоступны — берём кэш $_cache"
    cp "$_cache" /tmp/s5.norm
    _nn=$(wc -l < /tmp/s5.norm 2>/dev/null | tr -d ' ')
  fi
  if [ -z "$_nn" ] || [ "$_nn" -lt 3 ]; then
    echo "❌ Нет списка socks5 (сеть/GitHub недоступны, кэш пуст)"
    return 1
  fi
  awk 'BEGIN{srand()} {print rand() "\t" $0}' /tmp/s5.norm 2>/dev/null \
    | sort -n | cut -f2- > "$_pool"
  echo "→ Пул: ${_nn} адресов. Перебор до ${_maxt} проверок (нужно ${_need} рабочих)..."
  _tested=0; _found=0
  while IFS= read -r _p && [ "$_found" -lt "$_need" ] && [ "$_tested" -lt "$_maxt" ]; do
    [ -z "$_p" ] && continue
    _tested=$((_tested + 1))
    [ $((_tested % 10)) -eq 0 ] && echo "   ... проверено ${_tested}, найдено ${_found}"
    if socks5_alive "$_p"; then
      _found=$((_found + 1))
      echo "   ✓ кандидат #${_found}: $_p (проверено ${_tested})"
      echo "$_p" >> /tmp/opera-s5-found
    fi
  done < "$_pool"
  rm -f "$_temp" "$_pool" /tmp/s5.norm /tmp/s5.src
  if [ "$_found" -lt 1 ]; then
    echo "❌ Рабочих socks5 не найдено (проверено ${_tested})"
    return 1
  fi
  echo "→ Найдено ${_found} за ${_tested} проверок"
  return 0
}


config_menu() {
  print_banner
  printf '%b\n' "${bold}[6] Настройка конфига${reset}"
  echo ""

  if [ ! -f "$OP_CONF_FILE" ]; then
    printf "⚠ Конфиг %b не найден.\n" "$OP_CONF_FILE"
    yes_no "Создать конфиг по умолчанию? [Y/n]: " "y"
    if [ "$YESNO" = "1" ]; then
      printf '%s\n' "$OPERA_CONF_TEMPLATE" > "$OP_CONF_FILE" \
        && printf '%b✓ Создан: %s%b\n' "$green" "$OP_CONF_FILE" "$reset" \
        || { printf '%b❌ Не удалось записать %s%b\n' "$red" "$OP_CONF_FILE" "$reset"; return 1; }
    else
      return 0
    fi
  fi

  while true; do
    print_banner
    printf '%b\n' "${bold}[6] Настройка конфига${reset}  ${light_blue}$OP_CONF_FILE${reset}"
    echo ""

    # Текущие значения (с дефолтами, если чего-то нет в conf)
    _country=$(conf_get COUNTRY);          [ -z "$_country" ] && _country="EU"
    _bindaddr=$(conf_get BIND_ADDR);       [ -z "$_bindaddr" ] && _bindaddr="0.0.0.0"
    _bindport=$(conf_get BIND_PORT);       [ -z "$_bindport" ] && _bindport="$BIND_PORT_DEFAULT"
    _obf=$(conf_get OBFUSCATE);            [ -z "$_obf" ] && _obf="yes"
    _sni=$(conf_get FAKE_SNI);             [ -z "$_sni" ] && _sni="2gis.com"
    _doh=$(conf_get BOOTSTRAP_DNS);        [ -z "$_doh" ] && _doh="https://dns.google/dns-query,https://1.1.1.1/dns-query"
    _srvsel=$(conf_get SERVER_SELECT);     [ -z "$_srvsel" ] && _srvsel="random"
    _verb=$(conf_get VERBOSITY);           [ -z "$_verb" ] && _verb="30"

    printf '%b\n' "${light_blue}────────── Текущий конфиг ──────────${reset}"
    printf "  %-14s: %b%s%b   (EU | AS | AM)\n" "COUNTRY" "$bold" "$_country" "$reset"
    printf "  %-14s: %b%s%b\n" "BIND_ADDR" "$bold" "$_bindaddr" "$reset"
    printf "  %-14s: %b%s%b\n" "BIND_PORT" "$bold" "$_bindport" "$reset"
    printf "  %-14s: %b%s%b   (yes | no)\n" "OBFUSCATE" "$bold" "$_obf" "$reset"
    printf "  %-14s: %b%s%b\n" "FAKE_SNI" "$bold" "$_sni" "$reset"
    printf "  %-14s: %b%s%b\n" "BOOTSTRAP_DNS" "$bold" "$_doh" "$reset"
    printf "  %-14s: %b%s%b   (random | fastest)\n" "SERVER_SELECT" "$bold" "$_srvsel" "$reset"
    printf "  %-14s: %b%s%b   (10|20|30|40|50|60)\n" "VERBOSITY" "$bold" "$_verb" "$reset"
    _api=$(conf_get_api_proxy)
    if [ -n "$_api" ]; then
      printf "  %-14s: %bsocks5://%s%b\n" "API_PROXY" "$yellow" "$_api" "$reset"
    else
      printf "  %-14s: %b(не задан — прямое подключение)%b\n" "API_PROXY" "$light_blue" "$reset"
    fi
    echo ""
    printf '%b\n' "${light_blue}──────────────────────────────────────${reset}"
    echo ""
    echo "  [1] Изменить COUNTRY (регион)"
    echo "  [2] Изменить BIND_ADDR (адрес)"
    echo "  [3] Изменить BIND_PORT (порт)"
    echo "  [4] Изменить OBFUSCATE + FAKE_SNI"
    echo "  [5] Изменить BOOTSTRAP_DNS"
    echo "  [6] Изменить SERVER_SELECT"
    echo "  [7] Изменить VERBOSITY"
    echo "  [8] Изменить API_PROXY (socks5-апстрим)"
    echo "  [l] Показать конфиг целиком"
    echo "  [s] Сохранить + перезапустить сервис"
    echo "  [x] Сбросить к конфигу по умолчанию"
    echo "  [0] Выход из настройки"
    echo ""
    printf '%b\n' "${light_blue}OPTIONS пересобирается автоматически при каждом изменении${reset}"
    echo ""

ask "Выбор [1-8 / l / s / x / 0]: " "0"
_cc=$REPLY
    case "$_cc" in
      1)
        echo ""
        echo "Выберите регион (COUNTRY):"
        echo "  [1] EU (Европа)"
        echo "  [2] AS (Азия)"
        echo "  [3] AM (Америка)"
        echo "  [0] Отмена"
        ask "Ваш выбор [текущий: $_country]: " ""
        _v=$REPLY
        case "$_v" in
          1|EU|eu|Европа) _vu="EU" ;;
          2|AS|as|Азия)   _vu="AS" ;;
          3|AM|am|Америка) _vu="AM" ;;
          0) printf '   Отменено.\n'; sleep 1; continue ;;
          *) printf '%b⚠ Неверный выбор: %s (нужно 1, 2 или 3)%b\n' "$red" "$_v" "$reset"; sleep 1; continue ;;
        esac
        conf_set COUNTRY "$_vu"; rebuild_options
        printf '%b✓ COUNTRY = %s (%s)%b\n' "$green" "$_vu" "$(case $_vu in EU) echo Европа;; AS) echo Азия;; AM) echo Америка;; esac)" "$reset"
        sleep 1
        ;;
      2)
        ask "BIND_ADDR [$_bindaddr] (127.0.0.1 — только роутер, 0.0.0.0 — вся сеть): " "$_bindaddr"
        _v=$REPLY
        case "$_v" in
          *[!0-9.]*|"") printf '%b⚠ Похоже, это не IPv4-адрес%b\n' "$red" "$reset" ;;
          *) conf_set BIND_ADDR "$_v"; rebuild_options; printf '%b✓ BIND_ADDR = %s%b\n' "$green" "$_v" "$reset" ;;
        esac
        sleep 1
        ;;
      3)
        ask "BIND_PORT [$_bindport]: " "$_bindport"
        _v=$REPLY
        case "$_v" in
          ''|*[!0-9]*) printf '%b⚠ Порт должен быть числом%b\n' "$red" "$reset" ;;
          *) if [ "$_v" -ge 1 ] && [ "$_v" -le 65535 ] 2>/dev/null; then
               conf_set BIND_PORT "$_v"; rebuild_options; printf '%b✓ BIND_PORT = %s%b\n' "$green" "$_v" "$reset"
               # Синхронизация с интерфейсом Opera (t2sN): проверить upstream-порт и предложить исправить
               find_opera_iface 2>/dev/null || IFACE="Proxy0"
               _t2s3=$(iface_to_t2s "$IFACE")
               _t2sport=$(iface_socks_port "$IFACE")
               if [ "$_t2sport" != "$_v" ]; then
                 echo ""
                 printf '%b⚠ Интерфейс %s (%s) сейчас настроен на 127.0.0.1:%s, а прокси будет слушать :%s%b\n' \
                   "$yellow" "$IFACE" "$_t2s3" "${_t2sport:-—}" "$_v" "$reset"
                 yes_no "   Исправить upstream $IFACE на 127.0.0.1:${_v} и перезапустить сервис? [y/N]: " "y"
    if [ "$YESNO" = "1" ]; then
                   if command -v ndmc >/dev/null 2>&1; then
                     echo "→ ndmc: interface $IFACE proxy upstream 127.0.0.1 ${_v} ..."
                     ndmc -c "interface $IFACE proxy upstream 127.0.0.1 ${_v}" 2>/dev/null || true
                     ndmc -c "system configuration save" 2>/dev/null || true
                     printf '%b   ✓ upstream %s → 127.0.0.1:%s%b\n' "$green" "$_t2s3" "$_v" "$reset"
                   else
                     echo "   ⚠ ndmc не найден — исправьте вручную: interface $IFACE proxy upstream 127.0.0.1 ${_v}"
                   fi
                   if [ -x "/opt/etc/init.d/S99opera-proxy" ]; then
                     echo "→ /opt/etc/init.d/S99opera-proxy restart ..."
                     /opt/etc/init.d/S99opera-proxy restart 2>/dev/null || true
                     printf '%b✓ Сервис перезапущен. Проверить можно в пункте [5].%b\n' "$green" "$reset"
                   else
                     printf '%b⚠ S99opera-proxy не найден — изменения сохранены, но сервис не перезапущен.%b\n' "$yellow" "$reset"
                   fi
                 else
                   echo "   Пропущено. Не забудьте перенастроить upstream $_t2s3 вручную и перезапустить сервис ([s])."
                 fi
               else
                 printf '   ✓ Порт интерфейса %s (%s) уже совпадает: 127.0.0.1:%s\n' "$IFACE" "$_t2s3" "$_v"
               fi
             else printf '%b⚠ Порт вне диапазона 1-65535%b\n' "$red" "$reset"; fi ;;
        esac
        sleep 2
        ;;
      4)
        ask "OBFUSCATE yes/no [$_obf]: " "$_obf"
        _v=$REPLY
        case "$_v" in
          y|Y|yes|YES|д|Д) conf_set OBFUSCATE "yes"; printf '%b✓ OBFUSCATE = yes%b\n' "$green" "$reset" ;;
          n|N|no|NO|нет)   conf_set OBFUSCATE "no";  printf '%b✓ OBFUSCATE = no%b\n' "$green" "$reset" ;;
          *) printf '%b⚠ Нужно yes или no%b\n' "$red" "$reset" ;;
        esac
        ask "FAKE_SNI [$_sni]: " "$_sni"
        _v=$REPLY
        if [ -n "$_v" ]; then
          conf_set FAKE_SNI "$_v"; printf '%b✓ FAKE_SNI = %s%b\n' "$green" "$_v" "$reset"
        fi
        rebuild_options
        sleep 1
        ;;
      5)
        ask "BOOTSTRAP_DNS [$_doh]: " "$_doh"
        _v=$REPLY
        case "$_v" in
          https://*) conf_set BOOTSTRAP_DNS "$_v"; rebuild_options; printf '%b✓ BOOTSTRAP_DNS обновлён%b\n' "$green" "$reset" ;;
          *) printf '%b⚠ Значение должно начинаться с https://%b\n' "$red" "$reset" ;;
        esac
        sleep 1
        ;;
      6)
        ask "SERVER_SELECT random/fastest [$_srvsel]: " "$_srvsel"
        _v=$REPLY
        case "$_v" in
          random|fastest) conf_set SERVER_SELECT "$_v"; rebuild_options; printf '%b✓ SERVER_SELECT = %s%b\n' "$green" "$_v" "$reset" ;;
          *) printf '%b⚠ Нужно random или fastest%b\n' "$red" "$reset" ;;
        esac
        sleep 1
        ;;
      7)
        echo ""
        echo "Выберите уровень логирования (VERBOSITY):"
        echo "  [1] 10 — debug     (подробная отладка)"
        echo "  [2] 20 — info      (информационный; по умолчанию в opera-proxy)"
        echo "  [3] 30 — warn      (предупреждения и выше)"
        echo "  [4] 40 — error     (только ошибки)"
        echo "  [5] 50 — critical  (только критические)"
        echo "  [6] 60 — silent    (полное отсутствие вывода)"
        echo "  [0] Отмена"
        ask "Ваш выбор [текущий: $_verb]: " ""
        _v=$REPLY
        case "$_v" in
          1|10) _vu="10" ;;
          2|20) _vu="20" ;;
          3|30) _vu="30" ;;
          4|40) _vu="40" ;;
          5|50) _vu="50" ;;
          6|60) _vu="60" ;;
          0) printf '   Отменено.\n'; sleep 1; continue ;;
          *) printf '%b⚠ Неверный выбор: %s (нужно 1-6)%b\n' "$red" "$_v" "$reset"; sleep 1; continue ;;
        esac
        conf_set VERBOSITY "$_vu"; rebuild_options
        printf '%b✓ VERBOSITY = %s (%s)%b\n' "$green" "$_vu" "$(case $_vu in 10) echo debug;; 20) echo info;; 30) echo warn;; 40) echo error;; 50) echo critical;; 60) echo silent;; esac)" "$reset"
        sleep 1
        ;;
      8)
        echo ""
        printf '%b\n' "${bold}Изменить API_PROXY (socks5-апстрим для opera-proxy)${reset}"
        if [ -n "$_api" ]; then
          echo "   Текущее значение: socks5://${_api}"
        else
          echo "   Текущее значение: (не задан — opera-proxy ходит напрямую)"
        fi
        echo ""
        echo "Выберите действие:"
        echo "  [1] Задать вручную (IP:PORT)"
        echo "  [2] Запустить подбор рабочего socks5 из публичных списков"
        echo "  [3] Отключить API_PROXY"
        echo "  [0] Отмена"
        ask "Ваш выбор: " ""
        _v=$REPLY
        case "$_v" in
          1)
            ask "   IP:PORT нового апстрима [текущий: ${_api:-без изменений}]: " ""
            _p=$REPLY
            # допускаем ввод с префиксом socks5://
            _p=$(printf '%s' "$_p" | sed 's#^socks5://##;s/^[[:space:]]*//;s/[[:space:]]*$//')
            if [ -z "$_p" ]; then
              echo "   Отменено (пустой ввод)."
            elif ! valid_ip_port "$_p"; then
              printf '%b⚠ Неверный формат. Пример: 72.195.34.59:4145 или локальный 127.0.0.1:11001%b\n' "$red" "$reset"
            else
              echo "→ Проверка socks5://$_p ..."
              if socks5_alive "$_p"; then
                conf_set_api_proxy "$_p"
                printf '%b✓ API_PROXY = socks5://%s (прокси отвечает, OPTIONS пересобран)%b\n' "$green" "$_p" "$reset"
              else
                printf '%b⚠ Прокси %s не отвечает (HTTP и HTTPS через него недоступны).%b\n' "$yellow" "$_p" "$reset"
                yes_no "   Всё равно сохранить? [y/N]: " "n"
    if [ "$YESNO" = "1" ]; then
                  conf_set_api_proxy "$_p"
                  printf '%b✓ API_PROXY = socks5://%s (сохранено без проверки)%b\n' "$green" "$_p" "$reset"
                else
                  echo "   Отменено."
                fi
              fi
            fi
            ;;
          2)
            echo "   Подбор может занять несколько минут (скачивание списков + перебор)."
            yes_no "   Продолжить? [Y/n]: " "y"
    if [ "$YESNO" = "1" ]; then
              if pick_socks5_pool 80 1; then
                _pick=$(head -1 /tmp/opera-s5-found 2>/dev/null)
                if [ -n "$_pick" ]; then
                  printf '%b   ✓ Найден рабочий: socks5://%s%b\n' "$green" "$_pick" "$reset"
                  yes_no "   Применить (записать в конфиг и перезапустить сервис)? [Y/n]: " "y"
                  if [ "$YESNO" = "1" ]; then
                    conf_set_api_proxy "$_pick"
                    printf '%b✓ API_PROXY = socks5://%s (OPTIONS пересобран)%b\n' "$green" "$_pick" "$reset"
                    if [ -x "/opt/etc/init.d/S99opera-proxy" ]; then
                      echo "→ /opt/etc/init.d/S99opera-proxy restart ..."
                      /opt/etc/init.d/S99opera-proxy restart
                      printf '%b✓ Сервис перезапущен. Проверить можно в пункте [5].%b\n' "$green" "$reset"
                    fi
                  else
                    echo "   Пропущено. Можно применить позже через [s]."
                  fi
                fi
              else
                printf '%b⚠ Подбор не дал результата. Можно задать адрес вручную ([1]) или выполнить Fix — п.[3].%b\n' "$yellow" "$reset"
              fi
              rm -f /tmp/opera-s5-found
            fi
            ;;
          3)
            if [ -z "$_api" ]; then
              echo "   API_PROXY и так не задан."
            else
              yes_no "   Отключить API_PROXY (удалить -api-proxy из OPTIONS)? [y/N]: " "n"
              if [ "$YESNO" = "1" ]; then
                conf_set_api_proxy ""
                printf '%b✓ API_PROXY отключён (OPTIONS пересобран). Перезапустите сервис: [s] или п.[4].%b\n' "$green" "$reset"
              fi
            fi
            ;;
          0)
            echo "   Отменено."
            ;;
          *)
            printf '%b⚠ Неверный выбор: %s (нужно 1-3 или 0)%b\n' "$red" "$_v" "$reset"
            ;;
        esac
        sleep 2
        ;;
      l|L)
        echo ""
        printf '%b\n' "${light_blue}───── $OP_CONF_FILE ─────${reset}"
        cat "$OP_CONF_FILE" 2>/dev/null | sed 's/^/  /'
        printf '%b\n' "${light_blue}──────────────────────────${reset}"
        ask "Нажмите Enter для возврата... " ""
        ;;
      s|S)
        # Изменения уже сохранены на лету через conf_set; OPTIONS пересобран автоматически.
        rebuild_options
        if [ -x "/opt/etc/init.d/S99opera-proxy" ]; then
          echo "→ /opt/etc/init.d/S99opera-proxy restart ..."
          /opt/etc/init.d/S99opera-proxy restart
          printf '%b✓ Сервис перезапущен. Проверить можно в пункте [5].%b\n' "$green" "$reset"
        else
          printf '%b⚠ /opt/etc/init.d/S99opera-proxy не найден — изменения сохранены, но сервис не перезапущен.%b\n' "$yellow" "$reset"
        fi
        sleep 2
        ;;
      x|X)
        yes_no "Сбросить конфиг к значениям по умолчанию? [y/N]: " "n"
    if [ "$YESNO" = "1" ]; then
          cp "$OP_CONF_FILE" "$OP_CONF_FILE.bak.$(date +%s)" 2>/dev/null
          printf '%s\n' "$OPERA_CONF_TEMPLATE" > "$OP_CONF_FILE" \
            && printf '%b✓ Конфиг сброшен (backup сохранён рядом).%b\n' "$green" "$reset" \
            || printf '%b❌ Не удалось записать конфиг%b\n' "$red" "$reset"
        fi
        sleep 1
        ;;
      0|q|Q|"")
        echo "Выход из настройки конфига."
        return 0
        ;;
      *)
        printf '%bНеверный выбор.%b\n' "$red" "$reset"
        sleep 1
        ;;
    esac
  done
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
    yes_no "Удалить opera-proxy? [y/N]: " "n"
    if [ "$YESNO" != "1" ]; then
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
    yes_no "Удалить репозиторий sw.ext.io? [y/N]: " "n"
    if [ "$YESNO" = "1" ]; then
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
    yes_no "Удалить fix-скрипт и cron-задачу? [y/N]: " "n"
    if [ "$YESNO" = "1" ]; then
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
    yes_no "Перезапустить меню сейчас? [Y/n]: " "y"
    if [ "$YESNO" = "1" ]; then
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
    echo "  [3]  Починить туннель"
    echo "  [4]  Остановить / Запустить сервис"
    echo "  [5]  Проверить прокси"
    echo "  [6]  Настройка конфига"
    echo "  [88] Удалить"
    echo "  [99] Обновить скрипт"
    echo "  [0]  Выход"
    echo ""

    ask "Выбор [0-6 / 88 / 99], Enter = выход: " "0"
    choice=$REPLY
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
        fix_opera
        ask "Нажмите Enter для возврата в меню... " ""
        ;;
      4)
        toggle_service
        ask "Нажмите Enter для возврата в меню... " ""
        ;;
      5)
        check_proxy
        ask "Нажмите Enter для возврата в меню... " ""
        ;;
      6)
        config_menu
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
  # Аргументы: ./menu-opera.sh [5 [-v]] — сразу запустить проверку прокси; -v = с полным cmdline
  for _a in "$@"; do
    case "$_a" in
      5) RUN_ITEM_5=1 ;;
      -v|--verbose|v) CHECK_PROXY_ARG="$_a" ;;
    esac
  done
  # Если stdin — труба (curl|sh), перенаправляем на /dev/tty для меню
  if [ -r /dev/tty ]; then
    exec </dev/tty >/dev/tty 2>/dev/tty
  fi
  if [ "${RUN_ITEM_5:-0}" = "1" ]; then
    check_proxy
    ask "Нажмите Enter для возврата в меню... " ""
  fi
  run_menu
}

main "$@"
