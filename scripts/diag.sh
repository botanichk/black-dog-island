#!/bin/sh
# diag.sh - одноразовая диагностика острова: собрать факты для отчёта.
# Ничего не меняет, только читает. Запускать из корня репозитория.
#
#   sh scripts/diag.sh
#
# Печатает всё, что нужно, чтобы понять, почему остров не поднялся:
# какой демон работает, отвечает ли он, что говорит open island и
# что видно в логе Eww.
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
EWW="$ROOT/build/target/release/eww"
CONF="$ROOT/eww"
GEOM="$ROOT/adapters/x11/island-geom.sh"

BDI_ROOT="$ROOT"
BDI_CONFIG="${BDI_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/bdi}"
BDI_STATE="${BDI_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/bdi}"
BDI_CACHE="${BDI_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/bdi}"
export BDI_ROOT BDI_CONFIG BDI_STATE BDI_CACHE

sec() { printf '\n== %s\n' "$*"; }

sec "окружение"
printf 'root        %s\n' "$ROOT"
printf 'дисплей     %s (экран %s)\n' "${DISPLAY:-нет}" \
  "$(xrandr --current 2>/dev/null | awk '/\*/{print $1; exit}')"
printf 'бинарник    %s\n' "$([ -x "$EWW" ] && echo есть || echo НЕТ)"
printf 'colors.scss %s\n' "$([ -f "$CONF/colors.scss" ] && echo есть || echo НЕТ)"

sec "демоны Eww (наши)"
pgrep -af "$EWW --config $CONF daemon" 2>/dev/null | grep -v pgrep || echo 'нет'

sec "BDI_ROOT у демонов"
# Пустой BDI_ROOT - самая частая причина «кнопки не работают»: в eww.yuck он
# подставляется в пути команд, и они превращаются в /adapters/... (нет такого).
# Так бывает, если демон подняли руками: `eww --config eww daemon` без
# окружения от run-island.sh.
_n=0
for _p in $(pgrep -f "$EWW --config .* daemon" 2>/dev/null); do
  [ "$_p" = "$$" ] && continue
  _r=$(tr '\0' '\n' < "/proc/$_p/environ" 2>/dev/null | sed -n 's/^BDI_ROOT=//p')
  _c=$(tr '\0' ' ' < "/proc/$_p/cmdline" 2>/dev/null)
  _n=$((_n + 1))
  printf 'pid %s  BDI_ROOT=[%s]\n' "$_p" "${_r:-ПУСТО}"
  printf '        cmd: %s\n' "$_c"
  [ -n "$_r" ] || printf '        ^ ЭТОТ ДЕМОН ЗАПУЩЕН БЕЗ BDI_ROOT: кнопки не работают\n'
done
[ "$_n" -eq 0 ] && echo 'нет демонов Eww'

sec "чужие демоны Eww"
pgrep -af 'eww.*daemon' 2>/dev/null | grep -v pgrep | grep -v "$CONF" || echo 'нет'

sec "ping"
timeout 5 "$EWW" --config "$CONF" ping 2>&1
printf 'код: %s\n' "$?"

sec "окна Eww на экране"
wmctrl -l 2>/dev/null | grep -i eww || echo 'нет ни одного'

sec "поиск окна острова (island-geom.sh)"
if [ -x "$GEOM" ]; then
  "$GEOM" xid 2>&1 || echo 'не найдено (код выше)'
  "$GEOM" 2>&1 || true
else
  echo 'нет скрипта'
fi

sec "open island (вывод как есть)"
timeout 15 "$EWW" --config "$CONF" --no-daemonize open island 2>&1
printf 'код: %s\n' "$?"

sec "окна Eww после open"
wmctrl -l 2>/dev/null | grep -i eww || echo 'нет ни одного'

sec "лог Eww (свежий файл)"
_l=$(ls -t "${XDG_CACHE_HOME:-$HOME/.cache}"/eww/*.log 2>/dev/null | head -1)
if [ -n "${_l:-}" ]; then
  printf 'файл: %s\n\n' "$_l"
  tail -30 "$_l" 2>/dev/null || echo 'пусто'
else
  echo 'логов нет'
fi

sec "последние строки лога темы"
[ -f "$BDI_CACHE/theme.log" ] && tail -5 "$BDI_CACHE/theme.log" 2>/dev/null || echo 'пусто'

# Plank и Ulauncher красятся из того же apply.sh, но ломаются по-разному:
# Plank требует схемы glib и перезапуска, Ulauncher - своей папки тем.
# Без этих фактов с чужой машины причину не угадать.
for _t in plank ulauncher; do
  sec "$_t: theme/$_t.sh status"
  if [ -x "$ROOT/theme/$_t.sh" ]; then
    timeout 20 "$ROOT/theme/$_t.sh" status 2>&1 || echo 'status не ответил'
  else
    echo 'нет скрипта'
  fi
  sec "$_t: лог"
  [ -f "$BDI_CACHE/$_t.log" ] && tail -8 "$BDI_CACHE/$_t.log" 2>/dev/null || echo 'пусто'
done

sec "Plank: схема glib и doc-ключи"
gsettings list-schemas 2>/dev/null | grep -i plank || echo 'схем glib для plank нет'
gsettings get net.launchpad.plank enabled-docks 2>&1
dconf dump /net/launchpad/plank/ 2>/dev/null | grep -i 'theme' || echo 'тема в dconf не записана'
ls /usr/share/plank/themes 2>/dev/null | head -3 || echo 'нет /usr/share/plank/themes'
ls "$HOME/.local/share/plank/themes" 2>/dev/null | head -3 || echo 'нет ~/.local/share/plank/themes'

echo
echo 'Скопируйте весь этот вывод целиком.'
