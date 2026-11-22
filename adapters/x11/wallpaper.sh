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

# run_to: wmctrl и запуск под таймаутом (см. theme/guard.sh). Без него
# зависший X-сервер держит кнопку до её таймаута в 25 с.
. "$ROOT/theme/guard.sh"

# Запасной вариант: родной настройщик. Уже открыт - поднимаем, копию не плодим.
xfce_fallback() {
  command -v "$XFCE_BIN" >/dev/null 2>&1 || {
    log "ошибка: нет $XFCE_BIN"
    echo "ошибка: $XFCE_BIN не найден" >&2
    exit 1
  }
  if run_to 3 wmctrl -lx 2>/dev/null | grep -q " $XFCE_CLASS "; then
    id=$(run_to 3 wmctrl -lx 2>/dev/null | awk -v c="$XFCE_CLASS" '$3 == c {print $1; exit}')
    [ -n "$id" ] && run_to 3 wmctrl -i -a "$id" 2>/dev/null || true
    exit 0
  fi
  if command -v setsid >/dev/null 2>&1; then
    run_to 10 setsid -f "$XFCE_BIN" >/dev/null 2>&1
  else
    "$XFCE_BIN" >/dev/null 2>&1 &
  fi
  i=0
  while [ "$i" -lt 20 ]; do
    run_to 3 wmctrl -lx 2>/dev/null | grep -q " $XFCE_CLASS " && exit 0
    sleep 0.1
    i=$((i + 1))
  done
  log "предупреждение: окно $XFCE_CLASS не появилось за 2 с"
  exit 0
}

# Основной вариант: выбор шестиугольниками. run.sh сам решает, можно ли его
# запускать (нет бинарника или папки - код 1/2), поэтому проверка здесь одна.
#
# run_to 30: у кнопки :timeout 25s. Внутри run.sh ждёт окно до 20 с, но если
# программа падает сразу - выходит раньше с кодом 4 и причиной. Таймаут тут
# нужен на случай, если сам run.sh застрянет: кнопка обязана ответить.
if run_to 30 "$ROOT/adapters/wallpicker/run.sh" 2>/dev/null; then
  exit 0
fi

# Причина уже в wallpicker.log (её пишут и run.sh, и этот скрипт). Коротко
# повторяем последнюю строку в тот же лог, чтобы рядом с «открываю запасной»
# было видно, почему.
_why=$(grep -E "ошибка:|не появилось|не запустились" "$LOG" 2>/dev/null | tail -1 | sed 's/^[0-9-]* [0-9:]* //')
log "wallpicker не запустился${_why:+ ($_why)} - открываю xfdesktop-settings"
xfce_fallback
