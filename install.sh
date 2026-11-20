#!/bin/sh
# install.sh - установка острова BDI одной командой.
#
# usage:
#   ./install.sh check     # что не хватает, какой командой поставить (только чтение)
#   ./install.sh install   # собрать движок, отключить панель XFCE, поставить автозапуск
#   ./install.sh update    # git pull, пересборка при новом пине или патчах, перезапуск
#   ./install.sh help      # эта справка
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
. "$ROOT/lib/check.sh"

usage() {
  sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
}

case "${1:-help}" in
  check)   check_all ;;
  install) . "$ROOT/lib/install.sh"; install_all ;;
  update)  . "$ROOT/lib/install.sh"; update_all ;;
  help|-h|--help) usage ;;
  *) usage; exit 2 ;;
esac
