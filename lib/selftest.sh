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

# --- 5. палитра из обоев без внешних программ ---
# Считаем сами (theme/wp-palette.py), поэтому проверяем то, что легко
# сломать: десять схем различимы, все роли на месте, без magick честный
# отказ, а не тихий n=0.
_wp=$(mktemp -d "${TMPDIR:-/tmp}/bdi-wp.XXXXXX")
python3 - "$_wp/gradient.png" <<'PY'
import subprocess, sys
# Простая картинка: три цветные полосы. Без внешних файлов - magick сам
# нарисует, проверка не зависит от картинок владельца.
subprocess.run(["magick", "-size", "90x30", "xc:#2b6cb0",
                "-fill", "#c05621", "-draw", "rectangle 30,0 59,29",
                "-fill", "#2f855a", "-draw", "rectangle 60,0 89,29",
                sys.argv[1]], check=False)
PY
if [ -f "$_wp/gradient.png" ]; then
  python3 "$ROOT/theme/wp-palette.py" "$_wp/gradient.png" --all -o "$_wp/schemes" 2>/dev/null || true
  check "палитра: десять схем" "10" "$(ls "$_wp/schemes" 2>/dev/null | wc -l | tr -d ' ')"
  _first=$(python3 "$ROOT/theme/wp-palette.py" "$_wp/gradient.png" --scheme vibrant 2>/dev/null |
           python3 -c 'import json,sys; print(json.load(sys.stdin)["dark"]["primary"])' 2>/dev/null || true)
  case "$_first" in
    "#"*) check "палитра: есть primary" "да" "да" ;;
    *)    check "палитра: есть primary" "да" "нет" ;;
  esac
  # Три акцента не должны быть копиями друг друга: иначе ряд кружков
  # показывает один цвет трижды.
  _acc=$(python3 "$ROOT/theme/wp-palette.py" "$_wp/gradient.png" --scheme m3-tonal-spot 2>/dev/null |
         python3 -c 'import json,sys; d=json.load(sys.stdin)["dark"]; print(len({d["primary"],d["secondary"],d["tertiary"]}))' 2>/dev/null || echo 0)
  check "палитра: акценты разные" "3" "$_acc"
  # Без magick - честный код 1, а не пустой JSON.
  mkdir -p "$_wp/bin"
  for _b in python3; do ln -sf "$(command -v $_b)" "$_wp/bin/$_b"; done
  _rc=0
  env PATH="$_wp/bin" python3 "$ROOT/theme/wp-palette.py" "$_wp/gradient.png" >/dev/null 2>&1 || _rc=$?
  check "палитра: без magick отказ" "1" "$_rc"
else
  check "палитра: magick нарисовал картинку" "да" "нет"
fi
rm -rf "$_wp"

echo
if [ "$fail" -eq 0 ]; then echo "lib: всё ок"; else echo "lib: есть ошибки"; fi
exit "$fail"
