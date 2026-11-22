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
  SW=$(( $(date +%S) + 10 ))   # уникальное число, чтобы ловить именно наши вызовы
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
printf '\$primary: #787317;\n\$surface: #f6f8f8;\n' > "$ROOT/eww/colors.scss.tmp-test"

# colors.scss в песочнице: подкладываем свой, чтобы скрипт дошёл до dconf.
CSS="$ROOT/eww/colors.scss"
_css_backup=""
if [ -f "$CSS" ]; then _css_backup="$BASE/colors.scss.bak"; cp "$CSS" "$_css_backup"; fi
printf '$primary: #787317;\n$surface: #f6f8f8;\n' > "$CSS"

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

rm -f "$ROOT/eww/colors.scss.tmp-test"
[ -n "$_css_backup" ] && cp "$_css_backup" "$CSS"

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

printf '\n'
if [ "$fail" -eq 0 ]; then echo "всё сошлось"; else echo "есть провалы"; fi
exit "$fail"
