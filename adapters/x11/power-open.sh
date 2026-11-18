#!/bin/sh
# true/false при каждом изменении: открыто ли меню питания (panel-power).
#
# Зачем отдельно от panel-open.sh: у panel_open общий смысл "открыта любая
# панель", а кнопке питания нужно знать про СВОЁ окно. Плюс меню можно
# закрыть кликом по рабочему столу (unfocus-close в окне) - тогда panel.sh
# не вызывается вообще, и снять подсветку может только наблюдатель.
#
# Механизм тот же, что у panel-open.sh: xprop -spy на _NET_CLIENT_LIST,
# проверка по заголовку окна. Заголовок "Eww - panel-power" задаёт Eww по
# имени окна в конфиге.
last=""
emit() {
  if wmctrl -l 2>/dev/null | grep -q ' Eww - panel-power$'; then s=true; else s=false; fi
  [ "$s" = "$last" ] || { echo "$s"; last=$s; }
}
emit
xprop -spy -root _NET_CLIENT_LIST | while read -r _; do emit; done
