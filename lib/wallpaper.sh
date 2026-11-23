#!/bin/sh
# lib/wallpaper.sh - папка обоев, счёт картинок и сообщение человеку.
#
# Одно правило поиска папки на всех: adapters/wallpicker/run.sh (запуск сот),
# adapters/x11/wallpaper.sh (кнопка обоев), lib/check.sh и scripts/diag.sh.
# Раньше правило было скопировано в двух местах и читало только xdg-user-dir,
# которого на Void нет: папка «Изображения» не находилась вовсе.
#
# Расширения - ровно те, что понимает сама программа (src/fs.c:
# IsSupportedWallpaperFile): png, jpg, jpeg. webp и вложенные папки она НЕ
# показывает, поэтому считать их значило бы обещать пустую сетку.
#
# set -u здесь нет намеренно: библиотека подключается к чужим скриптам и не
# должна менять их режим оболочки.

# bdi_wallpaper_dir - первая существующая папка обоев по порядку:
#   $BDI_WALLPAPERS -> $WALLPAPER_DIR (старое имя) -> ~/.config/bdi/wallpapers
#   -> XDG_PICTURES_DIR (user-dirs.dirs, потом xdg-user-dir) -> ~/Pictures
#   -> ~/Изображения.
# Ничего нет - печатает ~/Pictures: сообщение назовёт путь, куда положить.
bdi_wallpaper_dir() {
  _cfg="${BDI_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/bdi}"
  _file=""
  [ -r "$_cfg/wallpapers" ] && _file=$(tr -d ' \t\r\n' < "$_cfg/wallpapers" 2>/dev/null || true)

  _xdg=""
  _ud="${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs"
  if [ -r "$_ud" ]; then
    _xdg=$(sed -n 's/^XDG_PICTURES_DIR="\(.*\)"$/\1/p' "$_ud" | tail -1)
    case "$_xdg" in
      '$HOME'/*) _xdg="$HOME/${_xdg#\$HOME/}" ;;
      '$HOME') _xdg="" ;;
    esac
  fi
  if [ -z "$_xdg" ] && command -v xdg-user-dir >/dev/null 2>&1; then
    _xdg=$(xdg-user-dir PICTURES 2>/dev/null || true)
  fi

  for _d in "${BDI_WALLPAPERS:-}" "${WALLPAPER_DIR:-}" "$_file" "$_xdg" \
            "$HOME/Pictures" "$HOME/Изображения"; do
    # xdg-user-dir без настроек отдаёт сам $HOME - это не папка картинок.
    if [ -n "$_d" ] && [ "$_d" != "$HOME" ] && [ -d "$_d" ]; then
      printf '%s\n' "$_d"
      return 0
    fi
  done
  printf '%s\n' "${BDI_WALLPAPERS:-$HOME/Pictures}"
}

# bdi_count_walls <папка> - сколько обоев увидит программа (верхний уровень).
bdi_count_walls() {
  find "$1" -maxdepth 1 -type f \
    \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) 2>/dev/null | wc -l | tr -d ' '
}

# bdi_notify <текст> - сказать человеку вслух. notify-send есть не везде
# (Void - отдельный пакет), тогда остаётся stdout и лог вызывающего.
bdi_notify() {
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -t 8000 "Остров BDI" "$*" >/dev/null 2>&1 || true
  fi
}
