#!/bin/sh
# wallpaper.sh - кнопка обоев на острове (этап 6, шаг 4; задание 13).
#
# Сначала пробует выбор обоев шестиугольниками (hypr-wallpicker). Если он не
# собран или упал - открывает родной настройщик XFCE (xfdesktop-settings),
# чтобы кнопка никогда не оставалась «мёртвой».
#
# Почему обе ветки в одном файле: команда кнопки должна жить в одном месте
# (значение :onclick задаёт только имя скрипта), и запасной вариант проще
# держать рядом с основным, чем в yuck.
#
# Зависимости: sh, wmctrl. Сам wallpicker - отдельная программа, см.
# docs/WALLPICKER.md.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
LOG_DIR="${BDI_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/bdi}"
LOG="$LOG_DIR/wallpicker.log"

XFCE_CLASS="xfdesktop-settings.Xfdesktop-settings"
XFCE_BIN="xfdesktop-settings"

mkdir -p "$LOG_DIR" 2>/dev/null || true
log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG" 2>/dev/null || true
}

# Запасной вариант: родной настройщик. Уже открыт - поднимаем, копию не плодим.
xfce_fallback() {
  command -v "$XFCE_BIN" >/dev/null 2>&1 || {
    log "ошибка: нет $XFCE_BIN"
    echo "ошибка: $XFCE_BIN не найден" >&2
    exit 1
  }
  if wmctrl -lx 2>/dev/null | grep -q " $XFCE_CLASS "; then
    id=$(wmctrl -lx 2>/dev/null | awk -v c="$XFCE_CLASS" '$3 == c {print $1; exit}')
    [ -n "$id" ] && wmctrl -i -a "$id" 2>/dev/null || true
    exit 0
  fi
  if command -v setsid >/dev/null 2>&1; then
    setsid -f "$XFCE_BIN" >/dev/null 2>&1
  else
    "$XFCE_BIN" >/dev/null 2>&1 &
  fi
  i=0
  while [ "$i" -lt 20 ]; do
    wmctrl -lx 2>/dev/null | grep -q " $XFCE_CLASS " && exit 0
    sleep 0.1
    i=$((i + 1))
  done
  log "предупреждение: окно $XFCE_CLASS не появилось за 2 с"
  exit 0
}

# Основной вариант: выбор шестиугольниками. run.sh сам решает, можно ли его
# запускать (нет бинарника или папки - код 1/2), поэтому проверка здесь одна.
if "$ROOT/adapters/wallpicker/run.sh"; then
  exit 0
fi

log "wallpicker не запустился - открываю xfdesktop-settings"
xfce_fallback
