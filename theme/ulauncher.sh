#!/bin/sh
# ulauncher.sh - тема Ulauncher в цвета острова.
#
# usage: theme/ulauncher.sh apply        # перекрасить (вызывается из apply.sh)
#        theme/ulauncher.sh restore      # вернуть исходную тему
#        theme/ulauncher.sh status       # показать, что сейчас
#        theme/ulauncher.sh rows <n>     # сколько строк результатов показывать
#
# Почему копия темы, а не правка твоей: тема Ulauncher - чужой набор файлов в
# /usr/share/ulauncher/themes/, правка там затрётся при обновлении пакета.
#
# Почему НЕ перезапуск (в отличие от plank.sh): Ulauncher перечитывает тему по
# SIGHUP - main.py вешает на него reload_config() -> init_theme(), а тот заново
# собирает generated.css и подсовывает его в CssProvider. Проверено: правка
# theme.css + kill -HUP пересобрала generated.css из нашего файла. Окно при
# этом не мигает и не теряет ввод.
#
# Почему наша тема называется как твоя (light/dark/...): SIGHUP перечитывает
# CSS, но НЕ settings.json - Settings в памяти синглтон. Чтобы не менять
# theme-name и не перезапускать демона ради цвета, мы кладём свою тему в
# ~/.config/ulauncher/user-themes/<имя-твоей-темы>/. load_available_themes()
# читает сначала системные, потом пользовательские и перезаписывает по имени,
# поэтому наша копия перекрывает системную. В настройках Ulauncher пункт
# называется как раньше ("Elementary Light"), но внутри наши цвета.
#
# Число строк результатов ("полей") - это show-recent-apps в
# ~/.config/ulauncher/settings.json: Ulauncher показывает столько частых
# приложений при пустом вводе. CSS это не задаёт (строки создаёт Python),
# поэтому rows пишет settings.json и перезапускает демона (~0.6 с).
#
# Зависимости только из системы: sh, python3, pgrep, pkill, setsid, wmctrl.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CSS="$ROOT/eww/colors.scss"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
UL_CONFIG="$CONF_DIR/ulauncher"
USER_THEMES="$UL_CONFIG/user-themes"
SETTINGS="$UL_CONFIG/settings.json"
SYS_THEMES="/usr/share/ulauncher/themes"
STATE_DIR="$CONF_DIR/eww-island"
STATE_FILE="$STATE_DIR/ulauncher-theme"
MARKER=".eww-island"
LOG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/eww-island"
LOG="$LOG_DIR/ulauncher.log"

mkdir -p "$LOG_DIR" 2>/dev/null || true
log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG" 2>/dev/null || true
}

# PID демона. Окно скрыто, поэтому ищем по строке запуска, а не по окну.
ul_pid() {
  pgrep -f '[/]usr/bin/ulauncher' 2>/dev/null | head -1 || true
}

# Перезапуск нужен только когда меняется settings.json (см. rows).
restart_ul() {
  _pid=$(ul_pid)
  if [ -n "$_pid" ]; then
    kill -TERM "$_pid" 2>/dev/null || true
    _i=0
    while [ "$_i" -lt 40 ] && [ -n "$(ul_pid)" ]; do
      sleep 0.05
      _i=$((_i + 1))
    done
    [ -z "$(ul_pid)" ] || { kill -KILL "$_pid" 2>/dev/null || true; sleep 0.1; }
  fi
  setsid -f ulauncher --hide-window >/dev/null 2>&1 || {
    log "ошибка: ulauncher не запустился"
    return 1
  }
  _i=0
  while [ "$_i" -lt 60 ]; do
    [ -n "$(ul_pid)" ] && return 0
    sleep 0.05
    _i=$((_i + 1))
  done
  return 0
}

# Тема, которая выбрана у владельца (её и перекрываем).
current_theme_name() {
  python3 - "$SETTINGS" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    print("light")
    raise SystemExit(0)
print(d.get("theme-name") or "light")
PY
}

# Каталог нашей темы: user-themes/<имя твоей темы>/
our_dir() {
  printf '%s/%s\n' "$USER_THEMES" "$(current_theme_name)"
}

# Убрать нашу копию, если она лежит под другим именем (владелец сменил тему).
clean_stale() {
  keep=$(our_dir)
  [ -d "$USER_THEMES" ] || return 0
  for _d in "$USER_THEMES"/*; do
    [ -d "$_d" ] || continue
    [ -f "$_d/$MARKER" ] || continue
    [ "$_d" = "$keep" ] && continue
    rm -rf "$_d"
    log "убрана наша тема под старым именем: $_d"
  done
}

case "${1:-apply}" in
  apply) ACTION=apply ;;
  restore) ACTION=restore ;;
  status) ACTION=status ;;
  rows)
    ACTION=rows
    ROWS=${2:-}
    case "$ROWS" in
      ''|*[!0-9]*) echo "usage: ulauncher.sh rows <1-20>" >&2; exit 2 ;;
    esac
    [ "$ROWS" -ge 1 ] && [ "$ROWS" -le 20 ] || { echo "rows: 1..20" >&2; exit 2; }
    ;;
  *) echo "usage: ulauncher.sh [apply|restore|status|rows <n>]" >&2; exit 2 ;;
esac

command -v ulauncher >/dev/null 2>&1 || {
  echo "нет ulauncher - нечего красить" >&2
  exit 1
}

# --- rows: сколько строк показывать ---------------------------------------
if [ "$ACTION" = "rows" ]; then
  [ -f "$SETTINGS" ] || { echo "нет $SETTINGS" >&2; exit 1; }
  OLD=$(python3 -c "
import json;print(json.load(open('$SETTINGS',encoding='utf-8')).get('show-recent-apps','0'))" 2>/dev/null || echo 0)
  python3 - "$SETTINGS" "$ROWS" <<'PY'
import json, sys
path, rows = sys.argv[1], sys.argv[2]
d = json.load(open(path, encoding="utf-8"))
d["show-recent-apps"] = rows
json.dump(d, open(path, "w", encoding="utf-8"), indent=4, sort_keys=True)
PY
  if [ "$OLD" = "$ROWS" ]; then
    echo "строк результатов: уже $ROWS"
    exit 0
  fi
  restart_ul || true
  log "строк результатов: $OLD -> $ROWS"
  echo "строк результатов: $ROWS"
  exit 0
fi

OUR=$(our_dir)

if [ "$ACTION" = "status" ]; then
  echo "выбрана тема:   $(current_theme_name)"
  echo "наша копия:     $OUR ($( [ -f "$OUR/$MARKER" ] && echo есть || echo нет ))"
  echo "демон:          $( [ -n "$(ul_pid)" ] && echo "работает (pid $(ul_pid))" || echo не запущен )"
  if [ -f "$OUR/theme.css" ]; then
    echo "рамка:          $(sed -n 's/^@define-color window_border_color \(.*\);/\1/p' "$OUR/theme.css" | head -1)"
    echo "фон:            $(sed -n 's/^@define-color window_bg \(.*\);/\1/p' "$OUR/theme.css" | head -1)"
    echo "активная строка:$(sed -n 's/^@define-color item_box_selected \(.*\);/\1/p' "$OUR/theme.css" | head -1)"
  fi
  echo "строк (settings): $(python3 -c "
import json;print(json.load(open('$SETTINGS',encoding='utf-8')).get('show-recent-apps','?'))" 2>/dev/null || echo '?')"
  exit 0
fi

# --- restore: убрать нашу копию -------------------------------------------
if [ "$ACTION" = "restore" ]; then
  REMOVED=0
  for _d in "$USER_THEMES"/*; do
    [ -d "$_d" ] || continue
    [ -f "$_d/$MARKER" ] || continue
    rm -rf "$_d"
    REMOVED=$((REMOVED + 1))
  done
  rm -f "$STATE_FILE"
  [ "$REMOVED" -eq 0 ] && { echo "нечего возвращать: нашей темы нет" >&2; exit 1; }
  _p=$(ul_pid)
  [ -n "$_p" ] && kill -HUP "$_p" 2>/dev/null || true
  rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}/ulauncher_cache/themes/$(current_theme_name)" 2>/dev/null || true
  log "возврат на системную тему $(current_theme_name)"
  echo "тема Ulauncher: системная $(current_theme_name) (наша копия убрана)"
  exit 0
fi

# --- apply ----------------------------------------------------------------
[ -f "$CSS" ] || { echo "нет $CSS - сначала theme/apply.sh" >&2; exit 1; }

BASE_NAME=$(current_theme_name)
BASE_DIR="$SYS_THEMES/$BASE_NAME"
# Тема могла быть выбрана из user-themes - тогда базы в системе нет, берём light.
[ -f "$BASE_DIR/manifest.json" ] || BASE_DIR="$SYS_THEMES/light"
[ -f "$BASE_DIR/manifest.json" ] || {
  echo "нет базовой темы Ulauncher в $SYS_THEMES" >&2
  exit 1
}

clean_stale
mkdir -p "$OUR"

# Снимок прошлого theme.css ДО копирования базы: иначе сравнивали бы с
# исходным файлом темы, а не с тем, что собрали в прошлый раз (было поймано -
# второй apply не говорил «без изменений»). Файл крошечный, сравнение дешёвое.
PREV="$LOG_DIR/ulauncher-prev.css"
cp "$OUR/theme.css" "$PREV" 2>/dev/null || : > "$PREV"

# Копия базы: манифест и css как есть, цвета перепишем ниже.
cp "$BASE_DIR/manifest.json" "$OUR/manifest.json"
cp "$BASE_DIR"/*.css "$OUR/" 2>/dev/null || true
: > "$OUR/$MARKER"

python3 - "$ROOT" "$OUR" "$BASE_NAME" <<'PY'
import os, re, sys

root, out, base_name = sys.argv[1:4]

# --- цвета острова ---------------------------------------------------------
css = open(os.path.join(root, "eww", "colors.scss"), encoding="utf-8").read()

def role(name):
    m = re.search(r"^\$%s:\s*(#[0-9a-fA-F]{6})" % re.escape(name), css, re.M)
    if not m:
        raise SystemExit("в colors.scss нет $%s" % name)
    return m.group(1)

surface   = role("surface")
surf_c    = role("surface-container")
surf_ch   = role("surface-container-high")
on_surf   = role("on-surface")
on_surf_v = role("on-surface-variant")
primary   = role("primary")
on_prim   = role("on-primary")

# "Активное поле темнее, неактивное светлее" по-разному выглядит в тёмной и
# светлой схеме, поэтому берём не «темнее на N», а роль: неактивная строка
# сливается с фоном ($surface), активная - приподнятая ($surface-container-high).
# В светлой схеме это темнее фона, в тёмной - светлее, и в обоих случаях
# активная строка выделяется. $surface-container оставлен для наведения.

palette = [
    ("bg_color", surface),
    ("window_bg", surface),
    ("window_border_color", primary),      # рамка, как у Plank
    ("prefs_backgroud", surf_c),
    ("selected_bg_color", surf_ch),        # выделение в поле ввода
    ("selected_fg_color", on_surf),
    ("input_color", on_surf),
    ("caret_color", primary),
    ("item_name", on_surf),
    ("item_text", on_surf_v),
    ("item_box_selected", surf_ch),        # активная строка
    ("item_text_selected", on_surf_v),
    ("item_name_selected", on_surf),
    ("item_shortcut_color", on_surf_v),
    ("item_shortcut_shadow", surface),
    ("item_shortcut_color_sel", on_surf),
    ("item_shortcut_shadow_sel", surf_ch),
    ("window_shadow", "rgba(0, 0, 0, 0.45)"),
]

path = os.path.join(out, "theme.css")
text = open(path, encoding="utf-8").read()

# reset.css в light-теме подключается первой строкой - сохраняем её.
imports = [ln for ln in text.splitlines() if ln.strip().startswith("@import")]
body = "\n".join(ln for ln in text.splitlines() if not ln.strip().startswith("@import"))

# Все @define-color заменяем разом: иначе чужие цвета останутся в теле правил.
body = re.sub(r"^@define-color\s+\S+.*$", "", body, flags=re.M)
# После вырезания объявлений остаются пустые строки пачками - ужимаем до одной,
# иначе файл вдвое длиннее нужного и в нём не видно, где чьи правила.
body = re.sub(r"\n{3,}", "\n\n", body).strip()

defs = "\n".join("@define-color %s %s;" % (k, v) for k, v in palette)

extra = """
/**
 * Eww Island: рамка в цвет акцента острова и скруглённые углы.
 * Цвета приходят из eww/colors.scss (тема острова), поэтому Ulauncher
 * перекрашивается вместе с ним - отдельной настройки нет.
 */
.app {
    background-color: @window_bg;
    border: 2px solid @window_border_color;
    border-radius: 16px;
}

/* Внутри рамки не должно быть второго прямоугольника с чужим цветом. */
.input-box {
    background-color: transparent;
}

.item-box {
    border-radius: 10px;
}

/* Активная строка: приподнятая плашка, без боковых линий исходной темы. */
.selected.item-box {
    background-color: @item_box_selected;
    border: none;
    border-radius: 10px;
}

.result-box {
    background-color: transparent;
}
"""

head = "\n".join(imports)
# Порядок важен: сначала тело исходной темы, потом наши правила. В CSS при
# равной специфичности побеждает последнее правило, поэтому наше .app с
# border-radius 16px обязано идти после исходного .app с 4px - иначе
# скругление остаётся чужим (было поймано на первом прогоне).
text = (head + "\n\n" if head else "") + defs + "\n\n" + body + "\n\n" + extra.lstrip() + "\n"
open(path, "w", encoding="utf-8").write(text)
print("тема собрана: %s (база %s)" % (out, base_name))
PY

# --- SIGHUP: перечитать без перезапуска -----------------------------------
mkdir -p "$STATE_DIR"
printf '%s\n' "$BASE_NAME" > "$STATE_FILE"

FRAME=$(sed -n 's/^@define-color window_border_color \(.*\);/\1/p' "$OUR/theme.css" | head -1)

# Ничего не изменилось - не дёргаем перечитывание (как plank.sh: он тоже
# выходит «без изменений»). Проверка нужна, чтобы eww reload / старт острова
# не слали SIGHUP на каждый шаг.
if cmp -s "$OUR/theme.css" "$PREV" && [ -n "$(ul_pid)" ]; then
  log "без изменений: рамка $FRAME"
  echo "тема Ulauncher: без изменений (рамка $FRAME)"
  exit 0
fi

_pid=$(ul_pid)
if [ -n "$_pid" ]; then
  kill -HUP "$_pid" 2>/dev/null || true
  log "тема перечитана по SIGHUP (pid $_pid), рамка $FRAME"
else
  log "демон не запущен - тема применится при следующем старте"
fi

echo "тема Ulauncher: рамка $FRAME (копия $(basename "$OUR") поверх системной)"
