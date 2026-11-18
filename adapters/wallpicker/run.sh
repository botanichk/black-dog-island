#!/bin/sh
# run.sh - открыть выбор обоев (hypr-wallpicker) на весь экран.
#
# usage: adapters/wallpicker/run.sh
#
# Почему не просто запуск бинарника: сетка при умолчаниях 5 колонок по 361 px
# = 1973 px, а экран 1366. Без разворота правая часть сетки уходит за край
# (замерено: миниатюры x=0..1365, но центр сетки за экраном). Поэтому:
#   - колонок 3 (ширина сетки 1250 px, влезает в 1366);
#   - окно развёрнуто на весь экран.
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
setsid -f "$BIN" -c 3 "$DIR" >>"$LOG" 2>&1
log "запуск: $BIN -c 3 $DIR"

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
