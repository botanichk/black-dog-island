#!/bin/sh
# apply.sh - хук hypr-wallpicker под XFCE: поставить выбранные обои.
#
# usage: adapters/wallpicker/apply.sh <путь к картинке> [rel_x] [rel_y]
#
# Вызывается программой wallpicker сама, через символическую ссылку
# ~/.config/hypr-wallpicker/apply-wallpaper.sh (её создаёт install.sh).
# Контракт из src/apply.c: /bin/sh <хук> <полный путь> <rel_x> <rel_y>,
# в отдельном процессе (fork), поэтому окно выбора не ждёт нас.
#
# Что делает:
#   1. ставит обои через xfconf (xfdesktop их подхватит сам);
#   2. если сейчас активна схема «с обоев» - пересчитывает палитру новыми
#      обоями и перезагружает остров. Обычную палитру НЕ трогает: человек
#      выбрал конкретную палитру, и смена картинки не должна её отменять;
#   3. пишет всё в ~/.cache/eww-island/wallpicker.log, а не в stdout:
#      stdout принадлежит программе выбора, и мусор в нём не нужен.
#
# Зависимости только из системы: sh, xfconf-query, xrandr, xprop, noctalia.
set -eu

# $0 - путь ССЫЛКИ (~/.config/hypr-wallpicker/apply-wallpaper.sh), а не
# нашего файла: wallpicker запускает ссылку через /bin/sh. Без readlink -f
# dirname/../.. дал бы ~/.config, и подключаемые файлы не нашлись бы
# (проверено: «строка 46: ~/theme/desktop.sh: Нет такого файла»).
SELF=$(readlink -f "$0")
ROOT=$(CDPATH= cd -- "$(dirname -- "$SELF")/../.." && pwd)
LOG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/eww-island"
LOG="$LOG_DIR/wallpicker.log"

# Путь приходит первым аргументом. rel_x/rel_y нам не нужны: xfdesktop сам
# решает, как масштабировать (у стола свой image-style). Не ругаемся на них -
# программа передаёт их всегда.
WALL=${1:-}

mkdir -p "$LOG_DIR" 2>/dev/null || true
log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG" 2>/dev/null || true
}

if [ -z "$WALL" ]; then
  log "ошибка: хук вызван без пути к картинке"
  exit 2
fi

if [ ! -f "$WALL" ]; then
  log "ошибка: файла нет: $WALL"
  exit 3
fi

. "$ROOT/theme/desktop.sh"

# --- 1. обои --------------------------------------------------------------
# Один и тот же файл дважды подряд (повторный клик по той же картинке) -
# всё равно применяем: xfdesktop мог перерисоваться, а лишних действий у
# нас немного. Зато лог честно покажет каждый клик.
if ! KEY=$(xfce_set_wallpaper "$WALL"); then
  log "ошибка: не удалось записать обои $WALL"
  exit 4
fi
log "обои: $WALL -> $KEY"

# --- 2. палитра -----------------------------------------------------------
# Схема «с обоев» активна, когда theme/current = wallpaper. Именно так её
# определяет вкладка «Цвета» (theme/colors-pick.sh пишет это же значение).
CURRENT=$(tr -d ' \t\r\n' < "$ROOT/theme/current" 2>/dev/null || true)

if [ "$CURRENT" != "wallpaper" ]; then
  log "палитра не с обоев (theme/current=$CURRENT) - цвета не меняю"
  exit 0
fi

# Режим и m3-схему берём из уже сохранённого выбора, чтобы клик по обоям
# не сбрасывал «Яркую» на «Спокойную» и не переключал светлое на тёмное.
MODE=$(tr -d ' \t\r\n' < "$ROOT/theme/mode" 2>/dev/null || true)
case "$MODE" in light|dark) ;; *) MODE=dark ;; esac
SCHEME=$(tr -d ' \t\r\n' < "$ROOT/theme/wallpaper-scheme" 2>/dev/null || true)
[ -n "$SCHEME" ] || SCHEME=m3-tonal-spot

# Пересчёт палитры и reload занимают секунды: человек уже закрыл окно
# выбора, но остров не должен подвиснуть. Хук и так запущен отдельным
# процессом (fork в apply.c), поэтому просто делаем работу здесь и пишем
# в лог. Ошибку не пробрасываем наружу: обои уже применены.
if "$ROOT/theme/from-wallpaper.sh" "$SCHEME" "$MODE" --reload >>"$LOG" 2>&1; then
  log "палитра пересчитана: $SCHEME, $MODE"
else
  log "ошибка: палитра не пересчиталась (обои применены)"
fi

exit 0
