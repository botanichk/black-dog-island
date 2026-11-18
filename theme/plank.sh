#!/bin/sh
# plank.sh - рамка Plank в цвет акцента острова ($primary).
#
# usage: theme/plank.sh apply     # подтянуть рамку (вызывается из apply.sh)
#        theme/plank.sh restore   # вернуть исходную тему Plank
#        theme/plank.sh status    # показать, что сейчас
#
# Почему копия темы, а не правка твоей: тема Plank - это файл dock.theme из
# чужого набора (Tokyonight-Storm-B и т.п.), и правка в нём затрётся при
# любом обновлении набора. Поэтому рядом кладётся своя тема EwwIsland:
# полная копия исходной, в которой изменена ОДНА строка - OuterStrokeColor.
# Всё остальное (заливка, скругления, отступы, толщина линии) остаётся как
# в исходной теме.
#
# Почему перезапуск Plank: он не перечитывает dock.theme на лету.
# Проверено: смена темы через dconf при живом процессе не меняет ни одного
# пикселя рамки, а после pkill -x plank + запуск - рамка появляется
# (оранжевая Mocha: 4183 px по контуру). Перезапуск ~1 с.
#
# Зависимости только из системы: sh, python3, dconf, pgrep, pkill.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
THEME_NAME=EwwIsland
USER_THEMES="$HOME/.local/share/plank/themes"
SYS_THEMES="/usr/share/plank/themes"
STATE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/eww-island"
BASE_FILE="$STATE_DIR/plank-base-theme"
LOG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/eww-island"
LOG="$LOG_DIR/plank.log"

mkdir -p "$LOG_DIR" 2>/dev/null || true
log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG" 2>/dev/null || true
}

dconf_key() {
  # Имя дока не хардкодим: берём первый из enabled-docks
  _dock=$(gsettings get net.launchpad.plank enabled-docks 2>/dev/null \
    | sed "s/[][]//g; s/'//g; s/,.*//" | tr -d ' \t')
  [ -n "$_dock" ] || _dock=dock1
  printf '/net/launchpad/plank/docks/%s/theme\n' "$_dock"
}

plank_running() {
  pgrep -x plank >/dev/null 2>&1
}

restart_plank() {
  if plank_running; then
    pkill -x plank 2>/dev/null || true
    # ждём выхода, иначе новый процесс увидит старый и уйдёт
    _i=0
    while [ "$_i" -lt 30 ] && plank_running; do
      sleep 0.1
      _i=$((_i + 1))
    done
  fi
  setsid -f plank >/dev/null 2>&1 || {
    log "ошибка: plank не запустился"
    return 1
  }
  # ждём окно дока, чтобы следующие замеры видели уже новую тему
  _i=0
  while [ "$_i" -lt 40 ]; do
    if wmctrl -l 2>/dev/null | grep -qi plank; then
      return 0
    fi
    sleep 0.05
    _i=$((_i + 1))
  done
  return 0
}

# Каталог темы по имени: сначала пользовательские, потом системные.
theme_dir() {
  for _d in "$USER_THEMES/$1" "$SYS_THEMES/$1"; do
    if [ -f "$_d/dock.theme" ]; then
      printf '%s\n' "$_d"
      return 0
    fi
  done
  return 1
}

case "${1:-apply}" in
  apply) ;;
  restore) ACTION=restore ;;
  status) ACTION=status ;;
  *) echo "usage: plank.sh [apply|restore|status]" >&2; exit 2 ;;
esac

command -v dconf >/dev/null 2>&1 || {
  echo "нет dconf - без него тему Plank не выбрать" >&2
  exit 1
}
command -v plank >/dev/null 2>&1 || {
  echo "нет plank - нечего красить" >&2
  exit 1
}

KEY=$(dconf_key)
CUR=$(dconf read "$KEY" 2>/dev/null | tr -d "'")
CUR=${CUR:-}

if [ "${ACTION:-apply}" = "status" ]; then
  echo "ключ:      $KEY"
  echo "тема:      ${CUR:-(не задана)}"
  echo "исходная:  $(cat "$BASE_FILE" 2>/dev/null || echo '(не записана)')"
  if [ -f "$USER_THEMES/$THEME_NAME/dock.theme" ]; then
    echo "рамка:     $(grep -m1 '^OuterStrokeColor=' "$USER_THEMES/$THEME_NAME/dock.theme" | cut -d= -f2)"
  fi
  echo "процесс:   $(plank_running && echo работает || echo не запущен)"
  exit 0
fi

# --- restore: вернуть исходную тему ---------------------------------------
if [ "${ACTION:-apply}" = "restore" ]; then
  BASE=$(cat "$BASE_FILE" 2>/dev/null || true)
  if [ -z "$BASE" ]; then
    echo "нечего возвращать: исходная тема не записана" >&2
    exit 1
  fi
  dconf write "$KEY" "'$BASE'"
  rm -f "$BASE_FILE"
  rm -rf "$USER_THEMES/$THEME_NAME"
  restart_plank || true
  log "возврат на исходную тему: $BASE"
  echo "тема Plank: $BASE (наша $THEME_NAME убрана)"
  exit 0
fi

# --- 1. исходная тема ------------------------------------------------------
# Первый запуск: текущая тема и есть исходная. Дальше исходная берётся из
# state-файла, иначе наша же копия стала бы «исходной» и рамка застыла бы.
BASE=$(cat "$BASE_FILE" 2>/dev/null || true)
if [ -z "$BASE" ]; then
  if [ -z "$CUR" ] || [ "$CUR" = "$THEME_NAME" ]; then
    BASE=Default
  else
    BASE=$CUR
  fi
  mkdir -p "$STATE_DIR"
  printf '%s\n' "$BASE" > "$BASE_FILE"
  log "исходная тема Plank: $BASE"
fi

BASE_DIR=$(theme_dir "$BASE") || {
  log "ошибка: нет темы $BASE (искал в $USER_THEMES и $SYS_THEMES)"
  echo "нет темы Plank '$BASE'" >&2
  exit 1
}

# --- 2. цвет акцента -------------------------------------------------------
# Берём $primary из уже сгенерированного eww/colors.scss: туда попадает
# выбранный акцент (primary/secondary/tertiary) с поправкой на контраст,
# поэтому рамка совпадает с островом при любой схеме, включая «С обоев».
CSS="$ROOT/eww/colors.scss"
[ -f "$CSS" ] || { echo "нет $CSS - сначала theme/apply.sh" >&2; exit 1; }
PRIMARY=$(sed -n 's/^\$primary: *\(#[0-9a-fA-F]\{6\}\).*/\1/p' "$CSS" | head -1)
[ -n "$PRIMARY" ] || { echo "в $CSS нет \$primary" >&2; exit 1; }

# --- 3. собрать тему EwwIsland --------------------------------------------
# Одна изменённая строка: OuterStrokeColor. Прозрачность (4-е число) и всё
# остальное берём из исходной темы, чтобы не менять чужой вид.
OUTDIR="$USER_THEMES/$THEME_NAME"
mkdir -p "$OUTDIR"

python3 - "$BASE_DIR/dock.theme" "$OUTDIR/dock.theme" "$PRIMARY" "$THEME_NAME" <<'PY'
import sys, re

src, dst, primary, theme_name = sys.argv[1:5]
text = open(src, encoding="utf-8", errors="replace").read()

hexv = primary.lstrip("#")
r, g, b = (int(hexv[i:i + 2], 16) for i in (0, 2, 4))

# Прозрачность рамки оставляем как в исходной теме (обычно 200 из 255).
alpha = 200
m = re.search(r"^OuterStrokeColor=(\d+);;(\d+);;(\d+);;(\d+)\s*$", text, re.M)
if m:
    alpha = int(m.group(4))

newline = "OuterStrokeColor=%d;;%d;;%d;;%d" % (r, g, b, alpha)
if m:
    text = text[:m.start()] + newline + text[m.end():]
else:
    # строки не было - добавляем после LineWidth, а если и его нет, в начало секции
    lm = re.search(r"^LineWidth=.*$", text, re.M)
    if lm:
        text = text[:lm.end()] + "\n" + newline + text[lm.end():]
    else:
        text = "OuterStrokeColor=%d;;%d;;%d;;%d\n" % (r, g, b, alpha) + text

open(dst, "w", encoding="utf-8").write(text)
PY
NEWLINE=$(grep -m1 '^OuterStrokeColor=' "$OUTDIR/dock.theme" | cut -d= -f2)

# --- 4. выбрать тему и перезапустить Plank --------------------------------
# Сравнивать надо с ПРЕДЫДУЩИМ содержимым, но снимок сделать уже поздно:
# python перезаписал файл. Поэтому сравниваем с тем, что сейчас показывает
# Plank - исходную тему, если выбрана она, иначе нашу (её цвет сохранён в
# state-файле после прошлого применения).
STATE_COLOR="$STATE_DIR/plank-color"
SHOWN=$(cat "$STATE_COLOR" 2>/dev/null || true)
if [ "$CUR" != "$THEME_NAME" ]; then
  # Показывается исходная тема - её цвет и есть текущий.
  SHOWN=$(grep -m1 '^OuterStrokeColor=' "$BASE_DIR/dock.theme" | cut -d= -f2 || true)
fi

if [ "$CUR" = "$THEME_NAME" ] && [ "$NEWLINE" = "$SHOWN" ] && plank_running; then
  # Уже наша тема, цвет тот же и Plank работает - перезапускать незачем.
  # Проверка plank_running обязательна: иначе закрытый док так и остался бы
  # закрытым (проверено - скрипт молча выходил «без изменений»).
  log "без изменений: рамка $NEWLINE"
  exit 0
fi

dconf write "$KEY" "'$THEME_NAME'"
restart_plank || true
mkdir -p "$STATE_DIR"
printf '%s\n' "$NEWLINE" > "$STATE_COLOR"
log "рамка Plank: $PRIMARY -> $NEWLINE (тема $THEME_NAME из $BASE)"
echo "рамка Plank: $PRIMARY"
