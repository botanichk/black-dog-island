#!/bin/sh
# Выпадающая панель под кнопкой острова.
# Панель открывается ровно под той кнопкой, по которой кликнули: позиция берётся
# из курсора (он остаётся на кнопке в момент клика), ширина - из аргумента.
# Повторный клик по той же кнопке закрывает панель (eww open --toggle).
#
# usage: panel.sh <имя окна> <ширина панели>
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
BIN="${XDG_CACHE_HOME:-$HOME/.cache}/eww-island/pointer"
EWW="$ROOT/build/target/release/eww"
CONF="$ROOT/eww"

[ "${1:-}" = "" ] && { echo "usage: panel.sh <window> <width>" >&2; exit 2; }

NAME=$1
WIDTH=${2:-280}
HEIGHT=${3:-300}

if [ ! -x "$BIN" ] || [ "$ROOT/adapters/x11/pointer.c" -nt "$BIN" ]; then
  mkdir -p "$(dirname -- "$BIN")"
  gcc -O2 -o "$BIN" "$ROOT/adapters/x11/pointer.c" -lX11
fi

# Позиция курсора: X - по кнопке, Y - не нужен.
PX=$("$BIN" | cut -d' ' -f1)

# Низ острова: панель открывается под ним.
ISLAND=$(wmctrl -lG 2>/dev/null | awk '/Eww - island$/ {print $4 + $6; exit}')
[ -n "${ISLAND:-}" ] || ISLAND=50

SCREEN_W=$(xrandr --current | awk '/\*/{print $1; exit}' | cut -d x -f1)

# Панель по центру под кнопкой, но не вылезает за края экрана.
X=$((PX - WIDTH / 2))
[ "$X" -lt 0 ] && X=0
[ $((X + WIDTH)) -gt "$SCREEN_W" ] && X=$((SCREEN_W - WIDTH))

"$EWW" --config "$CONF" open "$NAME" --toggle --pos "${X}x${ISLAND}"

# xfwm4 центрирует обычные окна, игнорируя --pos от Eww. Поэтому ставим
# геометрию через wmctrl -e - он работает с обычными окнами.
# Окно появляется не сразу и xfwm4 успевает перецентрировать его уже после
# первого wmctrl -r, поэтому позицию ставим дважды: сразу и ещё раз с задержкой.
i=0
while [ "$i" -lt 20 ]; do
  wmctrl -lG 2>/dev/null | grep -q "Eww - $NAME\$" && break
  i=$((i + 1))
  sleep 0.1
done

wmctrl -r "Eww - $NAME" -e 0,"$X","$ISLAND","$WIDTH","$HEIGHT" 2>/dev/null || true
sleep 0.5
wmctrl -r "Eww - $NAME" -e 0,"$X","$ISLAND","$WIDTH","$HEIGHT" 2>/dev/null || true
