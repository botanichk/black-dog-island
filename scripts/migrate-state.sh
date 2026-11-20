#!/bin/sh
# migrate-state.sh - перенос состояния из репозитория в каталоги пользователя.
#
# Однократный и идемпотентный: файлы, которые уже есть в новых местах, не
# трогает; старые оставляет на диске как страховку (из git они убраны).
# Вызывается из scripts/run-island.sh перед стартом демона.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BDI_CONFIG="${BDI_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/bdi}"
BDI_STATE="${BDI_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/bdi}"
BDI_CACHE="${BDI_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/bdi}"
OLD_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/eww-island"
OLD_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/eww-island"

mkdir -p "$BDI_CONFIG" "$BDI_STATE/schemes" "$BDI_CACHE" 2>/dev/null || true

# copy <откуда> <куда>: переносит и убирает оригинал, если копия совпала
# байт в байт. Уже перенесённое (или изменённое пользователем) не трогает.
copy() {
  [ -f "$1" ] || return 0
  if [ -e "$2" ]; then
    cmp -s "$1" "$2" && rm -f "$1"
    return 0
  fi
  cp -p "$1" "$2"
  cmp -s "$1" "$2" && rm -f "$1"
  echo "перенесено: $1 -> $2"
}

# 1. Выбор темы.
for f in current mode accent wallpaper-scheme hue-filter; do
  copy "$ROOT/theme/$f" "$BDI_CONFIG/$f"
done

# 2. Сгенерированные схемы; встроенные default/light остаются в репозитории.
for f in "$ROOT"/theme/schemes/*.json; do
  [ -f "$f" ] || continue
  case "$(basename "$f")" in default.json|light.json) continue ;; esac
  copy "$f" "$BDI_STATE/schemes/$(basename "$f")"
done

# 3. Кэш: копируем только недостающее. Старый демон мог успеть создать часть
# файлов в новом каталоге до миграции (kbdlayout, timer), затирать их нельзя.
for f in "$OLD_CACHE"/*; do
  [ -e "$f" ] || continue
  b=$(basename "$f")
  [ -e "$BDI_CACHE/$b" ] && continue
  cp -a "$f" "$BDI_CACHE/$b" && echo "перенесено: $f -> $BDI_CACHE/$b"
done

# 4. Состояние Plank и Ulauncher (раньше лежало в ~/.config/eww-island).
for f in plank-base-theme plank-color ulauncher-theme; do
  copy "$OLD_CONFIG/$f" "$BDI_CONFIG/$f"
done
