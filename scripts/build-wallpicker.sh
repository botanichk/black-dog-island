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
# Повторный запуск: reverse-check не годится - hunks патчей перекрываются,
# после полного применения reverse не встаёт. Проверяем след последнего
# патча (blur-backdrop) в дереве.
if grep -qs "scrim_percent" src/wallpaper.c; then
  # Фикс 2026-11-23: целочисленный crop. Его нет - в дереве патчи до него,
  # после git pull молча пересобирать старое нельзя.
  if ! grep -qsF "(int)((float)img.height * win_aspect)" src/wallpaper.c; then
    echo "ошибка: в дереве патчи без фикса crop, обнови их:" >&2
    echo "  git -C \"$SRC\" checkout -- src include" >&2
    echo "и запусти скрипт снова" >&2
    exit 1
  fi
  echo "  патчи уже применены, пропускаю"
else
  for p in "$PATCHES/hypr-wallpicker-size-and-cancel.patch" \
           "$PATCHES/hypr-wallpicker-blur-backdrop.patch"; do
    [ -f "$p" ] || { echo "нет патча $p" >&2; exit 1; }
    git apply --check "$p" || {
      echo "ошибка: $(basename "$p") не встаёт на этот коммит" >&2
      echo "  проверь пин в deps/wallpicker.txt" >&2
      exit 1
    }
    git apply "$p"
    echo "  $(basename "$p"): применён"
  done
fi

echo "собираю (около 80 с на 4 ядрах)"
make 2>&1 | tail -20
[ -x "$SRC/wallpicker" ] || { echo "ошибка: бинарник не появился" >&2; exit 1; }
echo "готово: $SRC/wallpicker"
