#!/bin/sh
# Раскладка: печатает код текущей раскладки (US/RU), "next" переключает на следующую.
# X11-хелпер собирается при первом запуске: xkb-switch и xkblayout-state в системе нет.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
BIN="${BDI_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/bdi}/kbdlayout"

if [ ! -x "$BIN" ] || [ "$ROOT/adapters/x11/kbdlayout.c" -nt "$BIN" ]; then
  mkdir -p "$(dirname -- "$BIN")"
  gcc -O2 -o "$BIN" "$ROOT/adapters/x11/kbdlayout.c" -lX11
fi

[ "${1:-}" = "next" ] && exec "$BIN" next

# "us,ru" -> группа 0 = us; номер группы приходит из хелпера
LAYOUTS=$(setxkbmap -query | sed -n 's/^layout:[[:space:]]*//p')

"$BIN" watch | while read -r group; do
  name=$(printf '%s' "$LAYOUTS" | cut -d, -f $((group + 1)))
  printf '%s\n' "$name" | tr 'a-z' 'A-Z'
done
