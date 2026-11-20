#!/bin/sh
# Снимок экрана для вкладки «Снимок» хаба (этап 6, шаг 3).
# usage: screenshot.sh area|window|screen [задержка 0|3|5]
#        screenshot.sh open|folder|copy
#
# area и window - один и тот же вызов import без -window: рамка мышью,
# клик по окну снимает окно. Разные только подписи в интерфейсе.
# Перед снимком хаб закрывается: иначе панель попадёт в кадр.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
EWW="$ROOT/build/target/release/eww"
CONF="$ROOT/eww"
SHOTS="$HOME/Pictures/Screenshots"
CACHE="${BDI_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/bdi}/thumbs"
LASTPATH="$CACHE/last_path.txt"

# Обновление переменных Eww: демон может быть не запущен, это не ошибка снимка.
eww_update() {
  "$EWW" --config "$CONF" update "$@" >/dev/null 2>&1 || true
}

mode=${1:-}
delay=${2:-0}

case "$mode" in
  open)
    # «Открыть»: последний снимок; если его уже нет - просто папка.
    last=
    [ -s "$LASTPATH" ] && last=$(cat "$LASTPATH")
    if [ -n "$last" ] && [ -f "$last" ]; then
      exec xdg-open "$last"
    fi
    exec xdg-open "$SHOTS" ;;
  folder)
    exec xdg-open "$SHOTS" ;;
  copy)
    # «Копировать»: последний снимок в буфер обмена как изображение.
    # xclip после чтения файла остаётся в памяти и отдаёт selection другим
    # приложениям, поэтому кнопка запускает скрипт через setsid -f: иначе Eww
    # убьёт команду по таймауту и буфер опустеет.
    last=
    [ -s "$LASTPATH" ] && last=$(cat "$LASTPATH")
    # Снимков ещё нет - ничего не делаем и не падаем.
    if [ -z "$last" ] || [ ! -s "$last" ]; then
      exit 0
    fi
    command -v xclip >/dev/null 2>&1 || { echo "xclip не установлен" >&2; exit 1; }
    exec xclip -selection clipboard -t image/png -i "$last" ;;
  area|window|screen) ;;
  *)
    echo "usage: screenshot.sh area|window|screen [0|3|5] | open | folder | copy" >&2
    exit 2 ;;
esac

case "$delay" in 0|3|5) ;; *) delay=0 ;; esac

# --- 1. Закрыть хаб, иначе он попадёт в кадр ---
if wmctrl -l 2>/dev/null | grep -q ' Eww - panel-'; then
  tab=$("$EWW" --config "$CONF" state --all 2>/dev/null \
        | awk -F': ' '$1 == "hub_tab" {print $2; exit}' || true)
  case "${tab:-0}" in
    0) name=home ;;
    1) name=calendar ;;
    2) name=weather ;;
    3) name=wifi ;;
    4) name=shot ;;
    *) name=home ;;
  esac
  # panel.sh на той же вкладке закрывает хаб; запасной путь - прямой close.
  "$ROOT/adapters/x11/panel.sh" panel-hub "$name" >/dev/null 2>&1 \
    || "$EWW" --config "$CONF" close panel-hub >/dev/null 2>&1 || true
  # Ждём, пока окно исчезнет из списка (до 1 с).
  i=0
  while wmctrl -l 2>/dev/null | grep -q ' Eww - panel-' && [ "$i" -lt 10 ]; do
    sleep 0.1
    i=$((i + 1))
  done
fi

# Пауза композитору: окно должно исчезнуть с экрана, а не только из wmctrl.
sleep 0.4

# --- 2. Задержка (0, 3 или 5 с) ---
[ "$delay" -gt 0 ] && sleep "$delay"

# --- 3. Снимок ---
mkdir -p "$SHOTS"
stamp=$(date '+%Y-%m-%d_%H-%M-%S')
file="$SHOTS/$stamp.png"

if [ "$mode" = screen ]; then
  import -window root "$file" 2>/dev/null || true
else
  # Интерактивно: рамка мышью или клик по окну, Esc отменяет.
  import "$file" 2>/dev/null || true
fi

# Отмена или пустой файл: убрать и миниатюру не трогать.
if [ ! -s "$file" ]; then
  rm -f "$file"
  echo "снимок отменён" >&2
  exit 1
fi

# --- 4. Миниатюра 160 px ---
mkdir -p "$CACHE"
magick "$file" -thumbnail 160x160 "$CACHE/last.png" 2>/dev/null || true
# Eww кеширует картинку по пути, поэтому у каждого снимка свой файл:
# last.png остаётся «последним» для внешних инструментов, last-<stamp>.png
# подставляется в интерфейс. Старые копии чистим, оставляем 5.
thumb="$CACHE/last-$stamp.png"
[ -f "$CACHE/last.png" ] && cp -f "$CACHE/last.png" "$thumb"
ls -1t "$CACHE"/last-*.png 2>/dev/null | tail -n +6 | while read -r old; do
  rm -f "$old"
done

printf '%s\n' "$file" > "$LASTPATH"

# --- 5. Обновить интерфейс без перезапуска ---
# shot_thumb - обычный путь к файлу, без file://: Eww читает картинку
# через gdk_pixbuf::from_file, URI он не понимает.
eww_update "shot_stamp=$stamp" "shot_thumb=$thumb"

printf '%s\n' "$file"
