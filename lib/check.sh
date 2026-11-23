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
# Проверяем не имя шрифта, а покрытие глифа обоев (U+F03E), который есть
# только в Nerd Font: Meslo есть не везде (в Void его нет), а Symbols Nerd
# Font покрывает те же глифы и весит 2.6 МБ вместо 116.
check_meslo() {
  command -v fc-list >/dev/null 2>&1 || return 0
  if [ -n "$(fc-list ':charset=f03e' family 2>/dev/null | head -1)" ]; then
    log_ok "шрифт с глифами Nerd Font"
    return 0
  fi
  case "${1:-?}" in
    '?') log_warn "нет шрифта с глифами Nerd Font: иконки кнопок будут квадратами, ставь вручную" ;;
    *)   log_warn "нет шрифта с глифами Nerd Font (пакет $1): иконки кнопок будут квадратами"
         printf '%s\n' "$1" >> "$BDI_PKGS_OPT" ;;
  esac
}

# check_dep_lines <файл deps> <check|build>
# Пишет пакеты в общие списки: BDI_PKGS_NOW (обязательные), BDI_PKGS_OPT
# (необязательные, в том числе для сборки). Печать — один раз в check_all,
# иначе два вызова (check + build) дублировали блоки.
check_dep_lines() {
  _f=$1
  _mode=$2
  [ -r "$_f" ] || { log_warn "нет таблицы зависимостей: $_f"; return 0; }

  while IFS= read -r _line; do
    case "$_line" in ''|\#*) continue ;; esac
    # Разбор по |. Поля: команда | пакет | обязательна | зачем | сборка
    _cmd=$(printf '%s' "$_line" | cut -d'|' -f1 | tr -d ' ')
    _pkg=$(printf '%s' "$_line" | cut -d'|' -f2 | tr -d ' ')
    _need=$(printf '%s' "$_line" | cut -d'|' -f3 | tr -d ' ')
    _why=$(printf '%s' "$_line" | cut -d'|' -f4 | sed 's/^ *//; s/ *$//')
    _build=$(printf '%s' "$_line" | cut -d'|' -f5 | tr -d ' ')

    [ -z "$_cmd" ] && continue
    # check - только рабочая часть, build - только строки сборки. Иначе
    # второй проход повторно печатал весь список.
    if [ "$_mode" = check ] && [ "$_build" = сборка ]; then continue; fi
    if [ "$_mode" = build ] && [ "$_build" != сборка ]; then continue; fi

    # Шрифт проверяется отдельно, через fc-list.
    if [ "$_cmd" = "@meslo" ]; then
      check_meslo "$_pkg"
      continue
    fi

    if command -v "$_cmd" >/dev/null 2>&1; then
      log_ok "$_cmd"
      continue
    fi
    # Строки сборки — это библиотеки: у них нет команды, проверяем заголовки
    # через pkg-config по тому же имени, что в первой колонке.
    if [ "$_build" = сборка ] && command -v pkg-config >/dev/null 2>&1 &&
       pkg-config --exists "$_cmd" 2>/dev/null; then
      log_ok "$_cmd (заголовки на месте)"
      continue
    fi

    # Нет ни команды, ни заголовков. Строки сборки без заголовков считаем
    # предупреждением: без них движок не собрать, но остров не падает.
    if [ "$_need" = да ] && [ "$_build" != сборка ]; then
      log_fail "$_cmd  нет  (пакет $_pkg) - $_why"
      [ "$_pkg" != "?" ] && printf '%s\n' "$_pkg" >> "$BDI_PKGS_NOW"
      BDI_MISSING="$BDI_MISSING $_cmd"
    else
      log_warn "$_cmd  нет  (пакет $_pkg) - $_why"
      [ "$_pkg" != "?" ] && printf '%s\n' "$_pkg" >> "$BDI_PKGS_OPT"
    fi
  done < "$_f"
}

# check_pkg_cmd <файл со списком> <заголовок> - печать команды установки.
# Пустой список - ничего не печатает.
check_pkg_cmd() {
  _list=$(sort -u "$1" 2>/dev/null | tr '\n' ' ' | sed 's/ *$//')
  [ -n "$_list" ] || return 0
  _cmdline=$(distro_install_cmd "$_list")
  if [ -n "$_cmdline" ]; then
    printf '\n%s\n\n  %s\n' "$2" "$_cmdline"
  else
    printf '\nПакетный менеджер этой системы неизвестен. Поставь вручную: %s\n' "$_list"
  fi
}

# check_all - полная проверка. Печатает отчёт, код 0 если обязательное есть.
# Пакеты копятся в двух списках и печатаются в конце, одной строкой на группу.
check_all() {
  BDI_MISSING=""
  # Списки пакетов общие для всех вызовов check_dep_lines; печатаются один раз.
  BDI_PKGS_NOW=$(mktemp "${TMPDIR:-/tmp}/bdi-now.XXXXXX")
  BDI_PKGS_OPT=$(mktemp "${TMPDIR:-/tmp}/bdi-opt.XXXXXX")
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

  # Сборка движка: строки с пометкой "сборка" проверяются по заголовкам,
  # а не по команде (у библиотек команды нет).
  log_step "Для сборки движка"
  if [ -r "$ROOT/build/target/release/eww" ] &&
     ! find "$ROOT/patches" -name 'eww-*.patch' -newer "$ROOT/build/target/release/eww" 2>/dev/null | head -1 | grep -q .; then
    log_ok "движок уже собран, пересборка не нужна"
  else
    [ -n "$BDI_DEPS" ] && check_dep_lines "$ROOT/deps/$BDI_DEPS" build
  fi

  # Соты обоев: без cmake/make/заголовков X11 их не собрать, и кнопка обоев
  # молча открывала xfdesktop-settings вместо сетки.
  log_step "Для выбора обоев"
  . "$ROOT/lib/wallpaper.sh"
  _wpdir=$(bdi_wallpaper_dir)
  if [ -d "$_wpdir" ]; then
    _wpn=$(bdi_count_walls "$_wpdir")
    if [ "${_wpn:-0}" -eq 0 ]; then
      log_warn "в папке обоев $_wpdir нет картинок (png, jpg, jpeg): сетка откроется пустой"
    else
      log_ok "обоев в $_wpdir: $_wpn"
    fi
  else
    log_warn "нет папки обоев $_wpdir: положите туда картинки или укажите BDI_WALLPAPERS"
  fi
  if [ -x "$ROOT/build/wallpicker-src/wallpicker" ]; then
    log_ok "соты обоев уже собраны"
  else
    # Пакеты копим отдельным списком, чтобы check сам печатал готовую
    # команду: имена cmake/make одинаковы в обоих дистрибутивах, а GL
    # заголовки разные (Void - libglvnd-devel, Arch - libglvnd).
    _wplist=$(mktemp "${TMPDIR:-/tmp}/bdi-wp.XXXXXX")
    # Имена заголовков GL/X11 разные: в Void пакеты с суффиксом -devel.
    case "$BDI_DISTRO" in
      void) _x11pkg=libX11-devel; _glpkg=libglvnd-devel ;;
      *)    _x11pkg=libx11;       _glpkg=libglvnd ;;
    esac
    command -v cmake >/dev/null 2>&1 ||
      { log_warn "нет cmake: соты обоев не собрать"; printf 'cmake\n' >> "$_wplist"; }
    command -v make >/dev/null 2>&1 ||
      { log_warn "нет make: соты обоев не собрать"; printf 'make\n' >> "$_wplist"; }
    # raylib линкуется с X11 и OpenGL: нужны их заголовки.
    pkg-config --exists x11 2>/dev/null ||
      { log_warn "нет заголовков X11: соты обоев не собрать"; printf '%s\n' "${_x11pkg:-libx11}" >> "$_wplist"; }
    pkg-config --exists gl 2>/dev/null ||
      { log_warn "нет заголовков GL: соты обоев не собрать"; printf '%s\n' "${_glpkg:-libglvnd}" >> "$_wplist"; }
    if [ -s "$_wplist" ]; then
      check_pkg_cmd "$_wplist" "Для сот обоев (без них кнопка обоев откроет xfdesktop-settings):"
    else
      log_ok "для сот всё на месте"
    fi
    rm -f "$_wplist"
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
  check_pkg_cmd "$BDI_PKGS_NOW" "Поставь недостающие пакеты сам (sudo есть только у тебя):"
  check_pkg_cmd "$BDI_PKGS_OPT" "По желанию (не обязательно для работы острова):"
  rm -f "$BDI_PKGS_NOW" "$BDI_PKGS_OPT"

  if [ -n "$BDI_MISSING" ]; then
    log_info "Не хватает обязательного:$BDI_MISSING"
    log_info "После установки пакетов: ./install.sh install"
    return 1
  fi
  log_ok "всё обязательное на месте"
  log_info "Дальше: ./install.sh install"
  return 0
}
