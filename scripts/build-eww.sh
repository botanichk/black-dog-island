#!/bin/sh
# Пересборка Eww из вендорённого исходника с нашими патчами.
# Патчи лежат в patches/ и применяются поверх upstream-коммита.
#
# Скрипт идемпотентен: повторный запуск даёт тот же результат и не затирает
# правки, сделанные в других файлах исходника. Никакого `git checkout`:
# применяется только то, что нужно, и только в рамках самих патчей.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SRC="$ROOT/build/eww-src"
PATCHES="$ROOT/patches"

[ -d "$SRC" ] || { echo "нет исходников eww: $SRC" >&2; exit 1; }
[ -x "$HOME/.cargo/bin/cargo" ] || [ -x /usr/bin/cargo ] || {
  echo "не найден cargo; поставь rustup (пакет rustup в pacman)" >&2; exit 1; }

cd "$SRC"

# apply_patch <путь к патчу>
# Порядок:
#   1. патч уже применён?  -> откатываем (reverse), потом накатываем заново;
#   2. патч не применён?  -> накатываем;
#   3. не то и не другое   -> конфликт с посторонней правкой: диагностика и выход.
apply_patch() {
  p=$1
  name=$(basename "$p")

  if git apply --reverse --check "$p" 2>/dev/null; then
    echo "  $name: уже применён, переприменяю"
    git apply --reverse "$p" || {
      echo "ошибка: не удалось откатить $name" >&2; exit 1; }
  fi

  if git apply --check "$p" 2>/dev/null; then
    echo "  $name: применяю"
    git apply "$p" || {
      echo "ошибка: не удалось применить $name" >&2; exit 1; }
    return 0
  fi

  echo "ошибка: патч $name конфликтует с текущим состоянием исходника." >&2
  echo "  Возможно, файл изменён вручную в участке патча." >&2
  echo "  Что именно не совпадает:" >&2
  git apply --check --verbose "$p" 2>&1 | sed 's/^/    /' >&2 || true
  echo "  Сделайте 'git -C $SRC diff' и разберитесь руками," >&2
  echo "  либо верните файл к состоянию коммита $(git rev-parse --short HEAD)." >&2
  exit 1
}

for p in "$PATCHES"/*.patch; do
  [ -e "$p" ] || continue
  apply_patch "$p"
done

CARGO_TARGET_DIR="$ROOT/build/target" \
  cargo build --release --locked --no-default-features --features x11

echo "бинарник: $ROOT/build/target/release/eww"
