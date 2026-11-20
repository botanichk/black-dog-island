#!/bin/sh
# Wi-Fi для выпадающей панели острова.
# Данные - NetworkManager через nmcli (тот же источник, что у Noctalia).
#
# usage: wifi.sh <ключ>
#   state         - подключено / отключено
#   ssid          - имя активной сети
#   signal        - сигнал активной сети, %
#   bars          - полоски сигнала активной сети
#   level         - уровень сигнала словом: excellent/good/ok/weak/none
#   n             - сколько сетей видно
#   list          - JSON-массив сетей для цикла "for" в Eww
#   connect <N>   - подключиться к N-й сети из списка
#   radio         - состояние радио: on / off
#   radio on|off  - включить / выключить радио Wi-Fi (off рвёт соединение)
#   radio-toggle  - переключатель из интерфейса: решает сам, спросить или нет
#   active        - 1, если есть активное подключение, иначе 0
#   disconnect    - отключиться от текущей сети (профиль сохраняется)
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
EWW="$ROOT/build/target/release/eww"
CONF="$ROOT/eww"

CACHE="${BDI_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/bdi}"
mkdir -p "$CACHE"
STAMP="$CACHE/wifi-scan.stamp"
# Снимок списка, который сейчас показан в панели: "номер|use|sig|locked|ssid".
# По нему клик выбирает сеть, поэтому попадает в ту же строку, что видит глаз.
SNAP="$CACHE/wifi-visible.txt"

key=${1:-}

# Обновить переменные панели сразу после действия, не ожидая defpoll.
# Ошибки глушим: адаптер должен работать и без запущенного демона Eww.
refresh_polls() {
  "$EWW" --config "$CONF" poll wf-radio wf-active wf-state wf-ssid \
    wf-signal wf-level wf-list wf-n >/dev/null 2>&1 || true
}

# --- Радио Wi-Fi ---
# Отвечаем раньше остальных запросов к nmcli: это единственный ключ, который
# опрашивается часто (defpoll раз в 3 с), а состояние радио - один вызов.
if [ "$key" = "radio" ]; then
  case "${2:-}" in
    "")
      if nmcli radio wifi 2>/dev/null | grep -q '^enabled'; then
        printf 'on'
      else
        printf 'off'
      fi
      ;;
    on)
      nmcli radio wifi on >/dev/null 2>&1 || true
      refresh_polls
      ;;
    off)
      nmcli radio wifi off >/dev/null 2>&1 || true
      # Плашка вопроса больше не нужна: радио уже выключено.
      "$EWW" --config "$CONF" update wf_confirm=0 >/dev/null 2>&1 || true
      refresh_polls
      ;;
    *)
      printf 'usage: wifi.sh radio [on|off]\n' >&2
      exit 2
      ;;
  esac
  exit 0
fi

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
# Дубли схлопываются: одна точка доступа на SSID (два диапазона одного роутера
# давали две одинаковые строки). Из дублей остаётся самый сильный сигнал,
# активная сеть остаётся первой всегда. Скрытые сети (пустой SSID) не годятся
# для выбора по имени, в список они не попадают.
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
           END{printf "%s", act rest}' \
    | awk -F'|' '
        { ssid = $4
          if (ssid == "") next
          if (!(ssid in idx)) {
            idx[ssid] = ++cnt; order[cnt] = ssid
            us[ssid] = $1; sg[ssid] = $2 + 0; lk[ssid] = $3; next
          }
          # Активную строку не перебиваем, из остальных берём сильнейшую.
          if (us[ssid] != "*" && $2 + 0 > sg[ssid]) {
            sg[ssid] = $2 + 0; lk[ssid] = $3; us[ssid] = $1
          }
        }
        END { for (i = 1; i <= cnt; i++) { s = order[i]
                printf "%s|%d|%s|%s\n", us[s], sg[s], lk[s], s } }'
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
    # "idx" - номер строки в nets(): по нему клик выбирает сеть. Имя сети
    # в командную строку не попадает никогда (кавычки, $ и ; в SSID иначе
    # ломают :onclick и позволяют подстановку команд).
    # Заодно сохраняем снимок "idx|ssid": connect берёт имя из него, поэтому
    # клик всегда попадает в ту сеть, которую пользователь видел, даже если
    # эфир перестроился между опросом списка и нажатием.
    nets | head -12 > "$SNAP"
    awk -F'|' '{print NR-1 "|" $0}' "$SNAP" \
    | while IFS='|' read -r idx use sig locked ssid; do
      esc=$(printf '%s' "$ssid" | sed 's/\\/\\\\/g; s/"/\\"/g')
      printf '{"idx":%s,"ssid":"%s","sig":%s,"bars":"%s","level":"%s","active":%s,"locked":%s},' \
        "$idx" "$esc" "${sig:-0}" "$(bars_of "${sig:-0}")" "$(level_of "${sig:-0}")" \
        "$([ "$use" = "*" ] && echo true || echo false)" \
        "$([ "$locked" = "1" ] && echo true || echo false)"
    done | sed 's/,$//' | sed 's/^/[/; s/$/]/'
    ;;
  connect)
    # Принимает только номер строки из list. Всё остальное - ошибка, а не
    # повод что-то подставлять в командную строку.
    i=${2:-}
    case "$i" in
      ''|*[!0-9]*)
        printf '%s\n' "connect: нужен номер сети из списка" >&2
        exit 2
        ;;
    esac
    # Имя из снимка, сделанного list: то же, что видел пользователь.
    ssid=
    if [ -s "$SNAP" ]; then
      ssid=$(sed -n "$((i + 1))p" "$SNAP" | cut -d'|' -f4)
    fi
    # Снимка нет (например, панель ещё не открывали) - берём живой список.
    [ -n "$ssid" ] || ssid=$(nets | sed -n "$((i + 1))p" | cut -d'|' -f4)
    if [ -z "$ssid" ]; then
      printf '%s\n' "Сеть не найдена" >&2
      exit 1
    fi
    nmcli dev wifi connect "$ssid" 2>&1 | head -3
    ;;
  active)
    # 1 только при реально поднятом соединении (100 connected).
    if [ "$STATE" = "connected" ] && [ -n "$CUR_SSID" ]; then printf '1'; else printf '0'; fi
    ;;
  radio-toggle)
    # Переключатель из шапки вкладки. Если Wi-Fi выключен - просто включаем.
    # Если включён и есть активное соединение - не рвём его молча: показываем
    # в интерфейсе подтверждение (wf_confirm=1), выключение будет вторым кликом.
    if ! nmcli radio wifi 2>/dev/null | grep -q '^enabled'; then
      nmcli radio wifi on >/dev/null 2>&1 || true
      "$EWW" --config "$CONF" update wf_confirm=0 >/dev/null 2>&1 || true
      refresh_polls
    elif [ "$STATE" = "connected" ] && [ -n "$CUR_SSID" ]; then
      # Вопрос задаём на вкладке Wi-Fi и сразу туда переключаем хаб: иначе
      # подтверждение, нажатое из плитки на "Главной", осталось бы невидимым.
      "$EWW" --config "$CONF" update wf_confirm=1 >/dev/null 2>&1 || true
      "$EWW" --config "$CONF" update hub_tab=3 >/dev/null 2>&1 || true
    else
      nmcli radio wifi off >/dev/null 2>&1 || true
      "$EWW" --config "$CONF" update wf_confirm=0 >/dev/null 2>&1 || true
      refresh_polls
    fi
    ;;
  disconnect)
    if [ "$STATE" != "connected" ]; then
      printf '%s\n' "Нет активного подключения" >&2
      exit 1
    fi
    # Профиль остаётся: соединение можно поднять снова из списка сетей.
    nmcli connection down "$CUR_SSID" >/dev/null 2>&1 || nmcli device disconnect "$DEV" >/dev/null 2>&1 || true
    refresh_polls
    ;;
  rescan)
    # Кнопка "Обновить": просим nmcli пересканировать эфир и сразу перечитываем
    # список. Сам rescan асинхронный, поэтому даём ему 1.5 с и обновляем
    # переменные панели принудительно - иначе "for" покажет старые данные.
    (nmcli dev wifi rescan >/dev/null 2>&1 || true) &
    sleep 1.5
    touch "$STAMP" 2>/dev/null || true
    refresh_polls
    ;;
  *)
    printf '%s\n' "—" >&2
    exit 2
    ;;
esac
