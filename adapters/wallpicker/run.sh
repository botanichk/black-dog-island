#!/bin/sh
# run.sh - открыть выбор обоев (hypr-wallpicker) на весь экран.
#
# usage: adapters/wallpicker/run.sh
#
# Почему не просто запуск бинарника: сетка по умолчанию (5 колонок при
# RADIUS=200) занимает 1973 px по ширине и ~3550 по высоте - на экране
# 1366x768 видно меньше трети, приходится прокручивать.
# Поэтому по умолчанию:
#   - радиус шестиугольника 85 px (-r 85, миниатюра 170x170);
#   - колонок 7 (-c 7, ширина сетки 1250 px, влезает в 1366);
#   - окно развёрнуто на весь экран.
# При 32 обоях это все миниатюры сразу, без прокрутки (замерено: центры
# от x=156 до 1210, y=99..669). Размер и колонки можно переопределить
# переменными WALLPICKER_RADIUS и WALLPICKER_COLS.
#
# Про fullscreen и автоскрытие острова: остров прячется, когда активное окно
# в _NET_WM_STATE_FULLSCREEN, и открывается сам, когда выбор закрыли
# (проверено замером: 373 0 619x50 до и после, во время выбора острова нет).
#
# Одна копия: повторный запуск поднимает уже открытое окно (wmctrl -a).
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
BIN="${WALLPICKER_BIN:-$HOME/src/hypr-wallpicker/wallpicker}"
CLASS="wallpicker.wallpicker"
LOG_DIR="${BDI_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/bdi}"
LOG="$LOG_DIR/wallpicker.log"

# --- сетка под экран и число обоев ----------------------------------------
# Было жёстко 85 px / 7 колонок - под 32 обои. Стало 42: рядов 6, сетка
# 832 px при экране 768, нижний ряд уходит за край - снаружи «соты видно, а
# они слетают». Теперь радиус считается от числа обоев и экрана.
# Зазор 5, а не апстримные 15: на 1366x768 большие зазоры расползаются.
SPACING=${WALLPICKER_SPACING:-5}

SW=$(xrandr --current 2>/dev/null | awk '/\*/{print $1; exit}' | cut -d x -f1)
SH=$(xrandr --current 2>/dev/null | awk '/\*/{print $1; exit}' | cut -d x -f2)
[ -n "${SW:-}" ] && [ -n "${SH:-}" ] || { SW=1366; SH=768; }

# Обои папки: те же расширения, что понимает сам wallpicker.
count_walls() {
  find "$1" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) 2>/dev/null | wc -l
}

# Радиус и колонки под $1 обоев и экран ${2}x${3}: печатает "радиус колонки".
# Шаг сетки по X 1.732*r+sp, по Y 1.5*r+sp (src/ui.c, BuildGridLayout).
# Берём самое крупное из влезающих: сначала 7 колонок, потом 6 и 5.
fit_grid() {
  _n=$1 _sw=$2 _sh=$3
  for _c in 7 6 5; do
    [ "$_c" -le "$_n" ] || continue
    _rows=$(( (_n + _c - 1) / _c ))
    _r=$(( (_sh - 16 - SPACING * (_rows - 1)) * 1000 / (1500 * (_rows - 1) + 2000) ))
    [ "$_r" -ge 40 ] || continue
    _w=$(( 1732 * _r * (_c - 1) / 1000 + 1732 * _r / 1000 + SPACING * (_c - 1) ))
    [ "$_w" -le $(( _sw - 16 )) ] || continue
    printf '%s %s\n' "$_r" "$_c"
    return 0
  done
  printf '70 5\n'
}

# Папка обоев: аргумент -> WALLPAPER_DIR -> картинки пользователя по XDG ->
# ~/Изображения -> ~/Pictures. Зашивать одно имя нельзя: на чужой системе
# папка называется по-английски (Pictures), и соты не открывались вовсе.
wall_dir() {
  for d in "${WALLPAPER_DIR:-}" "$(command -v xdg-user-dir >/dev/null 2>&1 && xdg-user-dir PICTURES 2>/dev/null)" \
           "$HOME/Изображения" "$HOME/Pictures"; do
    # xdg-user-dir без настроек отдаёт сам $HOME - это не папка картинок.
    [ -n "$d" ] && [ "$d" != "$HOME" ] && [ -d "$d" ] && { printf '%s\n' "$d"; return 0; }
  done
  printf '%s\n' "${WALLPAPER_DIR:-$HOME/Изображения}"
}
DIR=${1:-$(wall_dir)}

mkdir -p "$LOG_DIR" 2>/dev/null || true
log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG" 2>/dev/null || true
}

# --- уже открыто? ---------------------------------------------------------
if wmctrl -lx 2>/dev/null | grep -q " $CLASS "; then
  id=$(wmctrl -lx 2>/dev/null | awk -v c="$CLASS" '$3 == c {print $1; exit}')
  [ -n "$id" ] && wmctrl -i -a "$id" 2>/dev/null || true
  log "окно уже открыто, поднял: $id"
  exit 0
fi

if [ ! -x "$BIN" ]; then
  log "ошибка: нет программы $BIN"
  echo "нет $BIN - соберите по docs/WALLPICKER.md" >&2
  exit 1
fi

if [ ! -d "$DIR" ]; then
  log "ошибка: нет папки обоев $DIR"
  echo "нет папки обоев: $DIR" >&2
  exit 2
fi

# --- запуск ---------------------------------------------------------------
# setsid -f: окно переживает команду кнопки. Без setsid команда умирает
# вместе с таймаутом кнопки, и снаружи это «кнопка обоев молчит».
SPAWN="setsid -f"
command -v setsid >/dev/null 2>&1 || SPAWN=""

# Фон под миниатюрами: те самые обои, что сейчас на столе, размытые и
# затемнённые на 40%. Берём путь к файлу из xfconf - это ровно то, что
# нарисовал xfdesktop, без снятия экрана и без композитора.
#   -b <файл>   обои для фона (нет файла - окно прозрачное, как раньше)
#   --blur 16   размытие: уменьшить в 16 раз и растянуть обратно
#   --scrim 40  затемнение, процентов чёрного
#
# Аргументы собираем через set --, а не строкой: у владельца файл обоев
# называется «кот встречает.png», и пробел в пути развалил бы вызов на слова.
. "$ROOT/theme/desktop.sh"
CURRENT_WALL=$(xfce_current_wallpaper 2>/dev/null || true)

# Размер экрана: xrandr даёт текущий режим. Без него - 1366x768, как у владельца.

# Ручные значения хозяина главнее расчёта: WALLPICKER_RADIUS / WALLPICKER_COLS.
NWALL=$(count_walls "$DIR")
if [ -n "${WALLPICKER_RADIUS:-}" ] && [ -n "${WALLPICKER_COLS:-}" ]; then
  RADIUS=$WALLPICKER_RADIUS
  COLS=$WALLPICKER_COLS
else
  GRID=$(fit_grid "${NWALL:-0}" "$SW" "$SH")
  RADIUS=${WALLPICKER_RADIUS:-${GRID% *}}
  COLS=${WALLPICKER_COLS:-${GRID#* }}
fi
log "сетка: $NWALL обоев, радиус $RADIUS, колонок $COLS, экран ${SW}x${SH}"

set -- -c "$COLS" -r "$RADIUS" -s "$SPACING" \
  --blur "${WALLPICKER_BLUR:-16}" --scrim "${WALLPICKER_SCRIM:-40}"

if [ -n "$CURRENT_WALL" ] && [ -f "$CURRENT_WALL" ]; then
  set -- "$@" -b "$CURRENT_WALL"
  log "фон: $CURRENT_WALL"
else
  log "фон: обои не найдены - окно будет прозрачным"
fi

set -- "$@" "$DIR"

# setsid -f: окно переживает команду кнопки острова. stdout/stderr в лог:
# raylib сыплет INFO на каждую текстуру, в консоли это мусор.
if [ -n "$SPAWN" ]; then
  setsid -f "$BIN" "$@" >>"$LOG" 2>&1
else
  # Без setsid окно проживёт до выхода команды кнопки: лучше показать окно
  # и честно предупредить, чем молчать.
  log "нет setsid: запускаю в фоне, окно может закрыться с командой"
  "$BIN" "$@" >>"$LOG" 2>&1 &
fi
log "запуск: $BIN $*"

# --- развернуть на весь экран --------------------------------------------
# Ждём окно до 20 с: первый запуск строит кэш миниатюр (42 файла, ~10 с на
# 4 ядрах, в виртуалке дольше), но окно появляется раньше - оно рисует
# «Loading». Раньше ждали 5 с, и на медленной машине скрипт сдавался, хотя
# окно вот-вот появлялось: кнопка выглядела мёртвой.
#
# Про док: разворот на весь экран включает _NET_WM_STATE_FULLSCREEN, по нему
# остров прячется. Если док мешает, он прячется сам - его не трогаем.
i=0
while [ "$i" -lt 200 ]; do
  id=$(wmctrl -lx 2>/dev/null | awk -v c="$CLASS" '$3 == c {print $1; exit}')
  if [ -n "$id" ]; then
    wmctrl -i -r "$id" -b add,fullscreen 2>/dev/null || true
    log "окно $id развёрнуто"
    exit 0
  fi
  sleep 0.1
  i=$((i + 1))
done

log "предупреждение: окно $CLASS не появилось за 20 с"
echo "окно не появилось за 20 с, смотрите $LOG" >&2
exit 3
