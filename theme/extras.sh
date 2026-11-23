#!/bin/sh
# extras.sh - тяжёлая часть смены темы: док Plank и тема Ulauncher.
#
# Зачем отдельный файл: эти два шага ходят в D-Bus (dconf, gsettings) и
# перезапускают Plank. На виртуалке это секунды, и пока они шли вместе с
# рендером темы, кнопка «Цвета» вешала остров. apply.sh зовёт этот скрипт
# через setsid -f в фоне, сразу после того как colors.scss уже применён:
# остров перекрашивается мгновенно, док и лаунчер догоняют.
#
# Замеры пишутся в theme.log тем же видом, что у apply.sh: «шаг <метка> мс=
# <сколько> код=<код>». По ним видно, какой из двух шагов медленный.
#
# Повторный запуск: pid-файл theme-extras.pid. Второй экземпляр не встаёт в
# очередь, а выходит сразу - кнопку можно жать сколько угодно.
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BDI_CACHE="${BDI_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/bdi}"
LOG="$BDI_CACHE/theme.log"
mkdir -p "$BDI_CACHE" 2>/dev/null || true

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG" 2>/dev/null || true; }

# guard.sh: run_to и now_ms. Подключаем до lock, чтобы now_ms был готов.
. "$ROOT/theme/guard.sh"

# Одна копия. Замок на mkdir (см. lock_take в theme/guard.sh): pid-файл эту
# задачу не решал - между чтением и записью оба запуска проходили проверку.
LOCK="$BDI_CACHE/theme-extras.lock"
if ! lock_take "$LOCK"; then
  log "док и лаунчер уже красятся (pid ${LOCK_PID:-?}) - пропускаю"
  exit 0
fi
trap 'rm -f "$LOCK/pid" 2>/dev/null || true; rmdir "$LOCK" 2>/dev/null || true' EXIT INT TERM HUP

T0=$(now_ms)
for _t in plank ulauncher; do
  [ -x "$ROOT/theme/$_t.sh" ] || continue
  _s=$(now_ms)
  if run_to 20 "$ROOT/theme/$_t.sh" apply >/dev/null 2>&1; then
    log "шаг $_t мс=$(( $(now_ms) - _s )) код=0"
  else
    log "шаг $_t мс=$(( $(now_ms) - _s )) код=1 (остров живёт без него)"
  fi
done
log "готово: док и лаунчер, мс=$(( $(now_ms) - T0 ))"
