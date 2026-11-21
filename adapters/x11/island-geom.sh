#!/bin/sh
# Поиск окна острова Eww Island по XID.
#
# Остров ищется не по заголовку, а по двум признакам сразу:
#   * _NET_WM_PID окна == PID нашего демона Eww;
#   * тип окна == _NET_WM_WINDOW_TYPE_DOCK.
# Заголовок "Eww - island" как критерий не используется: он задаётся в конфиге
# и может измениться, а PID+тип однозначны.
#
# usage: island-geom.sh [xid]
#   без аргументов - печатает: <xid> <x> <y> <w> <h>
#   с аргументом "xid" - печатает только XID
#   с аргументом "pid" - печатает только PID демона
#   ничего не нашёл - пустой вывод, код 1
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
CONF="$ROOT/eww"
EWW="$ROOT/build/target/release/eww"

. "$ROOT/lib/eww-proc.sh"

# --- PID демона Eww для нашего конфига ---
# Через lib/eww-proc.sh: он приводит --config к абсолютному пути, иначе демон,
# запущенный как `eww --config eww daemon` (относительный путь), не находится,
# и остров считается не запущенным при живом окне на экране.
daemon_pid() {
  eww_daemon_pids "$CONF" | head -1
}

# --- XID окна острова ---
island_xid() {
  pid=$1
  xprop -root _NET_CLIENT_LIST 2>/dev/null \
    | sed 's/.*# //; s/,//g' \
    | tr ' ' '\n' \
    | while read -r w; do
        [ -n "$w" ] || continue
        wpid=$(xprop -id "$w" _NET_WM_PID 2>/dev/null \
          | sed -n 's/.*= *\([0-9]\+\)$/\1/p')
        [ "$wpid" = "$pid" ] || continue
        wtype=$(xprop -id "$w" _NET_WM_WINDOW_TYPE 2>/dev/null || true)
        case "$wtype" in
          *_NET_WM_WINDOW_TYPE_DOCK*) echo "$w"; break ;;
        esac
      done
}

# Запасной поиск: некоторые сборки Eww не выставляют _NET_WM_PID на окне, и
# тогда первый путь не находит ничего (со стороны это «окно не появилось»,
# хотя оно на экране). Ищем по заголовку из eww.yuck и типу DOCK, а PID
# проверяем только если он вообще есть на окне: чужой DOCK с тем же
# заголовком практически невозможен, а окно без PID - обычное дело.
island_xid_by_title() {
  pid=$1
  xprop -root _NET_CLIENT_LIST 2>/dev/null \
    | sed 's/.*# //; s/,//g' \
    | tr ' ' '\n' \
    | while read -r w; do
        [ -n "$w" ] || continue
        name=$(xprop -id "$w" WM_NAME 2>/dev/null || true)
        case "$name" in
          *'"Eww - island"'*) ;;
          *) continue ;;
        esac
        wtype=$(xprop -id "$w" _NET_WM_WINDOW_TYPE 2>/dev/null || true)
        case "$wtype" in
          *_NET_WM_WINDOW_TYPE_DOCK*) ;;
          *) continue ;;
        esac
        wpid=$(xprop -id "$w" _NET_WM_PID 2>/dev/null \
          | sed -n 's/.*= *\([0-9]\+\)$/\1/p')
        if [ -z "$wpid" ] || [ "$wpid" = "$pid" ]; then
          echo "$w"; break
        fi
      done
}

# find_island_xid <pid...> - XID окна острова у любого из демонов.
# Несколько PID - не редкость: демон, запущенный с относительным --config,
# слушает другой сокет, но окно на экране держит тоже. Тогда достаточно
# найти хоть одно окно острова, чтобы знать геометрию.
find_island_xid() {
  for _pid in "$@"; do
    _x=$(island_xid "$_pid")
    [ -n "$_x" ] || _x=$(island_xid_by_title "$_pid")
    if [ -n "$_x" ]; then
      printf '%s\n' "$_x"
      return 0
    fi
  done
  return 1
}

pid=$(daemon_pid || true)
[ -n "$pid" ] || exit 1

case "${1:-}" in
  pid)
    echo "$pid"
    exit 0
    ;;
  xid)
    find_island_xid $(eww_daemon_pids "$CONF") || exit 1
    exit 0
    ;;
esac

xid=$(find_island_xid $(eww_daemon_pids "$CONF")) || exit 1

# Геометрия окна: wmctrl отдаёт координаты клиентской области (рамка у окон Eww нулевая).
# XID сравниваем как числа: xprop печатает 0x3200029, wmctrl - 0x03200029.
want=$((xid))
geo=$(wmctrl -lG 2>/dev/null | awk -v w="$want" '{ id = strtonum("0x" substr($1, 3)); if (id == w) {print $3, $4, $5, $6; exit} }')
[ -n "$geo" ] || exit 1

echo "$xid $geo"
