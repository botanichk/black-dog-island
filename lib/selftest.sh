#!/bin/sh
# lib/selftest.sh - самопроверка lib/ на временных данных.
#
# Запускать ИЗОЛИРОВАННО (правило в AGENTS.md): своя шина D-Bus, HOME и XDG
# в /tmp. Реальные Plank, xfconf, dconf не читаются.
#
#   env -u DBUS_SESSION_BUS_ADDRESS -u XDG_RUNTIME_DIR HOME=/tmp/fakehome \
#       XDG_CONFIG_HOME=/tmp/fakehome/.config XDG_STATE_HOME=/tmp/fakehome/.local/state \
#       dbus-run-session -- sh lib/selftest.sh
#
# Код 0 - всё сошлось.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/lib/log.sh"
. "$ROOT/lib/distro.sh"
. "$ROOT/lib/journal.sh"
. "$ROOT/lib/backup.sh"

fail=0
check() {  # check <что> <ожидалось> <получено>
  if [ "$2" = "$3" ]; then printf 'ok   %s\n' "$1"
  else printf 'FAIL %s: ждали [%s], получили [%s]\n' "$1" "$2" "$3"; fail=1; fi
}

# --- 1. дистро ---
for d in cachyos:arch:arch.txt void:void:void.txt alpine:unknown:; do
  n=${d%%:*}; r=${d#*:}; want=${r%%:*}; f=${r#*:}
  printf 'ID=%s\n' "$n" > "/tmp/bdi-os-$n"
  OS_RELEASE="/tmp/bdi-os-$n" distro_detect
  check "дистро $n" "$want" "$BDI_DISTRO"
  check "deps $n" "$f" "$BDI_DEPS"
done
OS_RELEASE=/tmp/bdi-os-void distro_detect
check "команда void" "sudo xbps-install -S wmctrl" "$(distro_install_cmd wmctrl)"
OS_RELEASE=/tmp/bdi-os-cachyos distro_detect
check "команда arch" "sudo pacman -S --needed wmctrl" "$(distro_install_cmd wmctrl)"

# --- 2. журнал ---
mkdir -p "$BDI_STATE"
: > "$BDI_JOURNAL"
journal_add xfconf /k "[старое]" "новое"
check "записей" "1" "$(journal_count)"
check "старое" "[старое]" "$(journal_get xfconf /k)"
journal_get xfconf /нет >/dev/null 2>&1 && check "нет записи" "1" "0" || check "нет записи" "1" "1"
# значение с табуляцией не должно ломать строки
journal_add file /f "a	b" "c"
check "таб заменён" "2" "$(journal_count)"

# --- 3. бэкап ---
mkdir -p "$HOME/.config/xfce4" "$HOME/.config/autostart"
backup_create >/dev/null
[ -f "$BDI_BACKUP_DIR/xfconf.txt" ] && check "дамп xfconf" "да" "да" || check "дамп xfconf" "да" "нет"
[ -d "$BDI_BACKUP_DIR/.config_xfce4" ] && check "копия xfce4" "да" "да" || check "копия xfce4" "да" "нет"
check "last-backup" "$BDI_BACKUP_DIR" "$(cat "$BDI_STATE/last-backup")"

# --- 4. путь IPC-сокета Eww ---
# Формула повторяет хэш Eww (paths.rs). Сверено с живым демоном: для
# /home/ig_ro/eww-island/eww сокет был eww-server_5e929ad971167bef.
# Зашивать этот путь в проверку нельзя - он зависит от каталога репозитория,
# поэтому проверяем форму и стабильность: два вызова дают одно и то же,
# а разные каталоги - разное.
mkdir -p /tmp/bdi-socktest/a /tmp/bdi-socktest/b
_s1=$(XDG_RUNTIME_DIR=/run/user/0 sh "$ROOT/lib/eww-socket.sh" /tmp/bdi-socktest/a)
_s2=$(XDG_RUNTIME_DIR=/run/user/0 sh "$ROOT/lib/eww-socket.sh" /tmp/bdi-socktest/a)
_s3=$(XDG_RUNTIME_DIR=/run/user/0 sh "$ROOT/lib/eww-socket.sh" /tmp/bdi-socktest/b)
check "сокет: лежит в runtime" "/run/user/0" "$(dirname "$_s1")"
check "сокет: имя как у Eww" "eww-server_" "$(basename "$_s1" | cut -c1-11)"
check "сокет: стабилен" "$_s1" "$_s2"
[ "$_s1" != "$_s3" ] && check "сокет: разные конфиги различаются" "да" "да" \
  || check "сокет: разные конфиги различаются" "да" "нет"
# без XDG_RUNTIME_DIR Eww берёт /tmp
_s4=$(env -u XDG_RUNTIME_DIR sh "$ROOT/lib/eww-socket.sh" /tmp/bdi-socktest/a)
check "сокет: без runtime -> /tmp" "/tmp" "$(dirname "$_s4")"

echo
if [ "$fail" -eq 0 ]; then echo "lib: всё ок"; else echo "lib: есть ошибки"; fi
exit "$fail"
