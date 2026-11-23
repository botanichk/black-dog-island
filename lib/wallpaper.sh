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

# bdi_wallpaper_dir - папка обоев: всегда ~/Изображения.
#
# Так решил владелец (2026-11-23): обои лежат в ~/Изображения, искать больше
# негде. Раньше шёл перебор (xdg-user-dir, ~/Pictures, ~/Изображения), и на
# машине с пустой ~/Pictures он выбирал её - сетка открывалась пустой, хотя
# рядом лежали сорок обоев.
#
# Явное слово владельца главнее: $BDI_WALLPAPERS, $WALLPAPER_DIR (старое имя)
# или путь в ~/.config/bdi/wallpapers. Это нужно для второй папки и для
# проверок на заглушках.
bdi_wallpaper_dir() {
  _cfg="${BDI_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/bdi}"
  _file=""
  [ -r "$_cfg/wallpapers" ] && _file=$(tr -d ' \t\r\n' < "$_cfg/wallpapers" 2>/dev/null || true)

  for _d in "${BDI_WALLPAPERS:-}" "${WALLPAPER_DIR:-}" "$_file"; do
    [ -n "$_d" ] && printf '%s\n' "$_d" && return 0
  done
  printf '%s\n' "$HOME/Изображения"
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
