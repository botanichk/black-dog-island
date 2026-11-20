#!/bin/sh
# Выпадающая панель под островом, по его центру.
# Повторный запуск для уже открытой панели закрывает её.
# usage: panel.sh <окно> [примерная ширина]
#        panel.sh panel-hub <home|calendar|weather|wifi|shot|media>
# Ширину задаёт panel.sh (по острову), высоту - содержимое.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
EWW="$ROOT/build/target/release/eww"
CONF="$ROOT/eww"

[ -n "${1:-}" ] || { echo "usage: panel.sh <window> [width] | panel.sh panel-hub <home|calendar|weather|wifi|shot>" >&2; exit 2; }
NAME=$1
# Для хаба второй аргумент - вкладка, ширина не нужна (берётся с острова).
HUB_TAB=${2:-}
TITLE="Eww - $NAME"

# Печатает "x y w h" окна с таким заголовком (пусто, если окна нет).
win_geo() {
  wmctrl -lG 2>/dev/null | awk -v t="$1" '$0 ~ (t "$") {print $3, $4, $5, $6; exit}'
}

# Имя вкладки хаба -> индекс стека hub_tab (0..5). Медиа - 5, чтобы не
# сдвигать остальные вкладки (индексы хранятся цифрами в адаптерах).
tab_index() {
  case "$1" in
    home)     echo 0 ;;
    calendar) echo 1 ;;
    weather)  echo 2 ;;
    wifi)     echo 3 ;;
    shot)     echo 4 ;;
    media)    echo 5 ;;
    colors)   echo 6 ;;
    *)        echo "" ;;
  esac
}

IDX=
if [ "$NAME" = "panel-hub" ]; then
  IDX=$(tab_index "${HUB_TAB:-}")
  [ -n "$IDX" ] || { echo "ошибка: неизвестная вкладка хаба '${HUB_TAB:-}'" >&2; exit 2; }
fi

# Меню питания (panel-power): подсветку кнопки на острове и прямые углы ведёт
# power-open.sh - deflisten следит за окном и снимает состояние сам, в том
# числе когда меню закрыли кликом по рабочему столу (unfocus-close), а panel.sh
# при этом не вызывался. Здесь это состояние не трогаем.
#
# Таймер (panel-timer): подсветку кнопки даёт timer-state, отдельного
# наблюдателя не нужно - кнопка живёт на данных таймера.

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
  # Закрытие: углы острова возвращаются круглыми сразу. panel_open придёт в
  # false от panel-open.sh через ~0.5-1 с, но hub_opening держит прямые углы
  # только пока идёт ОТКРЫТИЕ - здесь его снимаем, иначе остров остался бы
  # с прямыми углами до следующего события.
  "$EWW" --config "$CONF" update hub_opening=false 2>/dev/null || true
  "$EWW" --config "$CONF" close "$NAME"
  exit 0
fi

# --- открытие ---
# Два окна под островом одновременно не нужны: меню питания рисует свою рамку
# на всю ширину острова, и вместе с хабом они накладывались бы друг на друга.
# Поэтому при открытии одного закрываем остальные. panel.sh для закрываемого
# окна не зовём (он бы отработал как "повторный клик" и вышел) - просто close.
for other in panel-hub panel-power panel-timer; do
  if [ "$other" != "$NAME" ]; then
    "$EWW" --config "$CONF" close "$other" 2>/dev/null || true
  fi
done
if [ "$NAME" != "panel-hub" ]; then
  "$EWW" --config "$CONF" update hub_opening=false 2>/dev/null || true
fi

# Нижние углы острова становятся прямыми СРАЗУ при клике, а не когда
# panel-open.sh увидит новое окно в _NET_CLIENT_LIST (это до 1 с, а вместе с
# расстановкой окна xfwm4 выходило до 3 с). hub_opening=true ставим ДО open.
# Сбрасываем его в любом исходе - и в успешном, и в аварийном (trap EXIT):
# если скрипт упадёт между "true" и "false", остров навсегда останется с
# прямыми углами. Сброс delay'ится на 0.5 с ПОСЛЕ появления окна, чтобы
# panel-open.sh успел выставить panel_open=true и между двумя сигналами не
# было вспышки круглых углов.
HUB_OPENING_SET=0
reset_hub_opening() {
  [ "$HUB_OPENING_SET" -eq 1 ] || return 0
  HUB_OPENING_SET=0
  "$EWW" --config "$CONF" update hub_opening=false 2>/dev/null || true
}
trap reset_hub_opening EXIT INT TERM HUP

if [ "$NAME" = "panel-hub" ]; then
  "$EWW" --config "$CONF" update hub_opening=true 2>/dev/null || true
  HUB_OPENING_SET=1
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

# X панели - по левому краю острова, ширина - как у острова.
X=$IX
[ "$X" -ge 0 ] || X=0

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

# Окно на месте. Снимаем hub_opening: остров снова слушает только panel_open.
# 0.5 с - запас на то, чтобы panel-open.sh (xprop -spy на _NET_CLIENT_LIST)
# успел выставить panel_open=true. Без этой паузы между "hub_opening=false" и
# "panel_open=true" был бы момент, когда оба false, и нижние углы острова
# мигнули бы круглыми. Если panel_open не успел - остров останется с прямыми
# углами ещё на мгновение, это лучше вспышки.
if [ "$HUB_OPENING_SET" -eq 1 ]; then
  sleep 0.5
  reset_hub_opening
fi
