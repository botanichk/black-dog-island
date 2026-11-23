#!/bin/sh
# wallpaper.sh - кнопка обоев на острове (этап 6, шаг 4; задание 13).
#
# Открывает выбор обоев шестиугольниками (hypr-wallpicker). Если программы нет
# (не собрана) - говорит об этом вслух и предлагает xfdesktop-settings.
# Если программа есть, но открыть не удалось (нет папки, нет обоев, упала) -
# показывает причину, а НЕ открывает молча запасной настройщик: раньше любой
# провал выглядел как «кнопка открыла чужое окно», и причину было не видно.
#
# Запасной вариант остаётся на случай, когда выбор недоступен в принципе
# (нет бинарника) - и тогда причина тоже печатается.
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
. "$ROOT/lib/wallpaper.sh"

# Запасной вариант: родной настройщик. Уже открыт - поднимаем, копию не плодим.
# Причину печатает вызывающий: здесь только действие.
xfce_fallback() {
  command -v "$XFCE_BIN" >/dev/null 2>&1 || {
    log "ошибка: нет $XFCE_BIN"
    bdi_notify "Нет ни выбора обоев, ни xfdesktop-settings"
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
_rc=0
run_to 30 "$ROOT/adapters/wallpicker/run.sh" 2>/dev/null || _rc=$?
[ "$_rc" -eq 0 ] && exit 0

# Причина уже в wallpicker.log (её пишут и run.sh, и этот скрипт). Коротко
# повторяем последнюю строку в тот же лог и показываем человеку.
_why=$(grep -E "ошибка:|не появилось|не запустились|нет обоев" "$LOG" 2>/dev/null \
  | tail -1 | sed 's/^[0-9-]* [0-9:]* //')
log "wallpicker не запустился (код $_rc)${_why:+: $_why}"

# Код 1 = нет самой программы. Это единственный случай, когда запасной путь
# уместен без вопроса: выбрать обои больше нечем. Остальные коды (2 - нет
# папки, 4 - упала, 5 - нет обоев, 3 - окно не появилось) человек должен
# видеть, иначе лечение уходит не туда.
if [ "$_rc" -eq 1 ]; then
  bdi_notify "Выбор обоев не собран, открываю настройщик XFCE"
  log "нет программы выбора обоев - открываю xfdesktop-settings"
  xfce_fallback
fi

bdi_notify "Выбор обоев не открылся${_why:+: $_why}"
echo "выбор обоев не открылся: ${_why:-смотрите $LOG}" >&2
exit "$_rc"
