#!/bin/sh
# true/false при каждом изменении: открыта ли какая-либо панель Eww.
last=""
emit() {
  # Панель таймера уже острова и висит по центру: нижние углы острова при ней
  # остаются круглыми (прямыми их делают только панели во всю ширину).
  if wmctrl -l 2>/dev/null | grep ' Eww - panel-' | grep -qv 'panel-timer'; then s=true; else s=false; fi
  [ "$s" = "$last" ] || { echo "$s"; last=$s; }
}
emit
xprop -spy -root _NET_CLIENT_LIST | while read -r _; do emit; done
