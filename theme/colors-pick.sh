#!/bin/sh
# colors-pick.sh - одна точка входа для вкладки «Цвета».
#
# usage: theme/colors-pick.sh palette <id> [dark|light]
#        theme/colors-pick.sh mode <dark|light>
#        theme/colors-pick.sh wallpaper [m3-схема]
#        theme/colors-pick.sh reset
#
# id - из theme/colors-list.sh: n-island (наши схемы), p-<слаг> (встроенная
# палитра Noctalia), u-<слаг> (своя палитра из ~/.config/noctalia/palettes).
#
# Почему обёртка над apply.sh: reload закрывает окно хаба и сбрасывает
# hub_tab на 0 (проверено). После применения скрипт сам переоткрывает хаб
# на вкладке «Цвета» - тем же приёмом, что theme/switch.sh.
#
# Зависимости только из системы: sh, python3. Ничего не ставим.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
EWW="$ROOT/build/target/release/eww"
PANEL="$ROOT/adapters/x11/panel.sh"
THEME="$ROOT/theme"

# --- разбор аргументов ----------------------------------------------------
ACTION=${1:-}
[ -n "$ACTION" ] || {
  echo "usage: colors-pick.sh palette <id> [dark|light] | mode <dark|light> | wallpaper [схема] | reset" >&2
  exit 2
}
shift || true

ARG=${1:-}
[ $# -gt 0 ] && shift || true
MODE=${1:-}
[ $# -gt 0 ] && shift || true
[ $# -eq 0 ] || { echo "лишний аргумент: $1" >&2; exit 2; }

read_mode() {
  m=$(tr -d ' \t\r\n' < "$THEME/mode" 2>/dev/null || true)
  case "$m" in light) echo light ;; *) echo dark ;; esac
}

write_mode() { printf '%s\n' "$1" > "$THEME/mode"; }

read_current() {
  tr -d ' \t\r\n' < "$THEME/current" 2>/dev/null || echo default
}

# Путь к файлу палитры по id схемы: p-<слаг> -> theme/palettes, u-<слаг> ->
# ~/.config/noctalia/palettes. Нужен при смене режима: theme/current хранит
# id схемы, а неисходный файл, и без этого «перекрасить в светлую» не знает,
# откуда брать палитру.
resolve_source() {
  case "$1" in
    p-*)
      src="$THEME/palettes/${1#p-}.json"
      [ -f "$src" ] && printf '%s\n' "$src" ;;
    u-*)
      for path in "$HOME"/.config/noctalia/palettes/*.json; do
        [ -f "$path" ] || continue
        stem=$(basename "$path" .json)
        if python3 -c "import sys; sys.path.insert(0,'$THEME'); import palette_lib as p; sys.exit(0 if 'u-' + p.slug_unique(sys.argv[1]) == sys.argv[2] else 1)" "$stem" "$1"; then
          printf '%s\n' "$path"
          return 0
        fi
      done ;;
  esac
  return 1
}

# --- 1. выбрать цель: имя схемы, которую применим -------------------------
SCHEME=""
NEED_BUILD=""       # пусто | "palette:<файл>" | "wallpaper"

case "$ACTION" in
  reset)
    SCHEME="default"
    write_mode dark
    ;;

  mode)
    case "$ARG" in
      dark|light) ;;
      *) echo "mode: ожидалось dark или light, получено '$ARG'" >&2; exit 2 ;;
    esac
    write_mode "$ARG"

    cur=$(read_current)
    case "$cur" in
      # наши собственные схемы: у них ровно два файла, отдельных режимов нет
      default|light)
        if [ "$ARG" = "light" ]; then SCHEME="light"; else SCHEME="default"; fi ;;
      wallpaper)
        SCHEME="wallpaper"; NEED_BUILD="wallpaper" ;;
      # палитра: пересобрать её же в новом режиме
      *)
        if src=$(resolve_source "$cur"); then
          NEED_BUILD="palette:$src"
          SCHEME="$cur"
        else
          echo "схема '$cur' есть, а палитры для неё не найти - оставляю как есть" >&2
          SCHEME="$cur"
        fi ;;
    esac
    ;;

  wallpaper)
    MODE=${MODE:-$(read_mode)}
    if [ -n "$ARG" ]; then
      "$THEME/from-wallpaper.sh" "$ARG" "$MODE"
      write_mode "$MODE"
      SCHEME="wallpaper"
    else
      SCHEME="wallpaper"; NEED_BUILD="wallpaper"
    fi
    ;;

  palette)
    [ -n "$ARG" ] || { echo "palette: нужен id из colors-list.sh" >&2; exit 2; }
    MODE=${MODE:-$(read_mode)}
    # режим применяется к любой палитре: и встроенной, и своей, и нашей
    write_mode "$MODE"

    case "$ARG" in
      n-island)
        # наши схемы до шага 11: default (тёмная) и light (светлая)
        if [ "$MODE" = "light" ]; then SCHEME="light"; else SCHEME="default"; fi
        write_mode "$MODE"
        ;;
      p-*)
        id=${ARG#p-}
        src="$THEME/palettes/$id.json"
        [ -f "$src" ] || { echo "нет встроенной палитры: $ARG (ожидался $src)" >&2; exit 2; }
        SCHEME="p-$id"
        NEED_BUILD="palette:$src"
        ;;
      u-*)
        # свои палитры: ищем файл, чей slug совпадает с хвостом id
        found=$(resolve_source "$ARG") || found=""
        [ -n "$found" ] || { echo "нет своей палитры: $ARG" >&2; exit 2; }
        SCHEME="$ARG"
        NEED_BUILD="palette:$found"
        ;;
      *)
        echo "неизвестный id: $ARG (ожидалось n-island, p-*, u-*)" >&2; exit 2 ;;
    esac
    ;;

  *)
    echo "неизвестное действие: $ACTION (ожидалось palette, mode, wallpaper, reset)" >&2
    exit 2 ;;
esac

# --- 2. собрать схему, если она выводится из палитры ----------------------
if [ -n "$NEED_BUILD" ]; then
  case "$NEED_BUILD" in
    wallpaper)
      # from-wallpaper.sh с явным режимом уже применяет схему и пишет mode;
      # сюда попадаем при смене режима у действующих обоев - пересобрать
      "$THEME/from-wallpaper.sh" m3-tonal-spot "$(read_mode)" >/dev/null ;;
    palette:*)
      src=${NEED_BUILD#palette:}
      python3 "$THEME/palette2scheme.py" "$src" --mode "$(read_mode)" \
        --out "$THEME/schemes/$SCHEME.json" >/dev/null ;;
  esac
fi

# --- 3. запомнить, что открыто (до reload: он сбросит hub_tab) ------------
# Вкладка «Цвета» = 6. Если хаб был открыт, вернём его сюда же.
was_open=false
tab=colors
if wmctrl -l 2>/dev/null | grep -q ' Eww - panel-hub'; then
  was_open=true
  idx=$("$EWW" --config "$ROOT/eww" state 2>/dev/null | awk -F': ' '$1=="hub_tab"{print $2; exit}')
  case "${idx:-6}" in
    0) tab=home ;; 1) tab=calendar ;; 2) tab=weather ;;
    3) tab=wifi ;; 4) tab=shot ;; 5) tab=media ;; *) tab=colors ;;
  esac
fi

# --- 4. применить ---------------------------------------------------------
"$THEME/apply.sh" "$SCHEME" --reload || true

# --- 5. вернуть хаб на прежнюю вкладку ------------------------------------
if [ "$was_open" = true ]; then
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
  # panel.sh держит позицию ~1.5 с; не спорим с ним
  sleep 0.4
fi

echo "цвет: $SCHEME (режим $(read_mode))"
