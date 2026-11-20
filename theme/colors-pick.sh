#!/bin/sh
# colors-pick.sh - одна точка входа для вкладки «Цвета».
#
# usage: theme/colors-pick.sh palette <id> [dark|light]
#        theme/colors-pick.sh mode <dark|light>
#        theme/colors-pick.sh wallpaper [m3-схема]
#        theme/colors-pick.sh reset
#        theme/colors-pick.sh open-palettes   (открыть папку своих палитр)
#        theme/colors-pick.sh path [<id>]     (файл палитры действующей темы)
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
  echo "usage: colors-pick.sh palette <id> [dark|light] | accent <primary|secondary|tertiary> | hue <all|green|blue|warm|gray> | mode <dark|light> | wallpaper [схема] | reset | open-palettes" >&2
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

# Какой акцент выбран (theme/accent, вне git). Пусто = primary: без выбора
# внешний вид не меняется, как было до шага 1.
read_accent() {
  a=$(tr -d ' \t\r\n' < "$THEME/accent" 2>/dev/null || true)
  case "$a" in secondary|tertiary) echo "$a" ;; *) echo primary ;; esac
}

write_accent() { printf '%s\n' "$1" > "$THEME/accent"; }

read_current() {
  tr -d ' \t\r\n' < "$THEME/current" 2>/dev/null || echo default
}

# Какая m3-схема выбрана для обоев (theme/wallpaper-scheme). Нужна при смене
# режима: иначе обои пересобираются со «Спокойной», затирая выбор.
read_wall_scheme() {
  s=$(tr -d ' \t\r\n' < "$THEME/wallpaper-scheme" 2>/dev/null || true)
  printf '%s\n' "${s:-m3-tonal-spot}"
}

# Путь к файлу палитры по id схемы: p-<слаг> -> theme/palettes, u-<слаг> ->
# ~/.config/noctalia/palettes. Нужен при смене режима: theme/current хранит
# id схемы, а неисходный файл, и без этого «перекрасить в светлую» не знает,
# откуда брать палитру.
resolve_source() {
  case "$1" in
    p-*)
      src="$THEME/palettes/${1#p-}.json"
      # return 0 обязателен: без него функция доходит до return 1 в конце и
      # вызывающий считает, что палитры нет. Из-за этого «акцент» и «режим»
      # молча не пересобирали схему у встроенных палитр (проверено sh -x:
      # путь печатался, следом шёл return 1).
      if [ -f "$src" ]; then
        printf '%s\n' "$src"
        return 0
      fi ;;
    u-*)
      for path in "$HOME"/.config/noctalia/palettes/*.json; do
        [ -f "$path" ] || continue
        stem=$(basename "$path" .json)
        if python3 -c "import sys; sys.path.insert(0,'$THEME'); import palette_lib as p; sys.exit(0 if 'u-' + p.slug_unique(sys.argv[1]) == sys.argv[2] else 1)" "$stem" "$1"; then
          printf '%s\n' "$path"
          return 0
        fi
      done ;;
    c-*)
      # Каталог сообщества: id -> файл через ту же read_community, что строит
      # список для вкладки. Через slug_unique(stem) нельзя: имена файлов
      # закодированы (Catppuccin%20Mocha%20Green.json), и слаг вышел бы
      # «catppuccin-20mocha-20green» вместо «catppuccin-mocha-green».
      src=$(python3 -c "import sys; sys.path.insert(0,'$THEME'); import palette_lib as p; print(next((str(f) for cid, _, f in p.read_community() if cid == sys.argv[1]), ''))" "$1")
      if [ -n "$src" ]; then
        printf '%s\n' "$src"
        return 0
      fi ;;
  esac
  return 1
}

# --- 1. выбрать цель: имя схемы, которую применим -------------------------
SCHEME=""
NEED_BUILD=""       # пусто | "palette:<файл>" | "wallpaper"

case "$ACTION" in
  # Путь к файлу палитры: без аргумента - у действующей темы, с аргументом -
  # у указанного id. Нужен theme/theme-save.sh, чтобы не повторять поиск файла.
  path)
    [ -n "$ARG" ] || ARG=$(read_current)
    resolve_source "$ARG" || { echo "нет файла палитры для '$ARG'" >&2; exit 1; }
    exit 0 ;;

  # Открыть папку своих палитр: рядом с полем названия во вкладке «Цвета».
  # Менеджер берём по умолчанию (xdg-open), а не наутилус жёстко: у разных
  # людей разные файловые менеджеры. У владельца xdg-open ведёт в наутилус.
  open-palettes)
    dir="$HOME/.config/noctalia/palettes"
    mkdir -p "$dir"
    if command -v xdg-open >/dev/null 2>&1; then
      setsid xdg-open "$dir" >/dev/null 2>&1 &
    else
      setsid nautilus "$dir" >/dev/null 2>&1 &
    fi
    echo "открыто: $dir"
    exit 0 ;;

  reset)
    SCHEME="default"
    write_mode dark
    write_accent primary
    ;;

  # Сменить акцент у действующей палитры. Палитра та же, меняется только
  # роль primary острова - поэтому схема пересобирается из того же файла.
  accent)
    case "$ARG" in
      primary|secondary|tertiary) ;;
      *) echo "accent: ожидалось primary, secondary или tertiary, получено '$ARG'" >&2; exit 2 ;;
    esac
    write_accent "$ARG"

    cur=$(read_current)
    case "$cur" in
      default|light)
        # у нашей схемы акцент один: перекрашивать нечего, честно скажем.
        # SCHEME всё равно заполняем - иначе ниже печатается «цвет:  (…)»
        # и apply.sh получает пустое имя.
        echo "у схемы «Остров» один акцент, менять не из чего" >&2
        SCHEME="$cur"
        ;;
      wallpaper)
        SCHEME="wallpaper"; NEED_BUILD="wallpaper" ;;
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

  # Фильтр оттенка каталога сообщества. Схему не трогает: пишет только
  # theme/hue-filter и перечитывает список - reload не нужен (проверено,
  # eww poll colors-list обновляет ряды за 0.04 с).
  hue)
    case "$ARG" in
      all|green|blue|warm|gray) ;;
      *) echo "hue: ожидалось all, green, blue, warm или gray, получено '$ARG'" >&2; exit 2 ;;
    esac
    printf '%s\n' "$ARG" > "$THEME/hue-filter"
    "$EWW" --config "$ROOT/eww" poll colors-list >/dev/null 2>&1 || true
    echo "оттенок: $ARG"
    exit 0
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
      u-*|c-*)
        # свои палитры и каталог сообщества: ищем файл по id
        found=$(resolve_source "$ARG") || found=""
        [ -n "$found" ] || { echo "нет палитры: $ARG" >&2; exit 2; }
        SCHEME="$ARG"
        NEED_BUILD="palette:$found"
        ;;
      *)
        echo "неизвестный id: $ARG (ожидалось n-island, p-*, u-*, c-*)" >&2; exit 2 ;;
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
      # ТУ ЖЕ m3-схему, что выбрана (theme/wallpaper-scheme), а не «Спокойную».
      "$THEME/from-wallpaper.sh" "$(read_wall_scheme)" "$(read_mode)" >/dev/null ;;
    palette:*)
      src=${NEED_BUILD#palette:}
      python3 "$THEME/palette2scheme.py" "$src" --mode "$(read_mode)" \
        --accent "$(read_accent)" \
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

# --- 4. закрыть хаб ДО reload ---------------------------------------------
# Почему до, а не после: reload пересоздаёт окно и оставляет старые
# экземпляры (проверено - после reload висело по два окна panel-hub, wmctrl
# правил только одно). Если закрыть заранее, reload нечего дублировать,
# и panel.sh открывает единственное окно. На клик выходит ~3 с вместо ~6.4:
# раньше 5.3 с из них уходило на закрытие уже пересозданного окна и ожидание.
if [ "$was_open" = true ]; then
  "$EWW" --config "$ROOT/eww" close panel-hub >/dev/null 2>&1 || true
  i=0
  while wmctrl -l 2>/dev/null | grep -q ' Eww - panel-hub' && [ "$i" -lt 20 ]; do
    sleep 0.05; i=$((i + 1))
  done
fi

# --- 5. применить ---------------------------------------------------------
"$THEME/apply.sh" "$SCHEME" --reload || true

# --- 6. открыть хаб на прежней вкладке ------------------------------------
if [ "$was_open" = true ]; then
  "$PANEL" panel-hub "$tab" >/dev/null 2>&1 || true
  i=0
  while ! wmctrl -l 2>/dev/null | grep -q ' Eww - panel-hub' && [ "$i" -lt 40 ]; do
    sleep 0.05; i=$((i + 1))
  done
  # panel.sh держит позицию ~1.5 с; не спорим с ним
  sleep 0.3
fi

echo "цвет: $SCHEME (режим $(read_mode))"
