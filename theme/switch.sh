#!/bin/sh
# switch.sh - переключить схему темы и применить её.
#
# usage: theme/switch.sh              # следующая схема по кругу
#        theme/switch.sh light        # конкретная схема
#        theme/switch.sh --no-reload  # только файлы и ~/.config/bdi/current
#
# Почему не просто apply.sh: reload закрывает окно хаба и сбрасывает hub_tab
# на 0 (проверено). Здесь после применения скрипт сам переоткрывает хаб на
# той же вкладке и с теми же координатами через adapters/x11/panel.sh.
#
# Порядок схем для перебора - theme/schemes/*.json, отсортированные по имени;
# default всегда первая, чтобы переключение из light вело обратно в default.
# Схемы палитр (p-*, u-*, wallpaper) в перебор не входят: они выводятся из
# палитры и режима, их выбор живёт во вкладке «Цвета» (theme/colors-pick.sh).
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BDI_CONFIG="${BDI_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/bdi}"
BDI_STATE="${BDI_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/bdi}"
EWW="$ROOT/build/target/release/eww"
PANEL="$ROOT/adapters/x11/panel.sh"

RELOAD=1
WANT=""
for arg in "$@"; do
  case "$arg" in
    --no-reload) RELOAD=0 ;;
    -*) echo "неизвестный аргумент: $arg" >&2; exit 2 ;;
    *)
      [ -z "$WANT" ] || { echo "лишний аргумент: $arg" >&2; exit 2; }
      WANT=$arg ;;
  esac
done

# Список схем: default первой, остальные по алфавиту.
SCHEMES=$( { echo default; ls "$ROOT/theme/schemes" \
  | sed 's/\.json$//' \
  | grep -v -e '^default$' -e '^p-' -e '^u-' -e '^wallpaper$' \
  | sort; } | tr '\n' ' ')
CUR=$(tr -d ' \t\r\n' < "$BDI_CONFIG/current" 2>/dev/null || echo default)
[ -n "$CUR" ] || CUR=default

# Следующая схема после CUR в списке (по кругу).
next_scheme() {
  prev=""
  first=""
  for s in $SCHEMES; do
    [ -n "$first" ] || first=$s
    if [ "$prev" = "$CUR" ]; then echo "$s"; return; fi
    prev=$s
  done
  echo "$first"
}

[ -n "$WANT" ] || WANT=$(next_scheme)
{ [ -f "$ROOT/theme/schemes/$WANT.json" ] || [ -f "$BDI_STATE/schemes/$WANT.json" ]; } || {
  echo "нет схемы: $WANT (есть: $SCHEMES)" >&2; exit 2; }

# Что сейчас открыто: вкладка хаба и была ли панель вообще.
was_open=false
tab=home
if wmctrl -l 2>/dev/null | grep -q ' Eww - panel-hub'; then
  was_open=true
  idx=$("$EWW" --config "$ROOT/eww" state 2>/dev/null | awk -F': ' '$1=="hub_tab"{print $2; exit}')
  case "${idx:-0}" in
    0) tab=home ;; 1) tab=calendar ;; 2) tab=weather ;;
    3) tab=wifi ;; 4) tab=shot ;; 5) tab=media ;; 6) tab=colors ;;
    *) tab=home ;;
  esac
fi

if [ "$RELOAD" -eq 1 ]; then
  "$ROOT/theme/apply.sh" "$WANT" --reload || true
else
  "$ROOT/theme/apply.sh" "$WANT"
fi

# reload не закрывает хаб, а оставляет окно и переставляет его на y=230,
# сбрасывая hub_tab на 0 (проверено). Поэтому окно закрываем сами, ждём,
# пока оно исчезнет, и открываем заново через panel.sh: он берёт x/ширину от
# острова, ставит y=50 и запрашивает нужную вкладку.
if [ "$RELOAD" -eq 1 ] && [ "$was_open" = true ]; then
  "$EWW" --config "$ROOT/eww" close panel-hub >/dev/null 2>&1 || true
  i=0
  while wmctrl -l 2>/dev/null | grep -q ' Eww - panel-hub' && [ "$i" -lt 30 ]; do
    sleep 0.1; i=$((i + 1))
  done
  "$PANEL" panel-hub "$tab" >/dev/null 2>&1 || true
  i=0
  while ! wmctrl -l 2>/dev/null | grep -q ' Eww - panel-hub' && [ "$i" -lt 40 ]; do
    sleep 0.1; i=$((i + 1))
  done
  # panel.sh держит позицию ~1.5 с; даём ему закончить и не спорим с ним.
  sleep 0.4
fi

echo "тема: $WANT"
