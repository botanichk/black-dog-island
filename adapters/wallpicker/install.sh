#!/bin/sh
# install.sh - поставить хук для hypr-wallpicker (идемпотентно).
#
# usage: adapters/wallpicker/install.sh
#        adapters/wallpicker/install.sh --remove
#
# Делает символическую ссылку
#   ~/.config/hypr-wallpicker/apply-wallpaper.sh -> adapters/wallpicker/apply.sh
# Символическая, а не копия: правка хука в проекте сразу действует, и
# никаких «двух версий» не появляется.
#
# Программу wallpicker НЕ ставит в систему: она живёт в ~/src/hypr-wallpicker,
# sudo не нужен (см. docs/WALLPICKER.md).
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
HOOK_DIR="$HOME/.config/hypr-wallpicker"
HOOK="$HOOK_DIR/apply-wallpaper.sh"
TARGET="$ROOT/adapters/wallpicker/apply.sh"

case "${1:-}" in
  --remove)
    if [ -L "$HOOK" ]; then
      rm -f "$HOOK"
      echo "хук убран: $HOOK"
    else
      echo "ссылки нет: $HOOK"
    fi
    exit 0 ;;
  "") ;;
  *) echo "неизвестный аргумент: $1" >&2; exit 2 ;;
esac

command -v xfconf-query >/dev/null 2>&1 || {
  echo "нет xfconf-query (пакет xfconf) - без него обои не поставить" >&2
  exit 1
}

chmod +x "$TARGET"
mkdir -p "$HOOK_DIR"

# Уже есть ссылка на нас - ничего не делаем (повторный запуск).
if [ -L "$HOOK" ] && [ "$(readlink -f "$HOOK")" = "$(readlink -f "$TARGET")" ]; then
  echo "хук уже стоит: $HOOK -> $TARGET"
  exit 0
fi

# Есть чужой файл (например, пример из репозитория wallpicker) - не затираем
# молча: сначала показываем, что там, и просим убрать.
if [ -e "$HOOK" ] && [ ! -L "$HOOK" ]; then
  echo "уже есть файл $HOOK, он не наш. Уберите его вручную:" >&2
  echo "  rm $HOOK" >&2
  exit 1
fi

ln -sfn "$TARGET" "$HOOK"
echo "хук поставлен: $HOOK -> $TARGET"

# Проверка: ссылка ведёт туда и исполняемая.
if [ -x "$HOOK" ]; then
  echo "проверка: $(readlink -f "$HOOK") исполняемый"
else
  echo "ошибка: $HOOK не исполняемый" >&2
  exit 1
fi
