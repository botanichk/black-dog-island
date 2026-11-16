#!/bin/sh
# Выпадающая панель под островом, по его центру.
# Повторный запуск для уже открытой панели закрывает её.
# usage: panel.sh <окно> [примерная ширина]
#        panel.sh panel-hub <calendar|weather|wifi|shot>
# Ширину задаёт panel.sh (по острову), высоту - содержимое.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
EWW="$ROOT/build/target/release/eww"
CONF="$ROOT/eww"

[ -n "${1:-}" ] || { echo "usage: panel.sh <window> [width] | panel.sh panel-hub <calendar|weather|wifi|shot>" >&2; exit 2; }
NAME=$1
# Для хаба второй аргумент - вкладка, ширина не нужна (берётся с острова).
HUB_TAB=${2:-}
GUESS=${2:-300}
TITLE="Eww - $NAME"

# Печатает "x y w h" окна с таким заголовком (пусто, если окна нет).
win_geo() {
  wmctrl -lG 2>/dev/null | awk -v t="$1" '$0 ~ (t "$") {print $3, $4, $5, $6; exit}'
}

# Имя вкладки хаба -> индекс стека hub_tab (0..3).
tab_index() {
  case "$1" in
    calendar) echo 0 ;;
    weather)  echo 1 ;;
    wifi)     echo 2 ;;
    shot)     echo 3 ;;
    *)        echo "" ;;
  esac
}

IDX=
if [ "$NAME" = "panel-hub" ]; then
  IDX=$(tab_index "${HUB_TAB:-}")
  [ -n "$IDX" ] || { echo "ошибка: неизвестная вкладка хаба '${HUB_TAB:-}'" >&2; exit 2; }
fi

# Панель уже открыта:
#  - хаб на другой вкладке - только переключить вкладку, окно не пересоздавать;
#  - на той же вкладке (или не хаб) - закрыть, повторный клик закрывает.
if [ -n "$(win_geo "$TITLE")" ]; then
  if [ "$NAME" = "panel-hub" ]; then
    CUR=$("$EWW" --config "$CONF" state --all | awk -F': ' '$1 == "hub_tab" {print $2; exit}')
    if [ "$CUR" != "$IDX" ]; then
      "$EWW" --config "$CONF" update hub_tab="$IDX"
      exit 0
    fi
  fi
  "$EWW" --config "$CONF" close "$NAME"
  exit 0
fi

# Хаб открываем на запрошенной вкладке.
if [ -n "$IDX" ]; then
  "$EWW" --config "$CONF" update hub_tab="$IDX"
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
# --no-daemonize: если демон недоступен - ошибка, а не молчаливый запуск
# второго демона (клиент open умеет сам форкать демона - получались клоны).
# Ошибку клиента здесь не считаем фатальной: Eww 0.6 иногда не дочитывает
# ответ демона ("Error reading response from server", os error 11), при этом
# окно уже создано. Раньше set -e обрывал скрипт на этой строке, до ожидания
# окна и правки позиции, и xfwm4 оставлял панель там, куда поставил сам
# (y=230). Если окна действительно нет, ошибку выдаст ожидание ниже.
"$EWW" --config "$CONF" --no-daemonize open "$NAME" --arg "w=${IW}px" --pos "${X}x${Y}" || true

# Ждём появления окна (до 3 с).
i=0; geo=
while [ -z "$geo" ] && [ "$i" -lt 30 ]; do
  geo=$(win_geo "$TITLE")
  [ -n "$geo" ] || { sleep 0.1; i=$((i + 1)); }
done
[ -n "$geo" ] || { echo "ошибка: панель $NAME не появилась" >&2; exit 1; }

# xfwm4 может переставить окно после открытия: держим позицию, пока она не
# продержится 15 проверок подряд (~1.5 с). Трёх проверок не хватало: если окно
# появлялось позже или xfwm4 применял свою расстановку с задержкой, скрипт уже
# выходил, и панель оставалась на y=230. Размер не трогаем: ширину окно
# получило при открытии (аргумент [w]), а минимум контента GTK всё равно
# сильнее wmctrl.
ok=0; i=0; final_x=0; final_y=0
while [ "$ok" -lt 15 ] && [ "$i" -lt 30 ]; do
  set -- $(win_geo "$TITLE")
  [ "$#" -eq 4 ] || break
  if [ "$1" -eq "$X" ] && [ "$2" -eq "$Y" ]; then
    ok=$((ok + 1))
  else
    ok=0
    wmctrl -r "$TITLE" -e "0,$X,$Y,-1,-1" 2>/dev/null || true
  fi
  final_x=$1; final_y=$2
  i=$((i + 1))
  sleep 0.1
done

# Контрольная проверка после выхода: если xfwm4 переставил окно в последний
# момент, поправляем ещё раз и даём позиции 0.3 с устояться.
set -- $(win_geo "$TITLE")
if [ "$#" -eq 4 ]; then
  if [ "$1" -ne "$X" ] || [ "$2" -ne "$Y" ]; then
    wmctrl -r "$TITLE" -e "0,$X,$Y,-1,-1" 2>/dev/null || true
    sleep 0.3
    set -- $(win_geo "$TITLE")
    [ "$#" -eq 4 ] || { echo "ошибка: панель $NAME исчезла при проверке позиции" >&2; exit 1; }
    final_x=$1; final_y=$2
  fi
  if [ "$1" -ne "$X" ] || [ "$2" -ne "$Y" ]; then
    echo "предупреждение: позиция панели $NAME не устоялась (фактически: ${final_x}x${final_y}, ожидалось: ${X}x${Y})" >&2
  fi
fi
