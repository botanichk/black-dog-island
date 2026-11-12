#!/bin/sh
# Громкость: up/down по 5% (не выше 100%), mute — переключение.
set -eu

cur() {
  pactl get-sink-volume @DEFAULT_SINK@ | grep -o '[0-9]\+%' | head -1 | tr -d %
}

case "${1:-}" in
  up)
    # Ставим абсолютное значение: pactl "+5%" округляет вверх (96% -> 101%).
    v=$(cur)
    target=$((v + 5))
    [ "$target" -gt 100 ] && target=100
    pactl set-sink-volume @DEFAULT_SINK@ "${target}%"
    ;;
  down)
    v=$(cur)
    target=$((v - 5))
    [ "$target" -lt 0 ] && target=0
    pactl set-sink-volume @DEFAULT_SINK@ "${target}%"
    ;;
  mute)
    pactl set-sink-mute @DEFAULT_SINK@ toggle
    ;;
  *)
    echo "usage: volume.sh up|down|mute" >&2
    exit 2
    ;;
esac
