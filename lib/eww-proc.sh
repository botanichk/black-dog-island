# lib/eww-proc.sh - поиск процессов Eww по конфигу.
# Подключается из adapters/x11/island-geom.sh и scripts/stop-island.sh.
#
# Зачем: `--config` можно передать относительным путём, и тогда в cmdline
# остаётся "eww", а не "/home/.../eww". Сравнение строк такие демоны не
# находит: окно на экране есть, а скрипт считает, что остров не запущен
# (и второй демон остаётся жив, потому что `eww kill` идёт по своему
# сокету - у относительного пути он другой).
# Поэтому путь конфига всегда приводим к абсолютному: аргумент + cwd.

# eww_proc_conf <pid> - абсолютный каталог конфига процесса, код 1 если не eww-демон.
#
# Как приводим путь: `--config` может быть относительным ("eww"), но cwd
# процесса для этого не годится - Eww сам делает chdir в каталог конфига,
# и cwd/eww даёт ".../eww/eww". Поэтому:
#   1. абсолютный аргумент берём как есть;
#   2. относительный разрешаем от cwd, но если такого каталога нет - от
#      родителя cwd (это как раз случай chdir: cwd уже и есть конфиг).
eww_proc_conf() {
  _p=$1
  [ -r "/proc/$_p/cmdline" ] || return 1
  _cmd=$(tr '\0' ' ' < "/proc/$_p/cmdline" 2>/dev/null) || return 1
  case "$_cmd" in
    *" daemon "*) ;;
    *" daemon") ;;
    *) return 1 ;;
  esac
  case "$_cmd" in
    *"--config "*) ;;
    *) return 1 ;;
  esac
  _arg=${_cmd#*--config }
  _arg=${_arg%% *}
  [ -n "$_arg" ] || return 1
  case "$_arg" in
    /* ) printf '%s\n' "$(readlink -f "$_arg" 2>/dev/null || printf '%s\n' "$_arg")"; return 0 ;;
  esac
  _cwd=$(readlink -f "/proc/$_p/cwd" 2>/dev/null) || return 1
  # cwd уже конфиг (Eww делает chdir) - иначе склеиваем с родителем.
  if [ "$(basename "$_cwd")" = "$(basename "$_arg")" ]; then
    printf '%s\n' "$_cwd"
  else
    printf '%s\n' "$(readlink -f "$_cwd/$_arg" 2>/dev/null || printf '%s\n' "$_cwd/$_arg")"
  fi
}

# eww_daemon_pids <conf> - PID всех демонов этого конфига (может быть несколько).
eww_daemon_pids() {
  _want=$(readlink -f "$1" 2>/dev/null || printf '%s\n' "$1")
  for _p in /proc/[0-9]*; do
    _p=${_p#/proc/}
    _c=$(eww_proc_conf "$_p" 2>/dev/null) || continue
    [ "$_c" = "$_want" ] && printf '%s\n' "$_p"
  done
}

# eww_proc_root <pid> - BDI_ROOT из окружения процесса, пусто если его нет.
# Пустой корень = демон поднят руками без run-island.sh: в eww.yuck пути
# команд становятся /adapters/..., и кнопки молча не работают.
eww_proc_root() {
  tr '\0' '\n' < "/proc/$1/environ" 2>/dev/null | sed -n 's/^BDI_ROOT=//p' | head -1
}
