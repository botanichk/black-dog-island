#!/bin/sh
# Прокрутка рабочих столов колесом над точками воркспейсов.
# usage: ws-scroll.sh up|down
#   up   - предыдущий стол;
#   down - следующий стол.
# На краях останавливается (без зацикливания).
# Троттлинг 120 мс: тачпад присылает лавину событий, без него столы
# перескакивают. Метка времени - в ${XDG_RUNTIME_DIR:-/tmp}/ws-scroll.stamp.
set -eu

THROTTLE_MS=120
STAMP="${XDG_RUNTIME_DIR:-/tmp}/ws-scroll.stamp"

case "${1:-}" in
  up) step=-1 ;;
  down) step=1 ;;
  *) echo "usage: ws-scroll.sh up|down" >&2; exit 2 ;;
esac

cur=$(xprop -root _NET_CURRENT_DESKTOP 2>/dev/null | sed -n 's/.*= *\([0-9]\+\)$/\1/p')
count=$(xprop -root _NET_NUMBER_OF_DESKTOPS 2>/dev/null | sed -n 's/.*= *\([0-9]\+\)$/\1/p')
[ -n "$cur" ] && [ -n "$count" ] || { echo "не удалось прочитать _NET_CURRENT_DESKTOP/_NET_NUMBER_OF_DESKTOPS" >&2; exit 1; }

next=$((cur + step))
# Края: ничего не делаем, чтобы не зацикливаться.
[ "$next" -ge 0 ] || exit 0
[ "$next" -lt "$count" ] || exit 0

# Троттлинг по монотонным миллисекундам (date +%s%N не зависит от смены времени).
now=$(( $(date +%s%N) / 1000000 ))
if [ -r "$STAMP" ]; then
  last=$(cat "$STAMP" 2>/dev/null || echo 0)
  case "$last" in
    ''|*[!0-9]*) last=0 ;;
  esac
  [ $((now - last)) -ge "$THROTTLE_MS" ] || exit 0
fi

wmctrl -s "$next" || exit 1
printf '%s' "$now" > "$STAMP" 2>/dev/null || true
