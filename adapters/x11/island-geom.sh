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

# --- PID демона Eww для нашего конфига ---
daemon_pid() {
  for p in /proc/[0-9]*; do
    [ -r "$p/cmdline" ] || continue
    cmd=$(tr '\0' ' ' < "$p/cmdline" 2>/dev/null || true)
    case "$cmd" in
      *"--config $CONF daemon"*) echo "${p#/proc/}"; return 0 ;;
    esac
  done
  return 1
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

pid=$(daemon_pid || true)
[ -n "$pid" ] || exit 1

case "${1:-}" in
  pid)
    echo "$pid"
    exit 0
    ;;
  xid)
    xid=$(island_xid "$pid")
    [ -n "$xid" ] || exit 1
    echo "$xid"
    exit 0
    ;;
esac

xid=$(island_xid "$pid")
[ -n "$xid" ] || exit 1

# Геометрия окна: wmctrl отдаёт координаты клиентской области (рамка у окон Eww нулевая).
# XID сравниваем как числа: xprop печатает 0x3200029, wmctrl - 0x03200029.
want=$((xid))
geo=$(wmctrl -lG 2>/dev/null | awk -v w="$want" '{ id = strtonum("0x" substr($1, 3)); if (id == w) {print $3, $4, $5, $6; exit} }')
[ -n "$geo" ] || exit 1

echo "$xid $geo"
