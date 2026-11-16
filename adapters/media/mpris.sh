#!/bin/sh
# Вкладка "Медиа": что играет, через стандарт MPRIS (D-Bus).
# playerctl в системе нет, поэтому так: busctl --json=short отдаёт честный UTF-8
# JSON (обычный busctl экранирует кириллицу в \NNN, gdbus - GVariant-текст),
# его разбор делает встроенный python (json.loads). Кавычки, $, ; и эмодзи в
# названии трека безопасны: в командные строки и :onclick они не попадают.
#
# usage: mpris.sh <ключ>
#   player        - имя выбранного плеера (Identity), "" если плееров нет
#   status        - playing / paused / stopped / none
#   title         - название трека
#   artist        - исполнитель (первый из списка)
#   album         - альбом
#   art           - локальный путь к обложке (кеш, 200x200) или ""
#   pos           - позиция, секунды
#   len           - длительность, секунды
#   posfmt, lenfmt - то же в виде "1:23" (для подписи у ползунка)
#   json          - всё сразу, одна строка JSON (для defpoll)
#   players       - короткие имена всех плееров через " | " (отладка)
#   next-player   - выбрать следующий плеер (запоминается, пока жив)
#   playpause     - пауза/играть (учитывает CanPause)
#   prev / next   - предыдущий / следующий трек (учитывает CanGo*Previous/Next)
#   seek <сек>    - перемотка на абсолютную позицию (только цифры, учитывает CanSeek)
#
# Выбор плеера: ручной выбор (файл prefer, пишет next-player), иначе играющий,
# иначе последний виденный играющим (файл last), иначе первый по алфавиту.
set -eu

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/eww-island"
mkdir -p "$CACHE"
PREF="$CACHE/media-player.prefer"
LAST="$CACHE/media-player.last"
SEEK="$CACHE/media-seek"

# --- список bus-имён всех плееров (по алфавиту) ---
dests() {
  busctl --user list --no-legend 2>/dev/null \
    | awk '$1 ~ /^org\.mpris\.MediaPlayer2\./ && $1 != "org.mpris.MediaPlayer2" {print $1}' \
    | sort
}

# Короткое имя плеера для показа: хвост bus-имени.
short_of() {
  printf '%s\n' "${1#org.mpris.MediaPlayer2.}"
}

# --- выбор плеера: prefer > играющий > last > первый ---
resolve() {
  LIST=$(dests)
  [ -n "$LIST" ] || return 0
  # 1. Ручной выбор, пока плеер жив.
  if [ -s "$PREF" ]; then
    P=$(cat "$PREF")
    if printf '%s\n' "$LIST" | grep -qx "$P"; then
      printf '%s\n' "$P"
      return 0
    fi
    rm -f "$PREF"
  fi
  # 2. Кто играет.
  for d in $LIST; do
    if [ "$(busctl --user get-property "$d" /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player PlaybackStatus 2>/dev/null || true)" = 's "Playing"' ]; then
      printf '%s\n' "$d"
      return 0
    fi
  done
  # 3. Последний активный, если жив.
  if [ -s "$LAST" ]; then
    P=$(cat "$LAST")
    if printf '%s\n' "$LIST" | grep -qx "$P"; then
      printf '%s\n' "$P"
      return 0
    fi
  fi
  # 4. Первый в списке.
  printf '%s\n' "$LIST" | head -1
}

# --- способности плеера: busctl печатает "b true"/"b false" ---
have() {
  [ "$(busctl --user get-property "$1" /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player "$2" 2>/dev/null || true)" = "b true" ]
}

# --- управление ---
control() {
  D=$(resolve)
  [ -n "$D" ] || exit 0
  IF=org.mpris.MediaPlayer2.Player
  case "$1" in
    playpause)
      have "$D" CanPause || exit 0
      busctl --user call "$D" /org/mpris/MediaPlayer2 $IF PlayPause
      ;;
    next)
      have "$D" CanGoNext || exit 0
      busctl --user call "$D" /org/mpris/MediaPlayer2 $IF Next
      ;;
    prev)
      have "$D" CanGoPrevious || exit 0
      busctl --user call "$D" /org/mpris/MediaPlayer2 $IF Previous
      ;;
  esac
  rm -f "$SEEK"
}

# --- перемотка: только цифры; без CanSeek - игнор ---
seek() {
  case "${1:-}" in
    ''|*[!0-9]*)
      printf '%s\n' "seek: нужны секунды (число)" >&2
      exit 2
      ;;
  esac
  D=$(resolve)
  [ -n "$D" ] || exit 0
  IF=org.mpris.MediaPlayer2.Player
  have "$D" CanSeek || exit 0
  US=$(( ${1:-0} * 1000000 ))
  # Абсолютная перемотка - SetPosition (нужен trackid из метаданных). Он
  # стандартный, но не у всех есть: запасной путь - Seek от текущей позиции.
  TID=$(busctl --user get-property "$D" /org/mpris/MediaPlayer2 $IF Metadata 2>/dev/null \
        | sed -n 's/.*"mpris:trackid" o "\([^"]*\)".*/\1/p' || true)
  if [ -n "$TID" ] && [ "$(printf '%s' "$TID" | cut -c1)" = "/" ]; then
    # Сигнатура одна на все аргументы: ox <путь> <микросекунды>.
    busctl --user call "$D" /org/mpris/MediaPlayer2 $IF SetPosition ox "$TID" "$US" >/dev/null || true
  else
    CUR=$(busctl --user get-property "$D" /org/mpris/MediaPlayer2 $IF Position 2>/dev/null | grep -o '[0-9-]*' | head -1)
    busctl --user call "$D" /org/mpris/MediaPlayer2 $IF Seek x "$(( US - ${CUR:-0} ))" >/dev/null || true
  fi
  # Держим ползунок на том, куда мотнул пользователь, пока опрос не догонит:
  # иначе на 2 с значение откатывается к старой позиции и ползунок дёргается.
  printf '%s %s\n' "$(( $(date +%s) + 2 ))" "$1" > "$SEEK"
}

# Разбор шины и выдача всего JSON одним вызовом python (режим "json").
# Скалярные ключи - то же самое, но одно поле (для терминала).
emit_json() {
  python3 -S - "$CACHE" <<'PY'
import json, subprocess, sys, os, hashlib, time

cache = sys.argv[1]
prefer_f = os.path.join(cache, "media-player.prefer")
last_f = os.path.join(cache, "media-player.last")
seek_f = os.path.join(cache, "media-seek")
artdir = os.path.join(cache, "art")

def bus(*args):
    r = subprocess.run(["busctl", "--user", "--json=short"] + list(args),
                       capture_output=True, text=True, timeout=5)
    if r.returncode != 0:
        raise RuntimeError(r.stderr.strip()[:200])
    return json.loads(r.stdout)

def getall(dest, iface):
    d = bus("call", dest, "/org/mpris/MediaPlayer2",
            "org.freedesktop.DBus.Properties", "GetAll", "s", iface)
    return d["data"][0]

names = bus("call", "org.freedesktop.DBus", "/org/freedesktop/DBus",
            "org.freedesktop.DBus", "ListNames")["data"][0]
dests = sorted(n for n in names
               if n.startswith("org.mpris.MediaPlayer2.") and n != "org.mpris.MediaPlayer2")

prefer = ""
try: prefer = open(prefer_f).read().strip()
except OSError: pass

# Выбор: prefer (если жив) > играющий > last > первый.
chosen = None
if prefer in dests:
    chosen = prefer
if chosen is None:
    for d in dests:
        try:
            if getall(d, "org.mpris.MediaPlayer2.Player").get("PlaybackStatus", {}).get("data") == "Playing":
                chosen = d; break
        except Exception:
            continue
if chosen is None and dests:
    last = ""
    try: last = open(last_f).read().strip()
    except OSError: pass
    chosen = last if last in dests else dests[0]

EMPTY = {"player": "", "status": "none", "title": "", "artist": "", "album": "",
         "art": "", "pos": 0, "len": 0, "posfmt": "0:00", "lenfmt": "0:00",
         "canseek": False, "canprev": False, "cannext": False, "canpause": False,
         "players": []}
if chosen is None:
    for f in (prefer_f, last_f):
        try: os.remove(f)
        except OSError: pass
    print(json.dumps(EMPTY, ensure_ascii=False, separators=(",", ":"))); sys.exit(0)

# Мёртвый ручной выбор не держим: resolve в shell чистит его же, но poll ходит
# только через python.
if prefer and prefer not in dests:
    try: os.remove(prefer_f)
    except OSError: pass

props = getall(chosen, "org.mpris.MediaPlayer2.Player")
ident = short = chosen[len("org.mpris.MediaPlayer2."):]
try:
    root = getall(chosen, "org.mpris.MediaPlayer2")
    ident = root.get("Identity", {}).get("data", short)
except Exception:
    pass

md = props.get("Metadata", {}).get("data", {})
def s(k):
    v = md.get(k, {}).get("data", "")
    return v if isinstance(v, str) else ""
artist = md.get("xesam:artist", {}).get("data", [])
artist = artist[0] if isinstance(artist, list) and artist else ""

us = props.get("Position", {}).get("data", 0) or 0
length = md.get("mpris:length", {}).get("data", 0) or 0
pos, ln = max(0, int(us) // 1000000), max(0, int(length) // 1000000)

# Недавняя ручная перемотка: показываем её, пока опрос не догонит.
try:
    until, target = open(seek_f).read().split()
    if int(until) > time.time():
        pos = int(target)
except Exception:
    pass

# Обложка: file:// берём как есть, http(s) скачиваем один раз (кеш по хэшу),
# всё через subprocess списком аргументов - URL не проходит через shell.
art = ""
url = s("mpris:artUrl")
if url.startswith("file://"):
    src = url[7:]
    if os.path.isfile(src):
        h = hashlib.sha1((url + str(int(os.path.getmtime(src)))).encode()).hexdigest()[:12]
        dst = os.path.join(artdir, "f-" + h + ".png")
        if not os.path.isfile(dst):
            os.makedirs(artdir, exist_ok=True)
            subprocess.run(["magick", src, "-resize", "200x200>", dst], timeout=10)
        art = dst
elif url.startswith(("http://", "https://")):
    os.makedirs(artdir, exist_ok=True)
    dst = os.path.join(artdir, "h-" + hashlib.sha1(url.encode()).hexdigest()[:12] + ".png")
    if os.path.isfile(dst):
        art = dst
    else:
        # Только http(s), никаких перенаправлений в file://; таймаут 5 с.
        r = subprocess.run(["curl", "--proto", "=http,https", "-fsSL", "--max-time", "5",
                            "-o", dst + ".part", url], capture_output=True, timeout=8)
        if r.returncode == 0 and os.path.getsize(dst + ".part") > 0:
            subprocess.run(["magick", dst + ".part", "-resize", "200x200>", dst], timeout=10)
            art = dst
        try: os.remove(dst + ".part")
        except OSError: pass

status = props.get("PlaybackStatus", {}).get("data", "Stopped").lower()
if status not in ("playing", "paused", "stopped"):
    status = "stopped"

# "1:23 / 4:56" - формат для подписи у ползунка.
fmt = lambda t: "%d:%02d" % (t // 60, t % 60)

if props.get("PlaybackStatus", {}).get("data") == "Playing":
    try: open(last_f, "w").write(chosen)
    except OSError: pass

flag = lambda k: props.get(k, {}).get("data") is True
out = {
    "player": ident,
    "status": status,
    "title": s("xesam:title"),
    "artist": artist,
    "album": s("xesam:album"),
    "art": art,
    "pos": pos,
    "len": ln,
    "posfmt": fmt(pos),
    "lenfmt": fmt(ln),
    "canseek": flag("CanSeek"),
    "canprev": flag("CanGoPrevious"),
    "cannext": flag("CanGoNext"),
    "canpause": flag("CanPause"),
    "players": [],
}
# Короткие bus-имена всех плееров (для отладки и переключения); показывается
# всё равно Identity выбранного, лишние GetAll на каждого - дорого.
for d in dests:
    out["players"].append(d[len("org.mpris.MediaPlayer2."):])
print(json.dumps(out, ensure_ascii=False, separators=(",", ":")))
PY
}

case "${1:-}" in
  json)
    emit_json
    ;;
  player|status|title|artist|album|art|pos|len|posfmt|lenfmt)
    # Одиночный ключ - для терминала: тот же JSON, одно поле.
    emit_json | python3 -S -c 'import json,sys; v=json.load(sys.stdin)[sys.argv[1]]; print(v if isinstance(v, str) else str(v).lower() if isinstance(v, bool) else v)' "$1"
    ;;
  players)
    D=$(dests)
    [ -n "$D" ] || exit 0
    OUT=""
    for d in $D; do
      I=$(busctl --user get-property "$d" /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2 Identity 2>/dev/null \
          | sed -n 's/^s "\(.*\)"$/\1/p' || true)
      OUT="$OUT${OUT:+ | }${I:-$(short_of "$d")}"
    done
    printf '%s\n' "$OUT"
    ;;
  next-player)
    LIST=$(dests)
    [ -n "$LIST" ] || exit 0
    CUR=""; [ -s "$PREF" ] && CUR=$(cat "$PREF")
    NXT=""
    SEEN=0
    for d in $LIST; do
      if [ "$SEEN" = 1 ]; then NXT=$d; break; fi
      [ "$d" = "$CUR" ] && SEEN=1
    done
    [ -n "$NXT" ] || NXT=$(printf '%s\n' "$LIST" | head -1)
    printf '%s\n' "$NXT" > "$PREF"
    short_of "$NXT"
    ;;
  playpause|next|prev)
    control "$1"
    ;;
  seek)
    seek "${2:-}"
    ;;
  '')
    printf '%s\n' "usage: mpris.sh <player|status|title|artist|album|art|pos|len|posfmt|lenfmt|json|players|next-player|playpause|prev|next|seek N>" >&2
    exit 2
    ;;
  *)
    printf '%s\n' "mpris.sh: неизвестный ключ '$1'" >&2
    exit 2
    ;;
esac
