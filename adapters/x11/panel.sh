#!/bin/sh
# Выпадающая панель под островом, по его центру.
# Повторный запуск для уже открытой панели закрывает её.
# usage: panel.sh <окно> [примерная ширина]
# Ширину задаёт panel.sh (по острову), высоту - содержимое.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
EWW="$ROOT/build/target/release/eww"
CONF="$ROOT/eww"

[ -n "${1:-}" ] || { echo "usage: panel.sh <window> [width]" >&2; exit 2; }
NAME=$1
GUESS=${2:-300}
TITLE="Eww - $NAME"

# Печатает "x y w h" окна с таким заголовком (пусто, если окна нет).
win_geo() {
  wmctrl -lG 2>/dev/null | awk -v t="$1" '$0 ~ (t "$") {print $3, $4, $5, $6; exit}'
}

# Панель уже открыта - закрываем и выходим.
if [ -n "$(win_geo "$TITLE")" ]; then
  "$EWW" --config "$CONF" close "$NAME"
  exit 0
fi

# Остров: x, ширина, низ. Ищем по PID демона + _NET_WM_WINDOW_TYPE_DOCK.
geom=$("$ROOT/adapters/x11/island-geom.sh" 2>/dev/null || true)
[ -n "$geom" ] || { echo "ошибка: остров не найден (island-geom.sh не ответил)" >&2; exit 1; }
IX=$(echo "$geom" | awk '{print $2}')
IW=$(echo "$geom" | awk '{print $4}')
Y=$(echo "$geom" | awk '{print $3 + $5}')

# X панели по центру острова.
x_for() {
  x=$IX
  [ "$x" -ge 0 ] || x=0
  echo "$x"
}
X=$(x_for "$GUESS")

# Ширина передаётся сразу: окно рождается в финальном размере под островом.
"$EWW" --config "$CONF" open "$NAME" --arg "w=${IW}px" --pos "${X}x${Y}"

# Ждём появления окна (до 3 с).
i=0; geo=
while [ -z "$geo" ] && [ "$i" -lt 30 ]; do
  geo=$(win_geo "$TITLE")
  [ -n "$geo" ] || { sleep 0.1; i=$((i + 1)); }
done
[ -n "$geo" ] || { echo "ошибка: панель $NAME не появилась" >&2; exit 1; }

# xfwm4 может переставить окно после открытия: держим позицию, пока она не
# продержится 3 проверки подряд (размер не трогаем: -1).
ok=0; i=0; final_x=0; final_y=0
while [ "$ok" -lt 3 ] && [ "$i" -lt 20 ]; do
  set -- $(win_geo "$TITLE")
  [ "$#" -eq 4 ] || break
  if [ "$1" -eq "$X" ] && [ "$2" -eq "$Y" ] && [ "$3" -eq "$IW" ]; then
    ok=$((ok + 1))
  else
    ok=0
    wmctrl -r "$TITLE" -e "0,$X,$Y,$IW,-1" 2>/dev/null || true
  fi
  final_x=$1; final_y=$2
  i=$((i + 1))
  sleep 0.1
done
[ "$ok" -ge 3 ] || echo "предупреждение: позиция панели $NAME не устоялась (фактически: ${final_x}x${final_y}, ожидалось: ${X}x${Y})" >&2
