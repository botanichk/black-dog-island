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

# Вывод копится в файл и печатается в конце через sed: в отчёте не должно быть
# имени пользователя (пути /home/<кто>) и названий сетей - владелец присылает
# вывод публично. Сети в diag не печатаются вообще, имя убираем здесь.
_OUT="${TMPDIR:-/tmp}/bdi-diag.$$"
exec 3>&1 4>&2 1>"$_OUT" 2>&1
trap 'rm -f "$_OUT"' EXIT INT TERM HUP

BDI_ROOT="$ROOT"
BDI_CONFIG="${BDI_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/bdi}"
BDI_STATE="${BDI_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/bdi}"
BDI_CACHE="${BDI_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/bdi}"
export BDI_ROOT BDI_CONFIG BDI_STATE BDI_CACHE

sec() { printf '\n== %s\n' "$*"; }

# Окна острова. Не `grep -i eww`: под него попадают заголовки чужих окон
# (браузер со страницей про Eww). Имя пользователя (3-е поле wmctrl) скрываем -
# вывод присылают публично.
eww_windows() {
  wmctrl -l 2>/dev/null | grep 'Eww - ' | awk '{ $3 = "…"; print }'
}

sec "окружение"
printf 'root        %s\n' "$ROOT"
printf 'дисплей     %s (экран %s)\n' "${DISPLAY:-нет}" \
  "$(xrandr --current 2>/dev/null | awk '/\*/{print $1; exit}')"
printf 'сеанс       %s / %s\n' "${XDG_SESSION_TYPE:-?}" "${XDG_CURRENT_DESKTOP:-?}"
printf 'бинарник    %s\n' "$([ -x "$EWW" ] && echo есть || echo НЕТ)"
printf 'colors.scss %s\n' "$([ -f "$CONF/colors.scss" ] && echo есть || echo НЕТ)"

# Версии инструментов: половина «не работает на Void» - это другой awk, sed
# или date. Без версий такой отчёт не разобрать.
sec "инструменты"
printf 'awk         %s\n' "$(command -v awk || echo НЕТ)"
printf '  версия    %s\n' "$(awk --version 2>&1 | head -1 || awk -W version 2>&1 | head -1)"
printf 'sed         %s\n' "$(sed --version 2>&1 | head -1 || echo 'без --version')"
printf 'date        %s\n' "$(date --version 2>&1 | head -1 || echo 'без --version')"
printf 'stat        %s\n' "$(stat --version 2>&1 | head -1 || echo 'без --version')"
printf 'sh          %s -> %s\n' "$(command -v sh)" "$(readlink -f /bin/sh 2>/dev/null || echo '?')"
printf 'timeout     %s\n' "$(command -v timeout || echo НЕТ)"
printf 'flock       %s\n' "$(command -v flock || echo НЕТ)"
printf 'setsid      %s\n' "$(command -v setsid || echo НЕТ)"

sec "D-Bus и настройки"
printf 'DBUS_SESSION_BUS_ADDRESS %s\n' "${DBUS_SESSION_BUS_ADDRESS:-ПУСТО}"
dbus-send --session --dest=org.freedesktop.DBus --type=method_call \
  --print-reply /org/freedesktop/DBus org.freedesktop.DBus.ListNames \
  >/dev/null 2>&1 && printf 'сеансовая шина   отвечает\n' || printf 'сеансовая шина   НЕТ\n'
printf 'dconf       %s\n' "$(command -v dconf || echo НЕТ)"
printf 'gsettings   %s\n' "$(command -v gsettings || echo НЕТ)"
printf 'xfconf-query %s\n' "$(command -v xfconf-query || echo НЕТ)"

sec "noctalia"
# Только чтение: наши скрипты считают палитру сами (theme/wp-palette.py),
# noctalia нужна лишь как источник палитр, если стоит.
_noc=""
for _d in "${XDG_CONFIG_HOME:-$HOME/.config}/noctalia" \
          "${XDG_STATE_HOME:-$HOME/.local/state}/noctalia"; do
  [ -d "$_d" ] && _noc="$_noc $_d"
done
printf 'каталоги    %s\n' "${_noc:-нет}"
printf 'палитры     %s\n' "$(ls "${XDG_CONFIG_HOME:-$HOME/.config}/noctalia/palettes" 2>/dev/null | wc -l)"
printf 'location    %s\n' "$([ -r "$HOME/.cache/noctalia/location.json" ] && echo есть || echo 'нет (считаем по IP)')"

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
eww_windows || echo 'нет ни одного'

sec "поиск окна острова (island-geom.sh)"
if [ -x "$GEOM" ]; then
  "$GEOM" xid 2>&1 || echo 'не найдено (код выше)'
  "$GEOM" 2>&1 || true
else
  echo 'нет скрипта'
fi

sec "open island (вывод как есть)"
# open island ПЕРЕСОЗДАЁТ окно, а у defwindow island в eww.yuck прописан
# :x "0px": голый open ставит остров к левому краю. diag обязан ничего не
# менять, поэтому если окно уже есть - только сообщаем это и не трогаем;
# если окна нет - открываем сразу по центру через --pos, как run-island.sh.
if "$GEOM" xid >/dev/null 2>&1; then
  echo 'окно уже открыто - open не нужен (иначе остров уедет в x=0)'
  printf 'код: 0\n'
else
  _w=$(tr -cd '0-9' < "$BDI_CACHE/island-width" 2>/dev/null)
  _sw=$(xrandr --current 2>/dev/null | awk '/\*/{print $1; exit}' | cut -d x -f1)
  _x=0
  if [ -n "$_w" ] && [ -n "$_sw" ] && [ "$_w" -gt 0 ] && [ "$_w" -lt "$_sw" ]; then
    _x=$(( (_sw - _w) / 2 ))
  fi
  timeout 15 "$EWW" --config "$CONF" --no-daemonize open island --pos "${_x}x0" 2>&1
  printf 'код: %s\n' "$?"
fi

sec "окна Eww после open"
eww_windows || echo 'нет ни одного'

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

sec "композитор и экран"
# Без композитора не работают ни скруглённые углы острова, ни прозрачность
# (Ulauncher, док): xfwm4 рисует окно плотным и прямоугольным. На живой
# машине проверено, что прозрачный угол острова показывает обои, поэтому
# тест такой: точка в углу окна острова не должна быть равна $surface.
_comp=$(xfconf-query -c xfwm4 -p /general/use_compositing -v 2>/dev/null || echo '?')
printf 'xfwm4 use_compositing  %s\n' "$_comp"
printf 'разрешение  %s\n' "$(xrandr --current 2>/dev/null | awk '/\*/{print $1; exit}')"
_geo=$(wmctrl -lG 2>/dev/null | grep 'Eww - island' | head -1)
if [ -n "${_geo:-}" ]; then
  _x=$(printf '%s' "$_geo" | awk '{print $3}')
  _y=$(printf '%s' "$_geo" | awk '{print $4}')
  # Левый верхний пиксель окна лежит в прозрачном углу: там под островом
  # должны виднеться обои, а не $surface.
  _c=$(import -window root -crop "1x1+${_x}+${_y}" +repage txt:- 2>/dev/null | tail -1 | awk '{print substr($3,1,7)}')
  printf 'угол острова (%s,%s)  %s\n' "$_x" "$_y" "${_c:-не снято}"
  [ "$_comp" = true ] || printf 'ВЫКЛЮЧЕН: углы острова будут прямоугольными, прозрачности не будет\n'
fi

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

sec "соты обоев (wallpicker)"
# Кнопка обоев при провале молча открывает xfdesktop-settings, и снаружи это
# выглядит как «соты не работают». Причина всегда одна из трёх: нет бинарника,
# нет ссылки в ~/src/hypr-wallpicker (её ждёт run.sh), нет папки обоев.
_wpbin="$ROOT/build/wallpicker-src/wallpicker"
_wplink="$HOME/src/hypr-wallpicker/wallpicker"
printf 'бинарник   %s\n' "$([ -x "$_wpbin" ] && echo "есть ($(stat -c %s "$_wpbin" 2>/dev/null) байт)" || echo 'НЕТ - кнопка откроет xfdesktop-settings')"
printf 'ссылка     %s\n' "$([ -x "$_wplink" ] && echo "есть -> $(readlink -f "$_wplink" 2>/dev/null)" || echo "НЕТ ($_wplink)")"
printf 'пин        %s\n' "$(cat "$ROOT/build/.wallpicker-pin" 2>/dev/null || echo 'не записан')"
_wpdir=""
. "$ROOT/lib/wallpaper.sh"
_wpdir=$(bdi_wallpaper_dir)
printf 'папка обоев %s (%s шт.)\n' "$_wpdir" "$([ -d "$_wpdir" ] && bdi_count_walls "$_wpdir" || echo 'папки нет')"
[ -f "$BDI_CACHE/wallpicker.log" ] && tail -8 "$BDI_CACHE/wallpicker.log" 2>/dev/null || echo 'лог: пусто'

sec "raylib и OpenGL (для сот)"
# «Соты не открываются» на чужой машине чаще всего именно это: бинарник собран,
# но libGL или драйвер не дают окна, и программа выходит через SystemExit.
_wpbin2="$ROOT/build/wallpicker-src/wallpicker"
if [ -x "$_wpbin2" ]; then
  printf 'ldd         %s\n' "$(ldd "$_wpbin2" 2>/dev/null | grep -c 'not found') не найдено библиотек"
  ldd "$_wpbin2" 2>/dev/null | grep 'not found' | head -5
else
  echo 'бинарника нет - нечего смотреть'
fi
printf 'libGL       %s\n' "$(ls /usr/lib/libGL.so* /usr/lib64/libGL.so* 2>/dev/null | head -1 || echo НЕТ)"
printf 'glxinfo     %s\n' "$(command -v glxinfo || echo 'нет (необязательно)')"
printf 'OpenGL      %s\n' "$(glxinfo -B 2>/dev/null | sed -n 's/^OpenGL version string: //p' | head -1 || echo 'не спрошено')"

sec "Plank: схема glib и doc-ключи"
gsettings list-schemas 2>/dev/null | grep -i plank || echo 'схем glib для plank нет'
gsettings get net.launchpad.plank enabled-docks 2>&1
dconf dump /net/launchpad/plank/ 2>/dev/null | grep -i 'theme' || echo 'тема в dconf не записана'
ls /usr/share/plank/themes 2>/dev/null | head -3 || echo 'нет /usr/share/plank/themes'
ls "$HOME/.local/share/plank/themes" 2>/dev/null | head -3 || echo 'нет ~/.local/share/plank/themes'

sec "статус смены темы"
printf 'статус      %s\n' "$(cat "$BDI_CACHE/theme-status" 2>/dev/null || echo 'нет (тему не меняли)')"
printf 'схема       %s / режим %s\n' "$(cat "$BDI_CONFIG/current" 2>/dev/null || echo '?')" \
  "$(cat "$BDI_CONFIG/mode" 2>/dev/null || echo '?')"
for _t in theme theme-extra colors-pick; do
  printf 'лог %-12s\n' "$_t"
  [ -f "$BDI_CACHE/$_t.log" ] && tail -6 "$BDI_CACHE/$_t.log" 2>/dev/null || echo '  пусто'
done

echo
echo 'Скопируйте весь этот вывод целиком.'

# Имя пользователя из путей убираем: отчёт присылают публично.
sed -e "s#$HOME#~#g" -e "s#/home/[^/ ]*#~#g" \
    -e "s#--dest=[^ ]*#--dest=… #g" "$_OUT" >&3
rm -f "$_OUT"
