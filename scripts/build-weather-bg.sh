#!/bin/sh
# Сборка фонов карточки погоды из исходников Qwen в assets/weather-src/.
#
# Исходники (16 PNG 1650x928 + preview.png) в git НЕ входят: папка
# eww/assets/weather-src/ в .gitignore. В репозиторий кладутся только
# готовые JPEG (eww/assets/wx-bg-<вид>.jpg), их и грузит Eww.
#
# Что делает: у каждой сцены отрезает нижние 8% по высоте (там у генератора
# стоял водяной знак), ужимает по ширине до 2х ширины карточки (660 px) и
# пишет прогрессивный JPEG. Пропорции после обрезки сохраняются, поэтому
# background-position 75% 50% в eww.yuck считается от одного и того же кадра.
#
# usage: scripts/build-weather-bg.sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SRC="$ROOT/eww/assets/weather-src"
DST="$ROOT/eww/assets"

[ -d "$SRC" ] || { echo "нет исходников: $SRC" >&2; exit 1; }
command -v magick >/dev/null 2>&1 || { echo "не найден magick (пакет imagemagick)" >&2; exit 1; }

# Нижние 8%: оставляем 92% сверху. -gravity north важен: без него ImageMagick
# центрирует рамку обрезки и съедает по 4% с обеих сторон.
n=0
for f in "$SRC"/wx-bg-*.png; do
  [ -e "$f" ] || { echo "в $SRC нет wx-bg-*.png" >&2; exit 1; }
  name=$(basename "$f" .png)
  out="$DST/$name.jpg"
  magick "$f" -gravity north -crop 100%x92%+0+0 +repage \
    -resize 660x -strip -interlace Plane -quality 88 "$out"
  n=$((n + 1))
  printf '%-26s -> %-28s %s\n' "$(basename "$f")" "$(basename "$out")" \
    "$(identify -format '%wx%h' "$out")"
done

printf 'готово: %s файлов в %s\n' "$n" "$DST"
