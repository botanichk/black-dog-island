# lib/check.sh - проверка системы, только чтение.
#
# Ничего не меняет и не ставит: только смотрит и печатает, что не так и какой
# командой это лечится. sudo не зовёт никогда - пароль есть только у владельца.
#
# Результат: ok / warn / fail по каждой строке, в конце - готовая команда
# установки недостающих пакетов. Код 0, если обязательное всё на месте.
#
# Функции таблицы (deps/<система>.txt): check_dep_lines <файл> <режим>
#   режим "check"  - без строк с пометкой "сборка"
#   режим "build"  - все строки (нужны для сборки движка)

BDI_MISSING=""   # пакеты, которых не хватает (через пробел)

# check_os - сеанс, XFCE, экран, композитинг.
check_os() {
  case "${XDG_SESSION_TYPE:-}" in
    x11) log_ok "сеанс X11" ;;
    wayland) log_fail "сеанс Wayland: остров сделан под X11, работать не будет" ;;
    *) [ -n "${DISPLAY:-}" ] && log_ok "сеанс X11 (по \$DISPLAY)" \
         || log_fail "нет графического сеанса: запускать из терминала в XFCE" ;;
  esac

  if [ -n "${XDG_CURRENT_DESKTOP:-}" ]; then
    case "$XDG_CURRENT_DESKTOP" in
      *XFCE*) log_ok "Xfce ($XDG_CURRENT_DESKTOP)" ;;
      *) log_warn "рабочий стол $XDG_CURRENT_DESKTOP, проект сделан под Xfce" ;;
    esac
  fi

  # Композитинг нужен для скруглённых углов: без него окно прямоугольное.
  if command -v xfconf-query >/dev/null 2>&1; then
    _comp=$(xfconf-query -c xfwm4 -p /general/use_compositing -v 2>/dev/null || true)
    case "$_comp" in
      true) log_ok "композитинг xfwm4 включён" ;;
      false) log_warn "композитинг xfwm4 выключен: углы будут прямоугольными (install предложит включить)" ;;
      *) log_warn "не удалось прочитать композитинг xfwm4" ;;
    esac
  fi

  # Экран: 1366x768 - то, под что сделано. Меньше 1280x720 - остров 619 px
  # всё ещё влезет, но вкладки станут тесными.
  if command -v xrandr >/dev/null 2>&1; then
    _w=$(xrandr --current 2>/dev/null | awk '/\*/{print $1; exit}' | cut -dx -f1)
    if [ -n "$_w" ]; then
      if [ "$_w" -ge 1280 ]; then
        log_ok "ширина экрана ${_w} px"
      else
        log_warn "ширина экрана ${_w} px: остров 619 px влезет, но будет тесно"
      fi
    fi
  fi
}

# check_meslo [пакет] - шрифт с глифами кнопок. Без него вместо иконок квадраты.
check_meslo() {
  command -v fc-list >/dev/null 2>&1 || return 0
  if fc-list 2>/dev/null | grep -qi 'meslo'; then
    log_ok "шрифт Meslo Nerd Font"
    return 0
  fi
  case "${1:-?}" in
    '?') log_warn "шрифт Meslo Nerd Font не найден: глифы кнопок будут квадратами, ставь вручную" ;;
    *)   log_warn "шрифт Meslo Nerd Font не найден (пакет $1): глифы кнопок будут квадратами"
         printf '%s\n' "$1" >> "$_pkgs_opt" ;;
  esac
}

# check_dep_lines <файл deps> <check|build>
check_dep_lines() {
  _f=$1
  _mode=$2
  [ -r "$_f" ] || { log_warn "нет таблицы зависимостей: $_f"; return 0; }

  # Пакеты для команды установки. Значения newline-разделены, дубли снимаем
  # sort -u: imagemagick приходит и от magick, и от import.
  # Обязательные и необязательные копим в разные файлы: первые мешают install,
  # вторые только украшение (док, лаунчер), их ставит владелец по желанию.
  _pkgs=$(mktemp "${TMPDIR:-/tmp}/bdi-pkgs.XXXXXX")
  _pkgs_opt=$(mktemp "${TMPDIR:-/tmp}/bdi-pkgs-opt.XXXXXX")
  while IFS= read -r _line; do
    case "$_line" in ''|\#*) continue ;; esac
    # Разбор по |. Поля: команда | пакет | обязательна | зачем | сборка
    _cmd=$(printf '%s' "$_line" | cut -d'|' -f1 | tr -d ' ')
    _pkg=$(printf '%s' "$_line" | cut -d'|' -f2 | tr -d ' ')
    _need=$(printf '%s' "$_line" | cut -d'|' -f3 | tr -d ' ')
    _why=$(printf '%s' "$_line" | cut -d'|' -f4 | sed 's/^ *//; s/ *$//')
    _build=$(printf '%s' "$_line" | cut -d'|' -f5 | tr -d ' ')

    [ -z "$_cmd" ] && continue
    # В режиме check не трогаем то, что нужно только для сборки.
    if [ "$_mode" = check ] && [ "$_build" = сборка ]; then continue; fi

    # Шрифт проверяется отдельно, через fc-list.
    if [ "$_cmd" = "@meslo" ]; then
      check_meslo "$_pkg"
      continue
    fi

    if command -v "$_cmd" >/dev/null 2>&1; then
      log_ok "$_cmd"
      continue
    fi

    # Нет команды. Обязательная - fail, необязательная - warn.
    if [ "$_need" = да ]; then
      log_fail "$_cmd  нет  (пакет $_pkg) - $_why"
      [ "$_pkg" != "?" ] && printf '%s\n' "$_pkg" >> "$_pkgs"
      BDI_MISSING="$BDI_MISSING $_cmd"
    else
      log_warn "$_cmd  нет  (пакет $_pkg) - $_why"
      # Необязательное подсказываем отдельно, install из-за него не падает.
      [ "$_pkg" != "?" ] && printf '%s\n' "$_pkg" >> "$_pkgs_opt"
    fi
  done < "$_f"

  # Дубли пакетов -> одна строка команды.
  check_pkg_cmd "$_pkgs" "Поставь недостающие пакеты сам (sudo есть только у тебя):"
  check_pkg_cmd "$_pkgs_opt" "По желанию (не обязательно для работы острова):"
  rm -f "$_pkgs" "$_pkgs_opt"
}

# check_pkg_cmd <файл со списком> <заголовок> - печать команды установки.
# Пустой список - ничего не печатает.
check_pkg_cmd() {
  _list=$(sort -u "$1" 2>/dev/null | tr '\n' ' ' | sed 's/ *$//')
  [ -n "$_list" ] || return 0
  _cmdline=$(distro_install_cmd "$_list")
  if [ -n "$_cmdline" ]; then
    printf '\n%s\n\n  %s\n' "$2" "$_cmdline" >> "$BDI_CHECK_PKGS"
  else
    printf '\nПакетный менеджер этой системы неизвестен. Поставь вручную: %s\n' "$_list" \
      >> "$BDI_CHECK_PKGS"
  fi
}

# check_all - полная проверка. Печатает отчёт, код 0 если обязательное есть.
# Отчёт о пакетах собирается в $BDI_CHECK_PKGS и печатается в конце, чтобы
# команда установки стояла одной строкой, а не после каждого пакета.
check_all() {
  BDI_CHECK_PKGS=$(mktemp "${TMPDIR:-/tmp}/bdi-check.XXXXXX")
  BDI_MISSING=""
  _fails=0

  distro_detect
  case "$BDI_DISTRO" in
    arch) log_ok "Arch-семейство, пакеты через pacman" ;;
    void) log_ok "Void Linux, пакеты через xbps-install" ;;
    *) log_warn "система не из списка (Arch, Void): пакеты придётся ставить самому" ;;
  esac

  check_os

  log_step "Программы"
  if [ -n "$BDI_DEPS" ] && [ -r "$ROOT/deps/$BDI_DEPS" ]; then
    check_dep_lines "$ROOT/deps/$BDI_DEPS" check
  else
    log_warn "таблицы для этой системы нет, проверяю по Arch (имена пакетов могут отличаться)"
    check_dep_lines "$ROOT/deps/arch.txt" check
  fi

  # Сборка движка: отдельным блоком, чтобы было видно, что это только для
  # компиляции, а не для работы острова.
  log_step "Для сборки движка"
  if command -v cargo >/dev/null 2>&1 && command -v pkg-config >/dev/null 2>&1; then
    _ok=1
    for _pc in gtk+-3.0 dbusmenu-gtk3-0.4 libpulse; do
      pkg-config --exists "$_pc" 2>/dev/null || { _ok=0; log_fail "нет заголовков $_pc (пакет для сборки)"; }
    done
    [ "$_ok" = 1 ] && log_ok "cargo и заголовки GTK3 на месте, можно собирать"
  else
    [ -r "$ROOT/build/target/release/eww" ] && log_ok "движок уже собран, пересборка не нужна" \
      || log_warn "движок не собран и нечем собирать: install поставит сборку в очередь"
    [ -n "$BDI_DEPS" ] && check_dep_lines "$ROOT/deps/$BDI_DEPS" build
  fi

  log_step "Рабочий стол"
  # Панель XFCE: установщик её отключает, но проверить стоит заранее.
  if pgrep -x xfce4-panel >/dev/null 2>&1; then
    log_warn "панель XFCE запущена: install отключит её (настройки останутся)"
  else
    log_ok "панель XFCE не запущена"
  fi

  # Чужой демон Eww: наш остров ищется по своему пути к конфигу, чужой не
  # трогаем. Предупреждаем, чтобы не удивляться двум островам.
  _other=$(pgrep -af 'eww.*daemon' 2>/dev/null | grep -v "$ROOT/build/target/release/eww" || true)
  if [ -n "$_other" ]; then
    log_warn "работает другой демон Eww (не наш): его не трогаем"
  fi

  printf '\n'
  cat "$BDI_CHECK_PKGS"
  rm -f "$BDI_CHECK_PKGS"

  if [ -n "$BDI_MISSING" ]; then
    log_info "Не хватает обязательного:$BDI_MISSING"
    log_info "После установки пакетов: ./install.sh install"
    return 1
  fi
  log_ok "всё обязательное на месте"
  log_info "Дальше: ./install.sh install"
  return 0
}
