#!/bin/sh
# from-wallpaper.sh - палитра из обоев текущего рабочего стола.
#
# usage: theme/from-wallpaper.sh [m3-схема] [dark|light] [--reload]
#        theme/from-wallpaper.sh                      # m3-tonal-spot, режим из theme/mode
#        theme/from-wallpaper.sh vibrant light        # конкретная схема и режим
#
# Почему это работает без Noctalia-демона: `noctalia theme <картинка>` умеет
# считать палитру отдельным вызовом, Wayland и демон ему не нужны (проверено,
# мы на X11). Демона у нас нет, `noctalia msg` отвечает "not running".
#
# Список схем - из текста ошибки самого noctalia, других значений он не
# принимает: m3-fidelity, m3-neutral, m3-vibrant, m3-expressive НЕ существуют.
#
# Обои берём у ТЕКУЩЕГО рабочего стола: у каждого стола в XFCE свой
# last-image. Монитор в ключе не хардкодим (monitorLVDS-1 может смениться) -
# перебираем ключи и сверяем номер стола.
#
# Зависимости только из системы: sh, python3, xfconf-query, xprop, noctalia.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

SCHEME="m3-tonal-spot"
MODE=""
RELOAD=0
for arg in "$@"; do
  case "$arg" in
    --reload) RELOAD=1 ;;
    -*) echo "неизвестный аргумент: $arg" >&2; exit 2 ;;
    *)
      if [ -z "$MODE" ] && { [ "$arg" = "dark" ] || [ "$arg" = "light" ]; }; then
        MODE=$arg
      elif [ "$SCHEME" = "m3-tonal-spot" ]; then
        SCHEME=$arg
      else
        echo "лишний аргумент: $arg" >&2; exit 2
      fi ;;
  esac
done

case "$SCHEME" in
  m3-tonal-spot|m3-content|m3-fruit-salad|m3-rainbow|m3-monochrome|\
  vibrant|faithful|soft|dysfunctional|muted) ;;
  *) echo "неизвестная схема: $SCHEME (есть: m3-tonal-spot, m3-content,
m3-fruit-salad, m3-rainbow, m3-monochrome, vibrant, faithful, soft,
dysfunctional, muted)" >&2; exit 2 ;;
esac

if [ -z "$MODE" ]; then
  MODE=$(tr -d ' \t\r\n' < "$ROOT/theme/mode" 2>/dev/null || true)
  MODE=${MODE:-dark}
fi

command -v noctalia >/dev/null 2>&1 || {
  echo "нет команды noctalia (пакет noctalia не установлен)" >&2; exit 4; }
command -v xfconf-query >/dev/null 2>&1 || {
  echo "нет xfconf-query (пакет xfconf)" >&2; exit 4; }

# --- 1. обои текущего стола -----------------------------------------------
ws=$(xprop -root _NET_CURRENT_DESKTOP 2>/dev/null | sed -n 's/.*= *//p')
ws=${ws:-0}

wallpaper_of() {
  # $1 - номер стола; печатает первый непустой путь
  xfconf-query -c xfce4-desktop -l 2>/dev/null \
    | grep "/workspace$1/last-image$" \
    | while read -r prop; do
        value=$(xfconf-query -c xfce4-desktop -p "$prop" 2>/dev/null || true)
        if [ -n "$value" ] && [ -f "$value" ]; then
          printf '%s\n' "$value"
          break
        fi
      done
}

WALL=$(wallpaper_of "$ws")
if [ -z "$WALL" ] && [ "$ws" != "0" ]; then
  # у стола может не быть своих обоев - берём общие с первого
  WALL=$(wallpaper_of 0)
fi
[ -n "$WALL" ] || {
  echo "у этого рабочего стола нет обоев в настройках XFCE" >&2; exit 3; }

# --- 2. палитра от noctalia ----------------------------------------------
TMP=$(mktemp "${TMPDIR:-/tmp}/eww-island-wall.XXXXXX.json")
trap 'rm -f "$TMP"' EXIT

# При ошибке noctalia пишет в stderr и оставляет stdout пустым, код 1 -
# это проверено, поэтому пустой файл = провал (без разбора текста ошибки).
if ! noctalia theme "$WALL" --scheme "$SCHEME" --both >"$TMP" 2>"$TMP.err"; then
  echo "noctalia не смогла прочитать обои: $WALL" >&2
  sed 's/^/  /' "$TMP.err" >&2 || true
  rm -f "$TMP.err"
  exit 1
fi
rm -f "$TMP.err"
[ -s "$TMP" ] || { echo "noctalia вернула пустой ответ для $WALL" >&2; exit 1; }

# --- 3. схема -------------------------------------------------------------
python3 "$ROOT/theme/palette2scheme.py" --theme-json "$TMP" --mode "$MODE" \
  --out "$ROOT/theme/schemes/wallpaper.json" >/dev/null

# --- 4. применить ---------------------------------------------------------
if [ "$RELOAD" -eq 1 ]; then
  "$ROOT/theme/apply.sh" wallpaper --reload
else
  "$ROOT/theme/apply.sh" wallpaper
fi
printf '%s\n' "$MODE" > "$ROOT/theme/mode"
# Какая m3-схема выбрана: без этого смена режима пересобирала обои со
# «Спокойной», затирая «Яркую»/«Мягкую»/«Тихую» (проверено).
printf '%s\n' "$SCHEME" > "$ROOT/theme/wallpaper-scheme"

echo "обои: $WALL"
echo "схема: $SCHEME, режим: $MODE"
