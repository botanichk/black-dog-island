# lib/install.sh - сам install. Вызывается из install.sh, не напрямую.
#
# Порядок: check -> план -> подтверждение -> резервная копия -> действия.
# Каждое изменение пишется в журнал (~/.local/state/bdi/changes.log), чтобы
# uninstall мог вернуть прежнее. Нет записи - нет изменения.

# run_indent <команда...> - печатает вывод с отступом, возвращает её код.
# Через файл, а не через `| sed`: в POSIX sh код возврата после pipe - это код
# sed, то есть ошибка команды терялась.
run_indent() {
  _o=$(mktemp "${TMPDIR:-/tmp}/bdi-out.XXXXXX") || return 1
  "$@" >"$_o" 2>&1
  _r=$?
  sed 's/^/  /' "$_o"
  rm -f "$_o"
  return "$_r"
}

# install_eww - клон движка на закреплённом коммите и сборка с патчами.
# Не пересобирает, если бинарник новее пина и патчей.
install_eww() {
  _eww="$ROOT/build/target/release/eww"
  _src="$ROOT/build/eww-src"
  . "$ROOT/deps/engine.txt"
  _pinfile="$ROOT/build/.eww-pin"

  if [ -x "$_eww" ] && [ -f "$_pinfile" ] && [ "$(cat "$_pinfile")" = "$EWW_PIN" ]; then
    # Патчи новее бинарника - надо пересобрать.
    _newer=$(find "$ROOT/patches" -name 'eww-*.patch' -newer "$_eww" 2>/dev/null | head -1)
    if [ -z "$_newer" ]; then
      log_ok "движок уже собран на нужном коммите, пересборка не нужна"
      return 0
    fi
    log_info "патчи новее бинарника - пересобираю"
  fi

  if [ ! -d "$_src/.git" ]; then
    log_info "клонирую движок в build/eww-src (около 3.7 МБ, нужен интернет)"
    mkdir -p "$ROOT/build"
    # --filter=blob:none: история не нужна, только коммит.
    run_indent git clone --quiet --filter=blob:none "$EWW_REPO" "$_src" || true
    [ -d "$_src/.git" ] || { log_fail "не удалось клонировать $_EWW_REPO (нет интернета?)"; return 1; }
  fi

  log_info "переключаю движок на коммит $EWW_PIN"
  git -C "$_src" checkout --quiet "$EWW_PIN" 2>/dev/null ||
    { log_fail "коммит $EWW_PIN не найден в клоне"; return 1; }

  log_info "собираю. Это 10-25 минут и около 2 ГБ в build/, можно пить чай"
  # Без pipe в sed: сборка долгая, прогресс нужен живым, а код возврата -
  # от cargo, а не от sed.
  if ! sh "$ROOT/scripts/build-eww.sh"; then
    log_fail "сборка не удалась: смотри вывод выше и $ROOT/build/eww-src"
    return 1
  fi
  printf '%s\n' "$EWW_PIN" > "$_pinfile"
  log_ok "движок собран: $_eww"
}

# install_panel - отключить панель XFCE, не удаляя её настроек.
# Способ: Failsafe-сессия XFCE запускает клиента; вместо xfce4-panel ставим
# заглушку true. Панель просто не стартует, ~/.config/xfce4 не трогается.
install_panel() {
  if ! pgrep -x xfce4-panel >/dev/null 2>&1 &&
     [ "$(xfconf-query -c xfce4-session -p /sessions/Failsafe/Client2_Command -v 2>/dev/null | tr -d '\n')" = "true" ]; then
    log_ok "панель XFCE уже отключена"
    return 0
  fi

  # Найти, какой ClientN_Command сейчас держит панель: у разных сборок номер
  # может отличаться, зашивать "Client2" намертво нельзя.
  _prop=""
  _idx=0
  while [ "$_idx" -lt 12 ]; do
    _p="/sessions/Failsafe/Client${_idx}_Command"
    _v=$(xfconf-query -c xfce4-session -p "$_p" -v 2>/dev/null | tr -d '\n' || true)
    case "$_v" in
      *xfce4-panel*) _prop="$_p"; break ;;
    esac
    _idx=$((_idx + 1))
  done

  if [ -z "$_prop" ]; then
    # Панели в сессии нет, но, возможно, она запущена руками.
    if pgrep -x xfce4-panel >/dev/null 2>&1; then
      log_info "панели нет в списке сессии, закрываю запущенную"
      xfce4-panel --quit 2>/dev/null || true
      journal_add process "xfce4-panel" "запущена" "закрыта"
    fi
    log_ok "панель XFCE в сессии не значится"
    return 0
  fi

  _old=$(xfconf-query -c xfce4-session -p "$_prop" -v 2>/dev/null | tr -d '\n')
  log_info "отключаю панель XFCE в $_prop (было: $_old)"
  # Заглушка true - так XFCE помечает отключённого клиента. Тип bool, а не
  # массив: у отключённого клиента значение скалярное.
  journal_add xfconf "$_prop" "$_old" "true"
  xfconf-query -c xfce4-session -p "$_prop" -n -t bool -s true ||
    { log_fail "не удалось записать $_prop"; return 1; }

  pgrep -x xfce4-panel >/dev/null 2>&1 && xfce4-panel --quit 2>/dev/null || true
  log_ok "панель XFCE отключена (настройки не удалены, вернуть - ./install.sh uninstall)"
}

# install_compositing - скруглённые углы без композитинга не работают.
install_compositing() {
  command -v xfconf-query >/dev/null 2>&1 || return 0
  _c=$(xfconf-query -c xfwm4 -p /general/use_compositing -v 2>/dev/null || echo true)
  [ "$_c" = true ] && { log_ok "композитинг уже включён"; return 0; }
  log_warn "композитинг выключен: углы острова будут прямоугольными"
  log_ask "Включить композитинг xfwm4?" || { log_info "оставил как есть"; return 0; }
  journal_add xfconf /general/use_compositing "$_c" "true"
  xfconf-query -c xfwm4 -p /general/use_compositing -s true
  log_ok "композитинг включён"
}

# install_autostart - одна запись, без дублей.
#
# OnlyShowIn=XFCE: - запись не срабатывает в Hyprland (у которого нет
# xdg-autostart вовсе) и в любом другом рабочем столе. Проверяется по файлу,
# без запуска: строка есть в .desktop, а xdg-autostart её учитывает.
# Hidden=false обязателен: если владелец когда-то спрятал нашу запись, без
# явного Hidden=false autostart молча продолжал бы её пропускать.
install_autostart() {
  _f="$HOME/.config/autostart/bdi.desktop"
  mkdir -p "$HOME/.config/autostart"
  _want="$ROOT/scripts/run-island.sh"

  if [ -f "$_f" ] && grep -qxF "Exec=$_want" "$_f" 2>/dev/null &&
     grep -qxF "OnlyShowIn=XFCE;" "$_f" 2>/dev/null &&
     grep -qxF "Hidden=false" "$_f" 2>/dev/null; then
    log_ok "автозапуск уже на своём месте"
    return 0
  fi

  if [ -f "$_f" ]; then
    _old=$(sed -n 's/^Exec=//p' "$_f" | head -1)
    journal_add autostart "$_f" "$_old" "$_want"
  else
    journal_add autostart "$_f" "" "$_want"
  fi

  cat > "$_f" <<EOF
[Desktop Entry]
Type=Application
Name=Black Dog Island
Comment=Остров вместо панели XFCE
Exec=$_want
Terminal=false
Hidden=false
X-GNOME-Autostart-enabled=true
OnlyShowIn=XFCE;
EOF
  log_ok "автозапуск: $_f (только в XFCE)"
}

# disable_stale_autostart - погасить НАШ ЖЕ автозапуск под старым именем
# (у владельца это eww-island.desktop от прошлых сборок). Иначе при входе
# поднимались бы два острова: старый файл и новый bdi.desktop.
# Файл не удаляем: ставим Hidden=true и пишем в журнал, откат вернёт строку.
# Чужой .desktop (не с нашим Exec) не трогаем ни при каких условиях.
disable_stale_autostart() {
  for _g in "$HOME/.config/autostart"/*.desktop; do
    [ -f "$_g" ] || continue
    [ "$_g" = "$HOME/.config/autostart/bdi.desktop" ] && continue
    grep -qF "$ROOT/scripts/run-island.sh" "$_g" 2>/dev/null || continue
    grep -qxF "Hidden=true" "$_g" && continue
    journal_add autostart "$_g" "Hidden=false" "Hidden=true"
    if grep -q '^Hidden=' "$_g"; then
      _tmp="$_g.bdi-tmp"
      sed 's/^Hidden=.*/Hidden=true/' "$_g" > "$_tmp" && mv "$_tmp" "$_g"
    else
      printf 'Hidden=true\n' >> "$_g"
    fi
    log_ok "погашен старый автозапуск: $_g (Hidden=true, вернуть - uninstall)"
  done
}

# install_skin_consent - спросить один раз, можно ли красить док и лаунчер.
# Дальше смена темы делает это молча: спрашивать про док на каждое нажатие
# «Цвета» - то же самое, что не спрашивать вовсе. Ответ лежит в
# ~/.config/bdi/skin-<программа>; нет файла - не спрашивали (старая установка),
# тогда красим как раньше.
install_skin_consent() {
  for _p in plank ulauncher; do
    command -v "$_p" >/dev/null 2>&1 || { log_info "$_p не установлен - пропускаю"; continue; }
    if [ -f "$BDI_CONFIG/skin-$_p" ]; then
      log_ok "$_p: уже решено ($(cat "$BDI_CONFIG/skin-$_p"))"
      continue
    fi
    mkdir -p "$BDI_CONFIG"
    if log_ask "Красить $_p в цвета острова (своя тема рядом с твоими)?"; then
      printf '%s\n' yes > "$BDI_CONFIG/skin-$_p"
      log_ok "$_p: буду красить"
    else
      printf '%s\n' no > "$BDI_CONFIG/skin-$_p"
      log_info "$_p: оставил как есть, тему не трогаю"
    fi
  done
}

# install_extras - автозапуск Plank и Ulauncher, если они установлены.
# Тема дока и лаунчера уже ставится theme/apply.sh (шаги 5-6) при каждом
# запуске острова, здесь только подъём при входе. Чужой .desktop не
# перезаписываем: владелец мог настроить свой.
install_extras() {
  _n=0
  for _p in plank ulauncher; do
    command -v "$_p" >/dev/null 2>&1 || { log_info "$_p не установлен - пропускаю"; continue; }
    _f="$HOME/.config/autostart/$_p.desktop"
    if [ -f "$_f" ]; then
      log_ok "автозапуск $_p уже есть, не трогаю"
      continue
    fi
    case "$_p" in
      plank) _exec=plank ;;
      ulauncher) _exec="ulauncher --hide-window" ;;
    esac
    journal_add autostart "$_f" "" "$_exec"
    # OnlyShowIn=XFCE: и здесь - иначе Plank поднимался бы и в Hyprland, где
    # у владельца свой док и своя тема.
    cat > "$_f" <<EOF
[Desktop Entry]
Type=Application
Name=$_p
Exec=$_exec
Terminal=false
Hidden=false
X-GNOME-Autostart-enabled=true
OnlyShowIn=XFCE;
EOF
    log_ok "автозапуск: $_f"
    _n=$((_n + 1))
  done
  return 0
}

# install_wallpicker - выбор обоев шестиугольниками: клон по пину, патчи, сборка,
# хук под XFCE. Без этого кнопка обоев открывала родной xfdesktop-settings.
# Не пересобирает, если бинарник новее пина и патчей.
install_wallpicker() {
  _bin="$ROOT/build/wallpicker-src/wallpicker"
  _src="$ROOT/build/wallpicker-src"
  . "$ROOT/deps/wallpicker.txt"
  _pinfile="$ROOT/build/.wallpicker-pin"

  if [ -x "$_bin" ] && [ -f "$_pinfile" ] && [ "$(cat "$_pinfile")" = "$WALLPICKER_PIN" ]; then
    _newer=$(find "$ROOT/patches" -name 'hypr-wallpicker-*.patch' -newer "$_bin" 2>/dev/null | head -1)
    if [ -z "$_newer" ]; then
      log_ok "выбор обоев уже собран, пересборка не нужна"
      _wcached=1
    else
      log_info "патчи новее бинарника - пересобираю"
      _wcached=0
    fi
  else
    _wcached=0
  fi

  if [ "$_wcached" -eq 0 ]; then
    command -v cmake >/dev/null 2>&1 || {
      log_warn "нет cmake - соты обоев не собрать, кнопка откроет xfdesktop-settings"
      return 0; }
    command -v make >/dev/null 2>&1 || {
      log_warn "нет make - соты обоев не собрать"; return 0; }

    if [ ! -d "$_src/.git" ]; then
      log_info "клонирую выбор обоев (нужен интернет, ~10 МБ без raylib)"
      mkdir -p "$ROOT/build"
      run_indent git clone --quiet "$WALLPICKER_REPO" "$_src" || true
      [ -d "$_src/.git" ] || {
        log_warn "не удалось клонировать $WALLPICKER_REPO: соты не будут собраны"
        return 0; }
    fi

    log_info "переключаю на коммит $WALLPICKER_PIN"
    if ! git -C "$_src" checkout --quiet "$WALLPICKER_PIN" 2>/dev/null; then
      log_warn "коммит $WALLPICKER_PIN не найден: соты останутся не собраны"
      return 0
    fi

    log_info "собираю соты (raylib ~98 МБ, около 80 с)"
    if ! sh "$ROOT/scripts/build-wallpicker.sh"; then
      # Не валим установку: остров работает и без сот, кнопка обоев
      # откроет xfdesktop-settings.
      log_warn "соты не собрались (см. вывод выше), кнопка обоев откроет xfdesktop-settings"
      return 0
    fi
    printf '%s\n' "$WALLPICKER_PIN" > "$_pinfile"
    log_ok "выбор обоев собран: $_bin"
  fi

  # Бинарник лежит в build/, а run.sh ищет его в ~/src/hypr-wallpicker.
  # Симлинк, а не копия: update пересобирает один файл.
  _userbin="$HOME/src/hypr-wallpicker/wallpicker"
  if [ "$(readlink -f "$_bin")" != "$(readlink -f "$_userbin" 2>/dev/null)" ]; then
    mkdir -p "$(dirname "$_userbin")"
    ln -sfn "$_bin" "$_userbin"
    journal_add file "$_userbin" "" "$_bin"
    log_ok "ссылка на соты: $_userbin"
  fi

  # Хук, который wallpicker зовёт после выбора обоев.
  if "$ROOT/adapters/wallpicker/install.sh" >/dev/null 2>&1; then
    log_ok "хук обоев на месте"
  else
    log_warn "хук обоев не поставлен: смотри adapters/wallpicker/install.sh"
  fi
}

# install_start - поднять остров сейчас, не дожидаясь перезагрузки.
install_start() {
  if "$ROOT/adapters/x11/island-geom.sh" xid >/dev/null 2>&1; then
    log_ok "остров уже запущен"
    return 0
  fi
  log_info "запускаю остров"
  run_indent "$ROOT/scripts/run-island.sh" || {
    log_fail "остров не поднялся, смотри вывод выше"; return 1; }
}

install_all() {
  log_step "Проверка"
  if ! check_all; then
    log_fail "сначала поставь обязательные пакеты (команда выше) и повтори"
    return 1
  fi

  log_step "Что будет сделано"
  log_info "1. резервная копия настроек в ~/.local/state/bdi/backup-<дата>"
  log_info "2. сборка движка с нашими патчами (10-25 минут, ~2 ГБ в build/)"
  log_info "3. отключение панели XFCE (настройки не удаляются)"
  log_info "4. автозапуск острова при входе (и Plank с Ulauncher, если стоят)"
  log_info "5. спрошу, красить ли док и лаунчер в цвета острова"
  log_ask "Продолжаем?" || { log_info "отменено, ничего не менял"; return 1; }

  log_step "Резервная копия"
  backup_create | sed 's/^/  /' || { log_fail "не удалось сделать резервную копию"; return 1; }

  log_step "Движок"
  install_eww || return 1

  log_step "Панель XFCE"
  install_panel || return 1

  log_step "Композитинг"
  install_compositing

  log_step "Автозапуск"
  install_autostart || return 1
  disable_stale_autostart
  install_extras

  log_step "Док и лаунчер"
  install_skin_consent

  log_step "Выбор обоев"
  install_wallpicker

  log_step "Запуск"
  install_start || true

  log_step "Готово"
  log_info "Изменений в журнале: $(journal_count) ($BDI_JOURNAL)"
  log_info "Откатить: ./install.sh uninstall (появится в следующем шаге)"
  log_info "Проверить систему: ./install.sh check"
}

# update_all - обновление из git без переустановки.
# Пересобирает движок только если изменился пин или патчи (это решает
# install_eww), и перезапускает остров: окно и резерв применяются только
# полным перезапуском, eww reload их не трогает.
# В журнал не пишет: настроек не меняет, откатывать нечего.
update_all() {
  log_step "Обновление"
  if [ ! -d "$ROOT/.git" ]; then
    log_fail "$ROOT не клон git (скачан ZIP-ом): обновление вручную"
    return 1
  fi
  if [ -n "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ]; then
    log_warn "в репозитории есть свои правки - pull может не пройти"
    git -C "$ROOT" status --short | sed 's/^/  /'
  fi

  log_info "git pull --ff-only"
  if ! run_indent git -C "$ROOT" pull --ff-only; then
    log_fail "pull не прошёл: разберись с правками выше, потом повтори"
    return 1
  fi

  log_step "Движок"
  install_eww || return 1

  log_step "Выбор обоев"
  install_wallpicker

  log_step "Перезапуск острова"
  # Остановка только по нашему пути к eww (stop-island.sh), чужие демоны
  # не трогаем. Код возврата не важен: остров мог быть не запущен.
  sh "$ROOT/scripts/stop-island.sh" >/dev/null 2>&1 || true
  install_start || return 1

  log_step "Готово"
  log_info "Версия: $(git -C "$ROOT" log --oneline -1)"
  log_info "Проверить систему: ./install.sh check"
}
