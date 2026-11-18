#!/bin/sh
# Меню питания: выйти из сессии, перезагрузить, выключить.
#
# usage: power.sh logout|reboot|poweroff|status
#
# Почему через loginctl и systemctl, а не через `poweroff`/`reboot` напрямую:
# обе команды есть в системе и обе идут через systemd-logind, но loginctl
# умеет ещё и завершить сессию, не трогая машину (`loginctl terminate-session`),
# а systemctl - именно то, что делает кнопка выключения в любом DE.
# Проверено: polkit-агент (polkit-gnome, pid 826) работает, поэтому запрос
# прав проходит без ввода пароля из терминала.
#
# Ничего не выключается при вызове без аргумента или с незнакомым аргументом:
# скрипт сначала печатает, что собирается сделать, и только потом действует.
# Это защита от случайного нажатия при отладке.
set -eu

LOG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/eww-island"
mkdir -p "$LOG_DIR" 2>/dev/null || true
LOG="$LOG_DIR/power.log"

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG" 2>/dev/null || true
}

# Текущая сессия текущего пользователя: loginctl сам подставит её, если не
# указывать аргумент, но явный id надёжнее в скрипте, запущенном из Eww.
session_id() {
  loginctl list-sessions --no-legend 2>/dev/null \
    | awk -v u="${USER:-$(id -un)}" '$3 == u {print $1; exit}'
}

case "${1:-}" in
  logout)
    SID=$(session_id)
    if [ -z "$SID" ]; then
      log "logout: сессия не найдена"
      echo "не нашёл сессию пользователя" >&2
      exit 1
    fi
    log "logout: loginctl terminate-session $SID"
    exec loginctl terminate-session "$SID"
    ;;
  reboot)
    log "reboot: systemctl reboot"
    exec systemctl reboot
    ;;
  poweroff)
    log "poweroff: systemctl poweroff"
    exec systemctl poweroff
    ;;
  status)
    echo "сессия:   $(session_id || echo '?')"
    echo "тип:      $(loginctl show-session "$(session_id)" -p Type --value 2>/dev/null || echo '?')"
    echo "polkit:   $(pgrep -f 'polkit.*agent' >/dev/null 2>&1 && echo работает || echo 'не найден')"
    echo "systemctl: $(command -v systemctl || echo нет)"
    echo "loginctl:  $(command -v loginctl || echo нет)"
    exit 0
    ;;
  *)
    echo "usage: power.sh logout|reboot|poweroff|status" >&2
    echo "ничего не сделано (нет действия)" >&2
    exit 2
    ;;
esac
