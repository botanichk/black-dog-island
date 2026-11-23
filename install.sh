#!/bin/sh
# install.sh - установка острова BDI одной командой.
#
# usage:
#   ./install.sh check          # что не хватает, какой командой поставить (только чтение)
#   ./install.sh install        # собрать движок, отключить панель XFCE, поставить автозапуск
#   ./install.sh update         # git pull, пересборка при новом пине или патчах, перезапуск
#   ./install.sh uninstall      # откат по журналу; работает без X и без xfconfd
#   ./install.sh --restore-backup [каталог]  # вернуть настройки из резервной копии
#   ./install.sh help           # эта справка
#
# install и update работают только в сеансе X11 + XFCE: в Wayland и в чужих
# рабочих столах (Hyprland и т. п.) установщик печатает причину и выходит,
# ничего не меняя. check, uninstall и --restore-backup разрешены в любом
# сеансе и без графики: это путь отката, когда XFCE не поднялся.
#
# sudo не зовётся нигде: пакеты ставит владелец сам по подсказке из check.
# Всё остальное делается в домашнем каталоге и в клоне репозитория.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export ROOT

BDI_CONFIG="${BDI_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/bdi}"
BDI_STATE="${BDI_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/bdi}"
BDI_CACHE="${BDI_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/bdi}"
export BDI_CONFIG BDI_STATE BDI_CACHE

. "$ROOT/lib/log.sh"
. "$ROOT/lib/distro.sh"
. "$ROOT/lib/journal.sh"
. "$ROOT/lib/backup.sh"
. "$ROOT/lib/eww-proc.sh"
. "$ROOT/lib/check.sh"

usage() {
  sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
}

case "${1:-help}" in
  # check работает в любом сеансе: он только читает. uninstall и
  # --restore-backup - тоже: это аварийный путь, когда XFCE не поднялся и
  # владелец вошёл в Hyprland или в TTY (часть D задания 17).
  check)   check_all ;;
  uninstall)
    . "$ROOT/lib/install.sh"; uninstall_all ;;
  --restore-backup)
    . "$ROOT/lib/install.sh"; restore_backup "${2:-}" ;;
  install|update)
    . "$ROOT/lib/session.sh"
    _what="Установка не выполнена"
    [ "$1" = update ] && _what="Обновление не выполнено"
    if ! bdi_session_ok; then
      printf '%s: %s\n' "$_what" "$(bdi_session_why)"
      printf 'Сеанс: %s\n' "$(bdi_session_name)"
      printf 'Нужен сеанс X11 + XFCE. Ничего не изменено.\n'
      exit 1
    fi
    . "$ROOT/lib/install.sh"
    if [ "$1" = install ]; then install_all; else update_all; fi ;;
  help|-h|--help) usage ;;
  *) usage; exit 2 ;;
esac
