#!/bin/sh
# selftest-guard.sh - проверка на заглушках: смена темы не виснет, соты
# запускаются и честно падают.
#
# Запускать ИЗОЛИРОВАННО (правило в AGENTS.md): своя шина D-Bus, HOME и XDG
# в /tmp. Реальные Plank, xfconf, dconf не трогаются.
#
#   env -u DBUS_SESSION_BUS_ADDRESS -u XDG_RUNTIME_DIR HOME=/tmp/fakehome \
#       XDG_CONFIG_HOME=/tmp/fakehome/.config XDG_STATE_HOME=/tmp/fakehome/.local/state \
#       XDG_CACHE_HOME=/tmp/fakehome/.cache \
#       dbus-run-session -- sh scripts/selftest-guard.sh
#
# Код 0 - всё сошлось.
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BASE="${TMPDIR:-/tmp}/bdi-guard"
fail=0

check() { # check <что> <ожидалось> <получено>
  if [ "$2" = "$3" ]; then printf 'ok   %s\n' "$1"
  else printf 'FAIL %s: ждали [%s], получили [%s]\n' "$1" "$2" "$3"; fail=1; fi
}

# --- общая песочница ------------------------------------------------------
mk_sandbox() {
  rm -rf "$BASE"
  mkdir -p "$BASE/home/.config/bdi" "$BASE/home/.cache/bdi" \
           "$BASE/bin" "$BASE/home/.local/share/plank/themes"
  cp -r /usr/share/plank/themes/Default "$BASE/home/.local/share/plank/themes/" 2>/dev/null || true
  export HOME="$BASE/home"
  export BDI_CONFIG="$BASE/home/.config/bdi"
  export BDI_CACHE="$BASE/home/.cache/bdi"
}

# --- 1. run_to: таймаут срабатывает ---------------------------------------
. "$ROOT/theme/guard.sh"
_t0=$(date +%s)
run_to 2 sleep 30
_rc=$?
_t1=$(date +%s)
check "run_to обрывает зависший вызов" 124 "$_rc"
check "run_to уложился в таймаут" 1 "$(( (_t1 - _t0) < 5 ? 1 : 0 ))"

# --- 2. theme/plank.sh: висящий dconf не вешает скрипт --------------------
mk_sandbox
printf '#!/bin/sh\nsleep 600\n' > "$BASE/bin/dconf"
printf '#!/bin/sh\nsleep 600\n' > "$BASE/bin/gsettings"
printf '#!/bin/sh\nexit 0\n' > "$BASE/bin/plank"
printf '#!/bin/sh\nexit 1\n' > "$BASE/bin/pgrep"
printf '#!/bin/sh\nexit 1\n' > "$BASE/bin/pkill"
printf '#!/bin/sh\nexit 1\n' > "$BASE/bin/wmctrl"
chmod +x "$BASE/bin"/*
# Действующий eww/colors.scss не трогаем: зависание ловится на dconf read,
# а он идёт раньше чтения CSS. Если бы тест упал посередине с подменённым
# CSS, остров остался бы без темы - на машине владельца это недопустимо.

_t0=$(date +%s)
out=$(PATH="$BASE/bin:$PATH" timeout 40 sh "$ROOT/theme/plank.sh" apply 2>&1)
_rc=$?
_t1=$(date +%s)
check "plank.sh не виснет на dconf" 0 "$_rc"
check "plank.sh уложился в 40 с" 1 "$(( (_t1 - _t0) < 40 ? 1 : 0 ))"
case "$out" in
  *"dconf не ответил"*) printf 'ok   plank.sh сказал причину\n' ;;
  *) printf 'FAIL plank.sh: нет причины в выводе [%s]\n' "$out"; fail=1 ;;
esac
grep -q "dconf не ответил" "$BDI_CACHE/plank.log" &&
  printf 'ok   причина в plank.log\n' ||
  { printf 'FAIL причина не в plank.log\n'; fail=1; }

# --- 3. соты: бинарник падает сразу -> код 4 и причина в лог ---------------
mk_sandbox
printf '#!/bin/sh\necho "INFO: Initializing raylib 6.2"\n'\
'echo "ERROR: GLFW: Failed to initialize GLFW" >&2\nexit 1\n' > "$BASE/bin/wallpicker"
chmod +x "$BASE/bin/wallpicker"
mkdir -p "$BASE/walls"
printf 'not really a png\n' > "$BASE/walls/a.png"

_t0=$(date +%s)
out=$(WALLPICKER_BIN="$BASE/bin/wallpicker" WALLPAPER_DIR="$BASE/walls" \
      PATH="$BASE/bin:$PATH" timeout 30 sh "$ROOT/adapters/wallpicker/run.sh" 2>&1)
_rc=$?
_t1=$(date +%s)
check "соты: падение распознано кодом 4" 4 "$_rc"
check "соты: не ждём 20 с впустую" 1 "$(( (_t1 - _t0) < 10 ? 1 : 0 ))"
case "$out" in
  *"вышла сразу"*|*"не запустились"*) printf 'ok   соты сказали причину\n' ;;
  *) printf 'FAIL соты: нет причины в выводе [%s]\n' "$out"; fail=1 ;;
esac
grep -q "ошибка: wallpicker вышел" "$BDI_CACHE/wallpicker.log" &&
  printf 'ok   причина в wallpicker.log\n' ||
  { printf 'FAIL причина не в wallpicker.log\n'; fail=1; }

# --- 4. соты: бинарник из build/ находится, даже если ссылки нет ----------
mk_sandbox
printf '#!/bin/sh\nexit 1\n' > "$BASE/bin/wallpicker"
chmod +x "$BASE/bin/wallpicker"
mkdir -p "$BASE/walls"
# Картинка обязательна: пустую папку run.sh теперь отсекает кодом 5 и до
# запуска не доходит (это проверяет отдельный случай ниже).
printf 'not really a png\n' > "$BASE/walls/a.png"
out=$(WALLPAPER_DIR="$BASE/walls" PATH="$BASE/bin:$PATH" \
      timeout 20 sh "$ROOT/adapters/wallpicker/run.sh" 2>&1)
grep -q "запуск: pid" "$BDI_CACHE/wallpicker.log" &&
  printf 'ok   запуск логируется с pid\n' ||
  { printf 'FAIL запуск не залогирован\n'; fail=1; }

# --- 4b. соты: пустая папка -> код 5, программа не запускается ------------
mk_sandbox
printf '#!/bin/sh\necho "$*" >> "$BDI_CACHE/wp.called"\nexit 0\n' > "$BASE/bin/wallpicker"
chmod +x "$BASE/bin/wallpicker"
mkdir -p "$BASE/walls"
out=$(WALLPICKER_BIN="$BASE/bin/wallpicker" WALLPAPER_DIR="$BASE/walls" \
      PATH="$BASE/bin:$PATH" timeout 20 sh "$ROOT/adapters/wallpicker/run.sh" 2>&1)
_rc=$?
check "пустая папка обоев -> код 5" 5 "$_rc"
case "$out" in
  *"нет обоев"*) printf 'ok   пустая папка названа вслух\n' ;;
  *) printf 'FAIL пустая папка: нет сообщения [%s]\n' "$out"; fail=1 ;;
esac
[ -f "$BDI_CACHE/wp.called" ] &&
  { printf 'FAIL программа запущена на пустой папке\n'; fail=1; } ||
  printf 'ok   на пустой папке программа не запускается\n'

# --- 5. кнопка обоев: соты упали -> код 4, запасной НЕ открывается --------
# Раньше любой провал молча открывал xfdesktop-settings, и причину было не
# видно. Теперь запасной путь только для «программы нет» (код 1).
mk_sandbox
printf '#!/bin/sh\nexit 1\n' > "$BASE/bin/wallpicker"
printf '#!/bin/sh\necho "xfdesktop-settings запущен" >> "$BDI_CACHE/fallback.called"\n' > "$BASE/bin/xfdesktop-settings"
printf '#!/bin/sh\nexit 1\n' > "$BASE/bin/wmctrl"
printf '#!/bin/sh\nexit 0\n' > "$BASE/bin/notify-send"
chmod +x "$BASE/bin"/*
mkdir -p "$BASE/walls"
printf 'not really a png\n' > "$BASE/walls/a.png"

WALLPICKER_BIN="$BASE/bin/wallpicker" WALLPAPER_DIR="$BASE/walls" \
  PATH="$BASE/bin:$PATH" timeout 40 sh "$ROOT/adapters/x11/wallpaper.sh" >/dev/null 2>&1
_rc=$?
check "кнопка обоев: падение сот -> код 4" 4 "$_rc"
[ -f "$BDI_CACHE/fallback.called" ] &&
  { printf 'FAIL запасной настройщик открылся молча\n'; fail=1; } ||
  printf 'ok   запасной настройщик не открылся\n'
grep -q "wallpicker не запустился" "$BDI_CACHE/wallpicker.log" &&
  printf 'ok   причина записана в лог\n' ||
  { printf 'FAIL причины нет в логе\n'; fail=1; }

# --- 5b. кнопка обоев: программы нет (код 1) -> запасной открывается ------
mk_sandbox
printf '#!/bin/sh\necho "xfdesktop-settings запущен" >> "$BDI_CACHE/fallback.called"\n' > "$BASE/bin/xfdesktop-settings"
printf '#!/bin/sh\nexit 1\n' > "$BASE/bin/wmctrl"
printf '#!/bin/sh\nexit 0\n' > "$BASE/bin/notify-send"
chmod +x "$BASE/bin"/*
mkdir -p "$BASE/walls"; printf 'x\n' > "$BASE/walls/a.png"

WALLPICKER_BIN="$BASE/bin/нет-такой" WALLPAPER_DIR="$BASE/walls" \
  PATH="$BASE/bin:$PATH" timeout 40 sh "$ROOT/adapters/x11/wallpaper.sh" >/dev/null 2>&1
[ -f "$BDI_CACHE/fallback.called" ] &&
  printf 'ok   нет программы -> запасной настройщик открыт\n' ||
  { printf 'FAIL нет программы, а настройщик не открылся\n'; fail=1; }

# --- 6. apply.sh: reload «ответил», а главный цикл залип -> перезапуск ------
# Дерево-двойник: настоящие theme/*, но scripts/stop-island.sh и run-island.sh
# - заглушки, а eww изображает настоящий IPC: reload отвечает 0 сразу (сервер
# ждёт главный цикл лишь 100 мс), state - пусто, пока цикл занят.
mk_sandbox
FAKE="$BASE/root"
mkdir -p "$FAKE/theme" "$FAKE/scripts" "$FAKE/eww/assets" "$FAKE/build/target/release"
cp "$ROOT/theme/apply.sh" "$ROOT/theme/guard.sh" "$FAKE/theme/"
ln -s "$ROOT/theme/schemes" "$FAKE/theme/schemes"
ln -s "$ROOT/theme/templates" "$FAKE/theme/templates"
printf '#!/bin/sh\nexit 0\n' > "$FAKE/theme/plank.sh"
printf '#!/bin/sh\nexit 0\n' > "$FAKE/theme/ulauncher.sh"
printf '#!/bin/sh\necho stop >> "$BDI_CACHE/restart.called"\n' > "$FAKE/scripts/stop-island.sh"
printf '#!/bin/sh\necho start >> "$BDI_CACHE/restart.called"\n' > "$FAKE/scripts/run-island.sh"
printf '#!/bin/sh\ncase "$*" in *reload*) exit 0 ;; *state*) exit 0 ;; esac\nexit 0\n' \
  > "$FAKE/build/target/release/eww"
chmod +x "$FAKE/theme/apply.sh" "$FAKE/theme/plank.sh" "$FAKE/theme/ulauncher.sh" \
         "$FAKE/scripts/stop-island.sh" "$FAKE/scripts/run-island.sh" \
         "$FAKE/build/target/release/eww"

_t0=$(date +%s)
out=$(timeout 90 sh "$FAKE/theme/apply.sh" default --reload 2>&1)
_rc=$?
_t1=$(date +%s)
check "apply.sh не виснет на залипшем reload" 0 "$_rc"
check "apply.sh уложился в 60 с" 1 "$(( (_t1 - _t0) < 60 ? 1 : 0 ))"
check "демон остановлен и поднят заново" "stop start" \
  "$(tr '\n' ' ' < "$BDI_CACHE/restart.called" 2>/dev/null | sed 's/ $//')"
grep -q "не ответил на state" "$BDI_CACHE/theme.log" &&
  printf 'ok   причина в theme.log\n' ||
  { printf 'FAIL причины нет в theme.log\n'; fail=1; }

# --- 7. apply.sh: живой главный цикл -> перезапуска нет --------------------
mk_sandbox
FAKE="$BASE/root"
mkdir -p "$FAKE/theme" "$FAKE/scripts" "$FAKE/eww/assets" "$FAKE/build/target/release"
cp "$ROOT/theme/apply.sh" "$ROOT/theme/guard.sh" "$FAKE/theme/"
ln -s "$ROOT/theme/schemes" "$FAKE/theme/schemes"
ln -s "$ROOT/theme/templates" "$FAKE/theme/templates"
printf '#!/bin/sh\nexit 0\n' > "$FAKE/theme/plank.sh"
printf '#!/bin/sh\nexit 0\n' > "$FAKE/theme/ulauncher.sh"
printf '#!/bin/sh\necho stop >> "$BDI_CACHE/restart.called"\n' > "$FAKE/scripts/stop-island.sh"
printf '#!/bin/sh\necho start >> "$BDI_CACHE/restart.called"\n' > "$FAKE/scripts/run-island.sh"
printf '#!/bin/sh\ncase "$*" in *state*) echo "hub_tab: 0"; exit 0 ;; esac\nexit 0\n' \
  > "$FAKE/build/target/release/eww"
chmod +x "$FAKE/theme/apply.sh" "$FAKE/theme/plank.sh" "$FAKE/theme/ulauncher.sh" \
         "$FAKE/scripts/stop-island.sh" "$FAKE/scripts/run-island.sh" \
         "$FAKE/build/target/release/eww"

_t0=$(date +%s)
timeout 60 sh "$FAKE/theme/apply.sh" default --reload >/dev/null 2>&1
_rc=$?
_t1=$(date +%s)
check "живой reload не перезапускает демон" 0 "$_rc"
[ -f "$BDI_CACHE/restart.called" ] &&
  { printf 'FAIL демон перезапущен зря\n'; fail=1; } ||
  printf 'ok   перезапуска нет\n'
check "живой reload быстрый" 1 "$(( (_t1 - _t0) < 10 ? 1 : 0 ))"

# --- 8. stop-island.sh: висящий `eww kill` не держит аварийный путь --------
mk_sandbox
STOPROOT="$BASE/stoproot"
mkdir -p "$STOPROOT/scripts" "$STOPROOT/lib" "$STOPROOT/theme" "$STOPROOT/eww" \
         "$STOPROOT/build/target/release"
cp "$ROOT/scripts/stop-island.sh" "$STOPROOT/scripts/"
cp "$ROOT/lib/eww-proc.sh" "$STOPROOT/lib/"
cp "$ROOT/theme/guard.sh" "$STOPROOT/theme/"
printf '#!/bin/sh\nsleep 600\n' > "$STOPROOT/build/target/release/eww"
chmod +x "$STOPROOT/build/target/release/eww" "$STOPROOT/scripts/stop-island.sh"

_t0=$(date +%s)
timeout 40 sh "$STOPROOT/scripts/stop-island.sh" >/dev/null 2>&1
_rc=$?
_t1=$(date +%s)
check "stop-island.sh не виснет на eww kill" 0 "$_rc"
check "stop-island.sh уложился в 20 с" 1 "$(( (_t1 - _t0) < 20 ? 1 : 0 ))"

# --- 9. смена темы: второй запуск во время первого не стартует ------------
# Проверяем именно pid-файл, без настоящей смены темы: подменяем apply.sh
# заглушкой, которая спит, и зовём colors-pick дважды.
mk_sandbox
PICKROOT="$BASE/pickroot"
mkdir -p "$PICKROOT/theme" "$PICKROOT/eww" "$PICKROOT/adapters/x11"
cp "$ROOT/theme/colors-pick.sh" "$ROOT/theme/guard.sh" "$PICKROOT/theme/"
printf '#!/bin/sh\nprintf "apply\\n" >> "$BDI_CACHE/apply.called"\nsleep 3\n' \
  > "$PICKROOT/theme/apply.sh"
printf '#!/bin/sh\nexit 1\n' > "$PICKROOT/theme/from-wallpaper.sh"
printf '#!/bin/sh\nexit 1\n' > "$PICKROOT/adapters/x11/panel.sh"
chmod +x "$PICKROOT/theme/"*.sh "$PICKROOT/adapters/x11/panel.sh"

BDI_NO_DETACH=1 timeout 20 sh "$PICKROOT/theme/colors-pick.sh" hue all >/dev/null 2>&1
BDI_NO_DETACH=1 timeout 20 sh "$PICKROOT/theme/colors-pick.sh" palette n-island dark >/dev/null 2>&1 &
sleep 0.5
BDI_NO_DETACH=1 timeout 20 sh "$PICKROOT/theme/colors-pick.sh" palette light dark >/dev/null 2>&1
check "второй запуск отброшен" 1 "$(grep -c 'уже применяется' "$BDI_CACHE/colors-pick.log" 2>/dev/null | head -1)"
wait
check "первый запуск дошёл до apply" 1 "$(grep -c 'apply' "$BDI_CACHE/apply.called" 2>/dev/null | head -1)"
[ -f "$BDI_CACHE/colors-pick.pid" ] &&
  { printf 'FAIL pid-файл остался после выхода\n'; fail=1; } ||
  printf 'ok   pid-файл убран\n'

# --- 10. apply.sh: док и лаунчер уходят в фон, кнопка не ждёт их ----------
# Заглушки plank/ulauncher спят 5 с. Основной путь должен вернуться быстро,
# а в theme.log появиться «шаг render» (замер) - раньше шагов вообще не было.
mk_sandbox
FAKE="$BASE/root"
mkdir -p "$FAKE/theme" "$FAKE/scripts" "$FAKE/eww/assets" "$FAKE/build/target/release"
cp "$ROOT/theme/apply.sh" "$ROOT/theme/guard.sh" "$ROOT/theme/extras.sh" "$FAKE/theme/"
ln -s "$ROOT/theme/schemes" "$FAKE/theme/schemes"
ln -s "$ROOT/theme/templates" "$FAKE/theme/templates"
printf '#!/bin/sh\nsleep 5\n' > "$FAKE/theme/plank.sh"
printf '#!/bin/sh\nsleep 5\n' > "$FAKE/theme/ulauncher.sh"
printf '#!/bin/sh\ncase "$*" in *state*) echo "hub_tab: 0"; exit 0 ;; esac\nexit 0\n' \
  > "$FAKE/build/target/release/eww"
chmod +x "$FAKE/theme/"*.sh "$FAKE/build/target/release/eww"

_t0=$(date +%s)
timeout 60 sh "$FAKE/theme/apply.sh" default --reload >/dev/null 2>&1
_rc=$?
_t1=$(date +%s)
check "apply.sh вернул 0" 0 "$_rc"
check "apply.sh не ждёт док и лаунчер (5 с каждый)" 1 "$(( (_t1 - _t0) < 5 ? 1 : 0 ))"
grep -q "шаг render" "$BDI_CACHE/theme.log" &&
  printf 'ok   шаг render замерен\n' ||
  { printf 'FAIL замера шагов нет в theme.log\n'; fail=1; }
sleep 6
grep -q "шаг plank" "$BDI_CACHE/theme.log" &&
  printf 'ok   фон догнал док\n' ||
  { printf 'FAIL фон не дошёл до дока\n'; fail=1; }

# --- 11. портативность: не возвращать gawk-функции в awk -------------------
# Проверено по шаблону void-packages/base-system: Void ставит gawk и coreutils,
# то есть `strtonum` там есть, а вот `date +%s%N`, `stat -c`, `readlink -f` тем
# более работают - их трогать не нужно (в задании 17 они были в списке
# подозреваемых, но в реальности на обеих целевых системах это GNU-утилиты).
# Остаётся один настоящий риск: awk бывает mawk (Debian, часть сборок Void),
# и `strtonum` в нём нет - тогда island-geom.sh молча терял геометрию острова.
_hits=$(grep -rn 'strtonum' --include='*.sh' "$ROOT/adapters" "$ROOT/lib" \
          "$ROOT/scripts" "$ROOT/theme" 2>/dev/null | grep -v 'selftest-guard' \
          | grep -v '^[^:]*:[0-9]*: *#' | head -3)
[ -z "$_hits" ] && printf 'ok   нет gawk-функции strtonum\n' ||
  { printf 'FAIL strtonum вернулся:\n%s\n' "$_hits"; fail=1; }

# --- 12. охрана сеанса: без X11+XFCE установка и остров не идут -------------
# Пять случаев из задания 17, часть C. bdi_session_ok ничего не печатает и
# не меняет - проверяем только код возврата.
check "wayland отклонён" 1 \
  "$(env -i XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=Hyprland \
      sh -c '. "$1/lib/session.sh"; bdi_session_ok' sh "$ROOT" >/dev/null 2>&1; echo $?)"
check "x11+Hyprland отклонён" 1 \
  "$(env -i XDG_SESSION_TYPE=x11 XDG_CURRENT_DESKTOP=Hyprland DISPLAY=:0 \
      sh -c '. "$1/lib/session.sh"; bdi_session_ok' sh "$ROOT" >/dev/null 2>&1; echo $?)"
check "x11+XFCE разрешён" 0 \
  "$(env -i XDG_SESSION_TYPE=x11 XDG_CURRENT_DESKTOP=XFCE DISPLAY=:0 \
      sh -c '. "$1/lib/session.sh"; bdi_session_ok' sh "$ROOT" >/dev/null 2>&1; echo $?)"
check "без переменных, но DISPLAY есть" 0 \
  "$(env -i DISPLAY=:0 \
      sh -c '. "$1/lib/session.sh"; bdi_session_ok' sh "$ROOT" >/dev/null 2>&1; echo $?)"
check "нет ни сеанса, ни DISPLAY" 1 \
  "$(env -i sh -c '. "$1/lib/session.sh"; bdi_session_ok' sh "$ROOT" >/dev/null 2>&1; echo $?)"

# --- 13. run-island.sh в чужом сеансе: код 1 и причина, без запуска ---------
_out=$(env -i HOME="$BASE/home" PATH="$PATH" XDG_SESSION_TYPE=wayland \
         XDG_CURRENT_DESKTOP=Hyprland sh "$ROOT/scripts/run-island.sh" 2>&1)
check "run-island в Wayland: код 1" 1 "$?"
case "$_out" in
  *"остров не запущен"*Wayland*) printf 'ok   run-island сказал причину\n' ;;
  *) printf 'FAIL run-island: нет причины [%s]\n' "$_out"; fail=1 ;;
esac

# --- 14. install.sh в чужом сеансе: отказ до каких-либо действий -----------
_out=$(env -i HOME="$BASE/home" PATH="$PATH" XDG_SESSION_TYPE=wayland \
         XDG_CURRENT_DESKTOP=Hyprland sh "$ROOT/install.sh" install 2>&1)
check "install в Wayland: код 1" 1 "$?"
case "$_out" in
  *"не выполн"*) printf 'ok   install сказал причину\n' ;;
  *) printf 'FAIL install: нет причины [%s]\n' "$_out"; fail=1 ;;
esac
[ ! -f "$BASE/home/.local/state/bdi/changes.log" ] &&
  printf 'ok   install ничего не записал\n' ||
  { printf 'FAIL install оставил журнал в чужом сеансе\n'; fail=1; }

# --- 15. автозапуск: OnlyShowIn и гашение старого файла ---------------------
mk_sandbox
mkdir -p "$BASE/home/.config/autostart"
printf '[Desktop Entry]\nType=Application\nExec=%s/scripts/run-island.sh\nHidden=false\n' \
  "$ROOT" > "$BASE/home/.config/autostart/eww-island.desktop"
printf '[Desktop Entry]\nType=Application\nExec=чужое\n' \
  > "$BASE/home/.config/autostart/foreign.desktop"
BDI_STATE="$BASE/home/.local/state/bdi" \
  sh -c '. "$1/lib/log.sh"; . "$1/lib/journal.sh"; . "$1/lib/install.sh";
         ROOT=$1; install_autostart >/dev/null; disable_stale_autostart >/dev/null' \
  sh "$ROOT" 2>/dev/null
check "новая запись с OnlyShowIn=XFCE;" 1 \
  "$(grep -c '^OnlyShowIn=XFCE;' "$BASE/home/.config/autostart/bdi.desktop" 2>/dev/null)"
check "старый наш автозапуск погашен" 1 \
  "$(grep -c '^Hidden=true' "$BASE/home/.config/autostart/eww-island.desktop" 2>/dev/null)"
check "чужой автозапуск не тронут" 0 \
  "$(grep -c '^Hidden=' "$BASE/home/.config/autostart/foreign.desktop" 2>/dev/null)"
check "повтор: запись осталась одна" 1 \
  "$(sh -c '. "$1/lib/log.sh"; . "$1/lib/journal.sh"; . "$1/lib/install.sh";
            ROOT=$1; install_autostart >/dev/null; ls "$HOME/.config/autostart"/*.desktop | wc -l' \
       sh "$ROOT" 2>/dev/null | grep -c . )"

# --- 16. процессы: pkill по имени не осталось -------------------------------
# pkill -x plank убивал бы док другого пользователя, если он в этой же машине.
_hits=$(grep -rn 'pkill\|killall' --include='*.sh' "$ROOT/adapters" "$ROOT/lib" \
          "$ROOT/scripts" "$ROOT/theme" 2>/dev/null | grep -v 'selftest-guard' \
          | grep -v '^[^:]*:[0-9]*: *#' | grep -v 'pw-play')
[ -z "$_hits" ] && printf 'ok   нет pkill/killall по имени\n' ||
  { printf 'FAIL pkill по имени вернулся:\n%s\n' "$_hits"; fail=1; }

# --- 17. своя тема не пишется в каталог Noctalia ----------------------------
check "theme-save пишет в свой каталог" 1 \
  "$(grep -c 'PALETTES_DIR:-\$BDI_CONFIG/palettes' "$ROOT/theme/theme-save.sh")"
check "Plank: имя темы с префиксом bdi-" 1 \
  "$(grep -c '^THEME_NAME=bdi-' "$ROOT/theme/plank.sh")"

# --- 18. откат без X и без шины: install -> uninstall -> те же хэши --------
# Главная проверка части D. Песочница со своей копией ROOT: uninstall зовёт
# stop-island.sh и ищет демона по этому пути - живой остров не тронут.
DROOT="$BASE/d-root"
DHOME="$BASE/d-home"
DXML="$DHOME/.config/xfce4/xfconf/xfce-perchannel-xml"
rm -rf "$DROOT" "$DHOME"
mkdir -p "$DROOT/lib" "$DROOT/scripts" "$DROOT/theme" "$DXML" \
         "$DHOME/.local/state/bdi" "$DHOME/.config/autostart"
cp "$ROOT/install.sh" "$DROOT/"
cp -r "$ROOT/lib/." "$DROOT/lib/"
cp "$ROOT/scripts/stop-island.sh" "$DROOT/scripts/"
cp "$ROOT/theme/guard.sh" "$DROOT/theme/"
# Настройки с ВКЛЮЧЁННОЙ панелью: на живой она уже отключена, и install_panel
# вышел бы сразу, откатывать было бы нечего.
printf '<?xml version="1.1" encoding="UTF-8"?>\n\n<channel name="xfce4-session" version="1.0">\n  <property name="sessions" type="empty">\n    <property name="Failsafe" type="empty">\n      <property name="Client2_Command" type="string" value="xfce4-panel"/>\n    </property>\n  </property>\n</channel>\n' \
  > "$DXML/xfce4-session.xml"
dgrep() { grep -o 'name="Client2_Command"[^/]*' "$DXML/xfce4-session.xml" | head -1; }

# Заготовку приводит к каноничному виду сам xfconfd: при install он всё равно
# перепишет канал целиком (свои пустые ключи, свой порядок), и «тот же хэш»
# иначе недостижим. Значение специально меняем и возвращаем - на неизменном
# значении xfconfd файл не трогает, и заготовка осталась бы неканоничной.
env -i PATH="$PATH" HOME="$DHOME" XDG_CONFIG_HOME="$DHOME/.config" \
    XDG_CACHE_HOME="$DHOME/.cache" DISPLAY=:99 \
  dbus-run-session -- sh -c '
    xfconf-query -c xfce4-session -p /sessions/Failsafe/Client2_Command -n -t string -s true
    xfconf-query -c xfce4-session -p /sessions/Failsafe/Client2_Command -n -t string -s xfce4-panel
  ' >/dev/null 2>&1
_d1=$(md5sum "$DXML/xfce4-session.xml" | cut -d' ' -f1)

env -i PATH="$PATH" HOME="$DHOME" XDG_CONFIG_HOME="$DHOME/.config" \
    XDG_STATE_HOME="$DHOME/.local/state" XDG_CACHE_HOME="$DHOME/.cache" \
    DISPLAY=:99 XDG_SESSION_TYPE=x11 XDG_CURRENT_DESKTOP=XFCE \
    BDI_CONFIG="$DHOME/.config/bdi" BDI_STATE="$DHOME/.local/state/bdi" \
    BDI_CACHE="$DHOME/.cache/bdi" \
  dbus-run-session -- sh -c '
    . "$1/lib/log.sh"; . "$1/lib/journal.sh"; . "$1/lib/install.sh"
    ROOT=$1; BDI_CONFIG=$HOME/.config/bdi
    install_panel; install_autostart; install_extras
  ' sh "$DROOT" >/dev/null 2>&1
check "install: панель отключена" 'name="Client2_Command" type="bool" value="true"' "$(dgrep)"
check "install: автозапуск 3 файла" "3" \
  "$(ls "$DHOME/.config/autostart/" 2>/dev/null | wc -l | tr -d ' ')"
check "install: в журнале 4 записи" "4" \
  "$(grep -c . "$DHOME/.local/state/bdi/changes.log" 2>/dev/null)"

# Без DISPLAY и без DBUS_SESSION_BUS_ADDRESS - как из TTY или Hyprland.
env -i PATH="$PATH" HOME="$DHOME" XDG_CONFIG_HOME="$DHOME/.config" \
    XDG_STATE_HOME="$DHOME/.local/state" XDG_CACHE_HOME="$DHOME/.cache" \
    BDI_CONFIG="$DHOME/.config/bdi" BDI_STATE="$DHOME/.local/state/bdi" \
    BDI_CACHE="$DHOME/.cache/bdi" \
  sh "$DROOT/install.sh" uninstall >/dev/null 2>&1
check "uninstall без X: код 0" "0" "$?"
check "uninstall вернул панель" 'name="Client2_Command" type="string" value="xfce4-panel"' "$(dgrep)"
check "uninstall вернул тип string" "1" \
  "$(grep -c 'name="Client2_Command" type="string"' "$DXML/xfce4-session.xml")"
# Повторная запись того же значения не должна менять файл: так проверяется,
# что откат идемпотентен и пишет в формате xfconfd (тот при install всё равно
# переписывает канал целиком, поэтому «хэш как до install» недостижим).
check "uninstall: XML без изменений" "$_d1" \
  "$(md5sum "$DXML/xfce4-session.xml" | cut -d' ' -f1)"
check "uninstall: автозапуск убран" "0" \
  "$(ls "$DHOME/.config/autostart/" 2>/dev/null | wc -l | tr -d ' ')"

# --- 19. откат dconf и json: чужие настройки целы --------------------------
rm -rf "$DHOME/.config/autostart"; mkdir -p "$DHOME/.config/ulauncher"
printf '{\n    "show-recent-apps": 3,\n    "clear-on-hide": false\n}\n' \
  > "$DHOME/.config/ulauncher/settings.json"
printf '%s\n' \
  "$(printf '2026-11-23 10:00:00\tdconf\t/net/launchpad/plank/docks/dock1/theme\tEwwIsland\tbdi-EwwIsland\t')" \
  "$(printf '2026-11-23 10:00:01\tjson\t%s\tshow-recent-apps=0\tshow-recent-apps=5\t' \
     "$DHOME/.config/ulauncher/settings.json")" \
  > "$DHOME/.local/state/bdi/changes.log"
env -i PATH="$PATH" HOME="$DHOME" XDG_CONFIG_HOME="$DHOME/.config" \
    XDG_STATE_HOME="$DHOME/.local/state" XDG_CACHE_HOME="$DHOME/.cache" \
    BDI_STATE="$DHOME/.local/state/bdi" \
  sh "$DROOT/install.sh" uninstall >/dev/null 2>&1
check "json вернул поле" "0" \
  "$(python3 -c "import json;print(json.load(open('$DHOME/.config/ulauncher/settings.json'))['show-recent-apps'])" 2>/dev/null)"
check "json: чужой ключ цел" "False" \
  "$(python3 -c "import json;print(json.load(open('$DHOME/.config/ulauncher/settings.json'))['clear-on-hide'])" 2>/dev/null)"
check "json: файл не удалён" "да" \
  "$([ -f "$DHOME/.config/ulauncher/settings.json" ] && echo да || echo нет)"
# Без шины dconf не пишется - откат обязан сказать об этом и дать команду.
_out=$(env -i PATH="$PATH" HOME="$DHOME" XDG_CONFIG_HOME="$DHOME/.config" \
        XDG_CACHE_HOME="$DHOME/.cache" BDI_STATE="$DHOME/.local/state/bdi" \
        DISPLAY=:99 XDG_SESSION_TYPE=x11 \
        sh -c 'printf "%s\n" "$(printf "2026-11-23 10:00:00\tdconf\t/net/x/y\tEwwIsland\tbdi-EwwIsland\t")" > "'"$DHOME"'/.local/state/bdi/changes.log"
               sh "'"$DROOT"'/install.sh" uninstall' 2>&1)
case "$_out" in
  *"dconf write"*) printf 'ok   dconf без шины: сказал и дал команду\n' ;;
  *) printf 'FAIL dconf без шины молчит [%s]\n' "$_out"; fail=1 ;;
esac

# --- 20. файл копии: старый автозапуск возвращается, а не удаляется --------
rm -rf "$DHOME/.config/autostart"; mkdir -p "$DHOME/.config/autostart"
printf '[Desktop Entry]\nExec=/x/run-island.sh\nHidden=true\n' \
  > "$DHOME/.config/autostart/eww-island.desktop"
printf '%s\n' \
  "$(printf '2026-11-23 10:00:00\tautostart\t%s\tHidden=false\tHidden=true\t' \
     "$DHOME/.config/autostart/eww-island.desktop")" \
  > "$DHOME/.local/state/bdi/changes.log"
env -i PATH="$PATH" HOME="$DHOME" XDG_CONFIG_HOME="$DHOME/.config" \
    BDI_STATE="$DHOME/.local/state/bdi" \
  sh "$DROOT/install.sh" uninstall >/dev/null 2>&1
check "погашенный автозапуск: Hidden вернулся" "false" \
  "$(sed -n 's/^Hidden=//p' "$DHOME/.config/autostart/eww-island.desktop" 2>/dev/null)"
check "погашенный автозапуск: файл на месте" "да" \
  "$([ -f "$DHOME/.config/autostart/eww-island.desktop" ] && echo да || echo нет)"

# --- 21. пустые поля журнала не сдвигают значения --------------------------
# TAB - whitespace для read, и строка «autostart<файл>""<-Exec» читалась как
# «<файл><-Exec», откат возвращал чужое значение. Поля режет cut.
rm -rf "$DHOME/.config/autostart"; mkdir -p "$DHOME/.config/autostart"
printf '%s\n' \
  "$(printf '2026-11-23 10:00:00\tautostart\t%s\t\t%s\t' \
     "$DHOME/.config/autostart/made.desktop" "/x/run-island.sh")" \
  > "$DHOME/.local/state/bdi/changes.log"
printf '[Desktop Entry]\nExec=/x/run-island.sh\n' > "$DHOME/.config/autostart/made.desktop"
env -i PATH="$PATH" HOME="$DHOME" XDG_CONFIG_HOME="$DHOME/.config" \
    BDI_STATE="$DHOME/.local/state/bdi" \
  sh "$DROOT/install.sh" uninstall >/dev/null 2>&1
check "созданный нами файл удалён" "нет" \
  "$([ -f "$DHOME/.config/autostart/made.desktop" ] && echo да || echo нет)"

# --- 22. журнал с типом: старая строка из 5 полей тоже читается ------------
rm -rf "$DHOME/.config/autostart"; mkdir -p "$DHOME/.config/autostart"
printf '2026-11-23 10:00:00\tautostart\t%s\t\t/x\n' \
  "$DHOME/.config/autostart/old.desktop" > "$DHOME/.local/state/bdi/changes.log"
printf 'x\n' > "$DHOME/.config/autostart/old.desktop"
_out=$(env -i PATH="$PATH" HOME="$DHOME" XDG_CONFIG_HOME="$DHOME/.config" \
        BDI_STATE="$DHOME/.local/state/bdi" \
        sh "$DROOT/install.sh" uninstall 2>&1)
check "журнал из 5 полей: файл удалён" "нет" \
  "$([ -f "$DHOME/.config/autostart/old.desktop" ] && echo да || echo нет)"

# --- 23. Замок одной копии (theme/guard.sh, lock_take) ---------------------
# Раньше был pid-файл: между чтением и записью в него проходили оба запуска.
# Проверено пятью параллельными - файл взяли все пять. Теперь mkdir.
LD=$(mktemp -d)
. "$ROOT/theme/guard.sh"
for i in 1 2 3 4 5 6 7 8; do
  ( if lock_take "$LD/t.lock"; then echo "$$" >> "$LD/took"; sleep 0.2; fi ) &
done
wait
check "замок: из 8 запусков взял ровно 1" 1 "$(wc -l < "$LD/took" 2>/dev/null || echo 0)"

# Мёртвый замок (pid не существует) подхватывается, живой - нет.
mkdir -p "$LD/dead.lock"; printf '999999\n' > "$LD/dead.lock/pid"
lock_take "$LD/dead.lock" && _dead=1 || _dead=0
check "замок от убитого процесса подхвачен" 1 "$_dead"
rm -f "$LD/took"
lock_take "$LD/live.lock" && _t1=1 || _t1=0
lock_take "$LD/live.lock" && _t2=1 || _t2=0
check "второй запуск при живом замке отказал" "1 0" "$_t1 $_t2"
check "замок назвал pid занявшего" "да" "$([ -n "${LOCK_PID:-}" ] && echo да || echo нет)"
rm -rf "$LD"

# --- 24. Папка обоев: всегда ~/Изображения --------------------------------
# Решение владельца 2026-11-23. Раньше шёл перебор (xdg-user-dir, ~/Pictures,
# ~/Изображения), и пустая ~/Pictures перекрывала сорок обоев рядом.
WD=$(mktemp -d)
mkdir -p "$WD/h/Изображения"
printf 'x' > "$WD/h/Изображения/w.png"
_wd=$(env -i PATH="$PATH" HOME="$WD/h" XDG_CONFIG_HOME="$WD/h/.config" \
       BDI_CONFIG="$WD/h/.config/bdi" \
       sh -c ". $ROOT/lib/wallpaper.sh; bdi_wallpaper_dir")
check "обои: по умолчанию ~/Изображения" "$WD/h/Изображения" "$_wd"

# Пустая ~/Pictures не должна перекрывать: её в списке кандидатов больше нет.
mkdir -p "$WD/h/Pictures"
_wd=$(env -i PATH="$PATH" HOME="$WD/h" XDG_CONFIG_HOME="$WD/h/.config" \
       BDI_CONFIG="$WD/h/.config/bdi" \
       sh -c ". $ROOT/lib/wallpaper.sh; bdi_wallpaper_dir")
check "обои: пустой Pictures не перекрывает" "$WD/h/Изображения" "$_wd"

# Явный выбор владельца главнее - нужен для второй папки и для тестов.
_wd=$(env -i PATH="$PATH" HOME="$WD/h" XDG_CONFIG_HOME="$WD/h/.config" \
       BDI_CONFIG="$WD/h/.config/bdi" BDI_WALLPAPERS="$WD/h/Мои обои" \
       sh -c ". $ROOT/lib/wallpaper.sh; bdi_wallpaper_dir")
check "обои: явный выбор владельца главнее" "$WD/h/Мои обои" "$_wd"
rm -rf "$WD"

printf '\n'
if [ "$fail" -eq 0 ]; then echo "всё сошлось"; else echo "есть провалы"; fi
exit "$fail"
