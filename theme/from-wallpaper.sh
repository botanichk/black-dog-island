#!/bin/sh
# from-wallpaper.sh - палитра из обоев текущего рабочего стола.
#
# usage: theme/from-wallpaper.sh [m3-схема] [dark|light] [--reload]
#        theme/from-wallpaper.sh                      # m3-tonal-spot, режим из ~/.config/bdi/mode
#        theme/from-wallpaper.sh vibrant light        # конкретная схема и режим
#        theme/from-wallpaper.sh --name               # имя обоев, без обработки
#        theme/from-wallpaper.sh --path               # полный путь обоев
#
# Почему это работает без Noctalia-демона: `noctalia theme <картинка>` умеет
# считать палитру отдельным вызовом, Wayland и демон ему не нужны (проверено,
# мы на X11). Демона у нас нет, `noctalia msg` отвечает "not running".
#
# Список схем - из текста ошибки самого noctalia, других значений он не
# принимает: m3-fidelity, m3-neutral, m3-vibrant, m3-expressive НЕ существуют.
#
# Обои: у каждого стола в XFCE свой last-image, но есть режим
# /backdrop/single-workspace-mode - «одни обои на все столы». Когда он
# включён, xfdesktop рисует на всех столах обои стола
# /backdrop/single-workspace-number, а ключи остальных столов остаются
# старыми и на экран не влияют. Раньше мы читали ТЕКУЩИЙ стол и на столе 0
# отдавали «бурю», которой на экране не было (проверено замером: на экране
# был «Чёрный пёс на острове.png», Δ=3 по полосе y=4..46, а скрипт печатал
# «буря.jpeg»). Теперь режим учитываем.
#
# Монитор в ключе не хардкодим (monitorLVDS-1 может смениться) - перебираем
# ключи и сверяем номер стола.
#
# Зависимости только из системы: sh, python3, xfconf-query, xprop, noctalia.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BDI_CONFIG="${BDI_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/bdi}"
BDI_STATE="${BDI_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/bdi}"
mkdir -p "$BDI_CONFIG" "$BDI_STATE/schemes" 2>/dev/null || true

SCHEME="m3-tonal-spot"
MODE=""
RELOAD=0
NAME_ONLY=0
PATH_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --reload) RELOAD=1 ;;
    # --name печатает имя обоев текущего стола и выходит: вкладка «Цвета»
    # показывает его рядом с «С обоев», иначе непонятно, с каких обоев
    # считается палитра (владелец спросил «не видел работу с обоев»).
    --name) NAME_ONLY=1 ;;
    # --path печатает полный путь обоев: по нему wall-schemes.sh считает
    # хэш для кэша. Иначе поиск обоев пришлось бы дублировать вторым кодом.
    --path) PATH_ONLY=1 ;;
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
  MODE=$(tr -d ' \t\r\n' < "$BDI_CONFIG/mode" 2>/dev/null || true)
  MODE=${MODE:-dark}
fi

command -v noctalia >/dev/null 2>&1 || {
  echo "нет команды noctalia (пакет noctalia не установлен)" >&2; exit 4; }
command -v xfconf-query >/dev/null 2>&1 || {
  echo "нет xfconf-query (пакет xfconf)" >&2; exit 4; }

# --- 1. обои, которые реально на экране -----------------------------------
# Правило single-workspace-mode и перебор ключей живут в theme/desktop.sh:
# тот же файл использует хук выбора обоев (adapters/wallpicker/apply.sh),
# иначе две копии правила разъезжаются (уже разъехались: скрипт читал
# «бурю» со стола 0, а xfdesktop показывал обои стола 2).
. "$ROOT/theme/desktop.sh"

WALL=$(xfce_current_wallpaper)
[ -n "$WALL" ] || {
  echo "у этого рабочего стола нет обоев в настройках XFCE" >&2; exit 3; }

if [ "$NAME_ONLY" -eq 1 ]; then
  printf '%s\n' "$(basename -- "$WALL")"
  exit 0
fi
if [ "$PATH_ONLY" -eq 1 ]; then
  printf '%s\n' "$WALL"
  exit 0
fi

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
# Выбранный акцент (~/.config/bdi/accent) действует и для обоев: у M3-схемы есть все
# три роли, и человек вправе взять secondary вместо primary.
ACCENT=$(tr -d ' \t\r\n' < "$BDI_CONFIG/accent" 2>/dev/null || true)
case "$ACCENT" in secondary|tertiary) ;; *) ACCENT=primary ;; esac
python3 "$ROOT/theme/palette2scheme.py" --theme-json "$TMP" --mode "$MODE" \
  --accent "$ACCENT" \
  --out "$BDI_STATE/schemes/wallpaper.json" >/dev/null

# --- 4. применить ---------------------------------------------------------
if [ "$RELOAD" -eq 1 ]; then
  "$ROOT/theme/apply.sh" wallpaper --reload
else
  "$ROOT/theme/apply.sh" wallpaper
fi
printf '%s\n' "$MODE" > "$BDI_CONFIG/mode"
# Какая m3-схема выбрана: без этого смена режима пересобирала обои со
# «Спокойной», затирая «Яркую»/«Мягкую»/«Тихую» (проверено).
printf '%s\n' "$SCHEME" > "$BDI_CONFIG/wallpaper-scheme"

echo "обои: $WALL"
echo "схема: $SCHEME, режим: $MODE"
