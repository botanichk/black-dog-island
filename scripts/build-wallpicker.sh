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
for p in "$PATCHES/hypr-wallpicker-size-and-cancel.patch" \
         "$PATCHES/hypr-wallpicker-blur-backdrop.patch"; do
  [ -f "$p" ] || { echo "нет патча $p" >&2; exit 1; }
  name=$(basename "$p")
  if git apply --reverse --check "$p" 2>/dev/null; then
    echo "  $name: уже применён"
    continue
  fi
  if git apply --check "$p" 2>/dev/null; then
    echo "  $name: применяю"
    git apply "$p" || { echo "ошибка: не удалось применить $name" >&2; exit 1; }
  else
    echo "ошибка: $name не встаёт на этот коммит" >&2
    echo "  проверь пин в deps/wallpicker.txt" >&2
    exit 1
  fi
done

echo "собираю (около 80 с на 4 ядрах)"
make 2>&1 | tail -20
[ -x "$SRC/wallpicker" ] || { echo "ошибка: бинарник не появился" >&2; exit 1; }
echo "готово: $SRC/wallpicker"
