#!/bin/sh
# true/false при каждом изменении: открыта ли какая-либо панель Eww.
last=""
emit() {
  if wmctrl -l 2>/dev/null | grep -q ' Eww - panel-'; then s=true; else s=false; fi
  [ "$s" = "$last" ] || { echo "$s"; last=$s; }
}
emit
xprop -spy -root _NET_CLIENT_LIST | while read -r _; do emit; done
