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

# --- 4. соты: net возни -> бинарник из build/ находится --------------------
mk_sandbox
printf '#!/bin/sh\nexit 1\n' > "$BASE/bin/wallpicker"
chmod +x "$BASE/bin/wallpicker"
mkdir -p "$BASE/walls"
cp "$ROOT/build/wallpicker-src/wallpicker" "$BASE/bin/real-wp" 2>/dev/null || true
# Заглушка вместо настоящего окна: пусть падает, важен только выбор пути.
out=$(WALLPAPER_DIR="$BASE/walls" PATH="$BASE/bin:$PATH" \
      timeout 20 sh "$ROOT/adapters/wallpicker/run.sh" 2>&1)
grep -q "запуск: pid" "$BDI_CACHE/wallpicker.log" &&
  printf 'ok   запуск логируется с pid\n' ||
  { printf 'FAIL запуск не залогирован\n'; fail=1; }

# --- 5. кнопка обоев: соты падают -> запасной вариант и причина в лог ------
mk_sandbox
printf '#!/bin/sh\nexit 1\n' > "$BASE/bin/wallpicker"
printf '#!/bin/sh\necho "xfdesktop-settings запущен" >> "$BDI_CACHE/fallback.called"\n' > "$BASE/bin/xfdesktop-settings"
printf '#!/bin/sh\nexit 1\n' > "$BASE/bin/wmctrl"
chmod +x "$BASE/bin"/*
mkdir -p "$BASE/walls"
printf 'not really a png\n' > "$BASE/walls/a.png"

WALLPICKER_BIN="$BASE/bin/wallpicker" WALLPAPER_DIR="$BASE/walls" \
  PATH="$BASE/bin:$PATH" timeout 40 sh "$ROOT/adapters/x11/wallpaper.sh" >/dev/null 2>&1
_rc=$?
check "кнопка обоев: без сот отвечает 0" 0 "$_rc"
[ -f "$BDI_CACHE/fallback.called" ] &&
  printf 'ok   запасной xfdesktop-settings открыт\n' ||
  { printf 'FAIL запасной вариант не открылся\n'; fail=1; }
grep -q "wallpicker не запустился" "$BDI_CACHE/wallpicker.log" &&
  printf 'ok   причина записана в лог\n' ||
  { printf 'FAIL причины нет в логе\n'; fail=1; }

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

printf '\n'
if [ "$fail" -eq 0 ]; then echo "всё сошлось"; else echo "есть провалы"; fi
exit "$fail"
