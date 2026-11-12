#!/bin/sh
# Wi-Fi для выпадающей панели острова.
# Данные - NetworkManager через nmcli (тот же источник, что у Noctalia).
#
# usage: wifi.sh <ключ>
#   state        - подключено / отключено
#   ssid         - имя активной сети
#   signal       - сигнал активной сети, %
#   bars         - полоски сигнала активной сети
#   level        - уровень сигнала словом: excellent/good/ok/weak/none
#   n            - сколько сетей видно
#   list         - JSON-массив сетей для цикла "for" в Eww
#   connect <N>  - подключиться к N-й сети из списка
set -eu

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/eww-island"
mkdir -p "$CACHE"
STAMP="$CACHE/wifi-scan.stamp"

key=${1:-}

# --- Устройство и активное подключение ---
DEV=$(nmcli -g GENERAL.DEVICE device status 2>/dev/null | grep -v '^$' | head -1 || true)
[ -n "$DEV" ] || DEV=wlan0

STATE_RAW=$(nmcli -g GENERAL.STATE device show "$DEV" 2>/dev/null || true)
# "100 (connected)" -> "connected"
STATE=$(printf '%s' "$STATE_RAW" | sed -n 's/^[0-9]* *(\(.*\)).*/\1/p')
[ -n "$STATE" ] && [ "$STATE" != "$STATE_RAW" ] || STATE=$STATE_RAW

CUR_SSID=$(nmcli -g GENERAL.CONNECTION device show "$DEV" 2>/dev/null || true)
[ "$CUR_SSID" = "--" ] && CUR_SSID=""

# Формат nmcli: IN-USE:SSID:SIGNAL:SECURITY. nmcli не отдаёт JSON, поэтому
# разбираем по позициям с конца: SECURITY бывает пустым, SSID может содержать
# двоеточия, а SIGNAL - всегда число, поэтому ищем его с конца.
# Каждая сеть превращается в строку "use|sig|locked|ssid".
# Активная сеть переносится наверх - в панели она должна быть первой.
nets() {
  nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY dev wifi list --rescan no 2>/dev/null \
    | sed 's/\\:/\\x01/g' \
    | awk -F: '
        { n = NF; sig = ""
          for (i = n; i >= 3; i--) if ($i ~ /^[0-9]+$/) { sig = $i; break }
          sec = ""
          if (n >= 4 && $(n - 1) ~ /^[0-9]+$/) sec = $n
          else if (n >= 4) sec = $n
          ssid = ""
          for (i = 2; i < n - 1; i++) ssid = ssid (i > 2 ? ":" : "") $i
          locked = (sec != "") ? "1" : "0"
          printf "%s|%s|%s|%s\n", $1, sig, locked, ssid }' \
    | sed 's/\\x01/:/g' \
    | awk -F'|' 'BEGIN{act=""; rest=""}
           {if ($1 == "*") act = act $0 "\n"; else rest = rest $0 "\n"}
           END{printf "%s", act rest}'
}

# Полоски сигнала: четыре ступени, как у nmcli.
bars_of() {
  awk -v s="$1" 'BEGIN{
    if (s >= 76) printf "%s", "\342\226\202\342\226\204\342\226\206\342\226\210"
    else if (s >= 51) printf "%s", "\342\226\202\342\226\204\342\226\206"
    else if (s >= 26) printf "%s", "\342\226\202\342\226\204"
    else printf "%s", "\342\226\201"
  }'
}

# Уровень сигнала словом: пороги как у nmcli (четыре ступени + нет сети).
level_of() {
  awk -v s="${1:-0}" 'BEGIN{
    if (s >= 76) print "excellent";
    else if (s >= 51) print "good";
    else if (s >= 26) print "ok";
    else if (s > 0) print "weak";
    else print "none";
  }'
}

# Раз в минуту обновляем кеш сканирования nmcli в фоне, чтобы данные были свежими,
# но панель открывалась мгновенно (nmcli --rescan no отвечает за ~30 мс).
if [ ! -e "$STAMP" ] || [ $(( $(date +%s) - $(stat -c %Y "$STAMP") )) -gt 60 ]; then
  (nmcli dev wifi rescan >/dev/null 2>&1 || true) &
  touch "$STAMP" 2>/dev/null || true
fi

case "$key" in
  state)
    case "$STATE" in
      connected) printf 'подключено' ;;
      *) printf 'отключено' ;;
    esac
    ;;
  ssid)   printf '%s' "${CUR_SSID:-—}" ;;
  signal)
    nets | awk -F'|' '$1=="*"{print $2; exit}'
    ;;
  bars)
    sig=$(nets | awk -F'|' '$1=="*"{print $2; exit}')
    bars_of "${sig:-0}"
    ;;
  level)
    sig=$(nets | awk -F'|' '$1=="*"{print $2; exit}')
    level_of "${sig:-0}"
    ;;
  n)      nets | wc -l | tr -d ' ' ;;
  list)
    # JSON-массив для цикла "for" в Eww. Показываем 12 сетей: остальные
    # всё равно не помещаются в панель, а список длиннее - шум.
    nets | head -12 | while IFS='|' read -r use sig locked ssid; do
      esc=$(printf '%s' "$ssid" | sed 's/\\/\\\\/g; s/"/\\"/g')
      printf '{"ssid":"%s","sig":%s,"bars":"%s","level":"%s","active":%s,"locked":%s},' \
        "$esc" "${sig:-0}" "$(bars_of "${sig:-0}")" "$(level_of "${sig:-0}")" \
        "$([ "$use" = "*" ] && echo true || echo false)" \
        "$([ "$locked" = "1" ] && echo true || echo false)"
    done | sed 's/,$//' | sed 's/^/[/; s/$/]/'
    ;;
  connect)
    i=${2:-0}
    ssid=$(nets | sed -n "$((i + 1))p" | cut -d'|' -f4)
    if [ -z "$ssid" ]; then
      printf '%s\n' "Сеть не найдена" >&2
      exit 1
    fi
    nmcli dev wifi connect "$ssid" 2>&1 | head -3
    ;;
  *)
    printf '%s\n' "—" >&2
    exit 2
    ;;
esac
