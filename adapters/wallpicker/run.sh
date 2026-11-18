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
LOG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/eww-island"
LOG="$LOG_DIR/wallpicker.log"

# Радиус и число колонок: 85 px / 7 колонок подобраны под 1366x768, чтобы
# 32 обои влезли целиком. Патч на -r лежит в patches/.
RADIUS=${WALLPICKER_RADIUS:-85}
COLS=${WALLPICKER_COLS:-7}

# Папка обоев: первым делом аргумент, потом WALLPAPER_DIR, потом ~/Изображения
# (у владельца обои там), и только затем умолчание самой программы.
DIR=${1:-${WALLPAPER_DIR:-$HOME/Изображения}}

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
# setsid -f: окно переживает команду кнопки острова. stdout/stderr в лог:
# raylib сыплет INFO на каждую текстуру, в консоли это мусор.
setsid -f "$BIN" -c "$COLS" -r "$RADIUS" "$DIR" >>"$LOG" 2>&1
log "запуск: $BIN -c $COLS -r $RADIUS $DIR"

# --- развернуть на весь экран --------------------------------------------
# Ждём окно до 5 с: первый запуск строит кэш миниатюр (31 файл, ~10 с на
# 4 ядрах), но окно появляется раньше - оно рисует «Loading».
i=0
while [ "$i" -lt 50 ]; do
  id=$(wmctrl -lx 2>/dev/null | awk -v c="$CLASS" '$3 == c {print $1; exit}')
  if [ -n "$id" ]; then
    # Окно само просит 1366x718 (wmctrl -lG это показал). Разворот ставит
    # его в 1366x768 и включает _NET_WM_STATE_FULLSCREEN - по нему остров
    # понимает, что нужно спрятаться.
    wmctrl -i -r "$id" -b add,fullscreen 2>/dev/null || true
    log "окно $id развёрнуто"
    exit 0
  fi
  sleep 0.1
  i=$((i + 1))
done

log "предупреждение: окно $CLASS не появилось за 5 с"
echo "окно не появилось за 5 с, смотрите $LOG" >&2
exit 3
