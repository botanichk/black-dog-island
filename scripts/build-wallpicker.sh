#!/bin/sh
# Сборка hypr-wallpicker из upstream с нашими патчами.
#
# Как scripts/build-eww.sh: патчи в patches/hypr-wallpicker-*.patch
# применяются поверх закреплённого коммита, повторный запуск безопасен.
#
# Порядок патчей важен: blur-backdrop правит те же файлы, что size-and-cancel,
# и встаёт только после него (проверено `git apply --check` 2026-11-21).
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SRC="$ROOT/build/wallpicker-src"
PATCHES="$ROOT/patches"

[ -d "$SRC" ] || { echo "нет исходников wallpicker: $SRC" >&2; exit 1; }
[ -f "$SRC/Makefile" ] || { echo "нет $SRC/Makefile" >&2; exit 1; }

# raylib лежит подмодулем: без него линковка падает на -lraylib.
if [ ! -f "$SRC/vendor/raylib/CMakeLists.txt" ]; then
  echo "подтягиваю raylib (98 МБ, один раз)"
  git -C "$SRC" submodule update --init --depth 1 2>&1 | sed 's/^/  /'
fi

cd "$SRC"

# Патчи по имени, а не по алфавиту: blur-backdrop должен идти после
# size-and-cancel. Явный список надёжнее сортировки.
#
# Дерево каждый раз собирается с нуля от пина: частично применённые патчи
# (и старые версии патчей после git pull) иначе не распознать - hunks
# перекрываются, reverse-check не работает. Прежние правки не теряем:
# сохраняем их в файл рядом.
if ! git diff --quiet -- src include; then
  bak="$SRC/patched-$(date +%Y%m%d-%H%M%S).diff"
  git diff -- src include > "$bak"
  echo "  прежние правки в дереве -> $bak, сбрасываю к пину"
  git checkout -- src include
fi

for p in "$PATCHES/hypr-wallpicker-size-and-cancel.patch" \
         "$PATCHES/hypr-wallpicker-blur-backdrop.patch"; do
  [ -f "$p" ] || { echo "нет патча $p" >&2; exit 1; }
  if ! git apply --check "$p"; then
    echo "ошибка: $(basename "$p") не встаёт на коммит $(git rev-parse --short HEAD)" >&2
    echo "  проверь пин в deps/wallpicker.txt" >&2
    exit 1
  fi
  git apply "$p"
  echo "  $(basename "$p"): применён"
done

echo "собираю (около 80 с на 4 ядрах)"
make 2>&1 | tail -20
[ -x "$SRC/wallpicker" ] || { echo "ошибка: бинарник не появился" >&2; exit 1; }
echo "готово: $SRC/wallpicker"
