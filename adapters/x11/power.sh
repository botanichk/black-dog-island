#!/bin/sh
# Меню питания: выйти из сессии, перезагрузить, выключить.
#
# usage: power.sh logout|reboot|poweroff|status
#
# Выключение и перезагрузка - через logind: systemctl на Arch, loginctl на Void
# (там systemd нет вовсе, за logind отвечает elogind). Это ровно то, что делает
# кнопка в любом DE, и polkit для org.freedesktop.login1.power-off / .reboot
# разрешает активной сессии действовать без пароля (allow_active=yes). Проверено:
# pkcheck --action-id org.freedesktop.login1.power-off --process $$ -> код 0.
#
# Выход из сессии - НЕ через loginctl terminate-session. Тот требует polkit
# org.freedesktop.login1.manage, а у него allow_active=auth_admin_keep, то есть
# пароль admin каждый раз: pkcheck --action-id org.freedesktop.login1.manage
# --process $$ -> "Authorization requires authentication", код 2. Агент
# polkit-gnome в XFCE показывал бы окно с паролем, а из кнопки меню его никто
# не заполнит - поэтому кнопка «Выйти» молча ничего не делала.
#
# Вместо этого зовём родной менеджер сессии XFCE: он завершает сессию сам,
# изнутри, без polkit (права уже есть - процесс наш). Два равнозначных пути:
#   * xfce4-session-logout --logout - утилита XFCE, шлёт Logout в менеджер;
#   * dbus-send ... org.xfce.Session.Manager.Logout false true - то же самое,
#     но без промежуточного бинарника (первый аргумент - не показывать диалог,
#     второй - разрешить сохранение сессии).
# Пробуем утилиту, а если её нет - dbus. Ошибку не глотаем: пишем в лог.
#
# Ничего не выключается при вызове без аргумента или с незнакомым аргументом:
# скрипт сначала печатает, что собирается сделать, и только потом действует.
# Это защита от случайного нажатия при отладке.
set -eu

LOG_DIR="${BDI_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/bdi}"
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

# Выход из сессии через менеджер XFCE. Возвращает 0, если команда ушла.
logout_xfce() {
  if command -v xfce4-session-logout >/dev/null 2>&1; then
    log "logout: xfce4-session-logout --logout"
    xfce4-session-logout --logout >/dev/null 2>&1
    return $?
  fi
  if command -v dbus-send >/dev/null 2>&1; then
    # Имя интерфейса именно org.xfce.Session.Manager (с точками), не
    # org.xfce.SessionManager: последнее - это имя службы на шине.
    log "logout: dbus Logout(false, true) в org.xfce.Session.Manager"
    dbus-send --session --type=method_call \
      --dest=org.xfce.SessionManager /org/xfce/SessionManager \
      org.xfce.Session.Manager.Logout boolean:false boolean:true >/dev/null 2>&1
    return $?
  fi
  log "logout: нет ни xfce4-session-logout, ни dbus-send"
  return 1
}

case "${1:-}" in
  logout)
    if logout_xfce; then
      exit 0
    fi
    # Запасной путь для не-XFCE сессий: выйти из сессии средствами logind.
    # Тут polkit может спросить пароль - это лучше, чем не сделать ничего.
    SID=$(session_id)
    if [ -n "$SID" ]; then
      log "logout: запасной путь, loginctl terminate-session $SID"
      exec loginctl terminate-session "$SID"
    fi
    log "logout: сессия не найдена"
    echo "не смог выйти из сессии" >&2
    exit 1
    ;;
  reboot|poweroff)
    # Действие одно и то же, а средство зависит от системы: на Void systemctl
    # нет, и `exec systemctl` тихо ничего не делал (код 127 в лог не писался).
    if command -v systemctl >/dev/null 2>&1; then
      log "$1: systemctl $1"
      exec systemctl "$1"
    fi
    if command -v loginctl >/dev/null 2>&1; then
      log "$1: loginctl $1"
      exec loginctl "$1"
    fi
    log "$1: нет ни systemctl, ни loginctl"
    echo "не смог: нет systemctl и loginctl" >&2
    exit 1
    ;;
  status)
    echo "сессия:   $(session_id || echo '?')"
    echo "тип:      $(loginctl show-session "$(session_id)" -p Type --value 2>/dev/null || echo '?')"
    echo "polkit:   $(pgrep -f 'polkit.*agent' >/dev/null 2>&1 && echo работает || echo 'не найден')"
    echo "systemctl: $(command -v systemctl || echo нет)"
    echo "loginctl:  $(command -v loginctl || echo нет)"
    echo "logout:    $(command -v xfce4-session-logout || echo 'нет утилиты, будет dbus-send')"
    echo
    # Права polkit: у выключения/перезагрузки без пароля, у terminate-session -
    # только с паролем. Поэтому выход идёт через менеджер сессии, не через logind.
    echo "права без пароля:"
    for act in power-off reboot manage; do
      if pkcheck --action-id "org.freedesktop.login1.$act" --process $$ >/dev/null 2>&1; then
        echo "  $act: да"
      else
        echo "  $act: нет (для manage это нормально, см. комментарий в скрипте)"
      fi
    done
    exit 0
    ;;
  *)
    echo "usage: power.sh logout|reboot|poweroff|status" >&2
    echo "ничего не сделано (нет действия)" >&2
    exit 2
    ;;
esac
