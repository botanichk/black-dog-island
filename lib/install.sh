# lib/install.sh - сам install. Вызывается из install.sh, не напрямую.
#
# Порядок: check -> план -> подтверждение -> резервная копия -> действия.
# Каждое изменение пишется в журнал (~/.local/state/bdi/changes.log), чтобы
# uninstall мог вернуть прежнее. Нет записи - нет изменения.

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
    git clone --quiet --filter=blob:none "$EWW_REPO" "$_src" 2>&1 |
      sed 's/^/  /' || true
    [ -d "$_src/.git" ] || { log_fail "не удалось клонировать $_EWW_REPO (нет интернета?)"; return 1; }
  fi

  log_info "переключаю движок на коммит $EWW_PIN"
  git -C "$_src" checkout --quiet "$EWW_PIN" 2>/dev/null ||
    { log_fail "коммит $EWW_PIN не найден в клоне"; return 1; }

  log_info "собираю. Это 10-25 минут и около 2 ГБ в build/, можно пить чай"
  if ! sh "$ROOT/scripts/build-eww.sh" 2>&1 | sed 's/^/  /'; then
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
install_autostart() {
  _f="$HOME/.config/autostart/bdi.desktop"
  mkdir -p "$HOME/.config/autostart"
  _want="$ROOT/scripts/run-island.sh"

  if [ -f "$_f" ] && grep -qxF "Exec=$_want" "$_f" 2>/dev/null; then
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
X-GNOME-Autostart-enabled=true
EOF
  log_ok "автозапуск: $_f"
}

# install_start - поднять остров сейчас, не дожидаясь перезагрузки.
install_start() {
  if "$ROOT/adapters/x11/island-geom.sh" xid >/dev/null 2>&1; then
    log_ok "остров уже запущен"
    return 0
  fi
  log_info "запускаю остров"
  "$ROOT/scripts/run-island.sh" 2>&1 | sed 's/^/  /' || {
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
  log_info "4. автозапуск острова при входе"
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

  log_step "Запуск"
  install_start || true

  log_step "Готово"
  log_info "Изменений в журнале: $(journal_count) ($BDI_JOURNAL)"
  log_info "Откатить: ./install.sh uninstall (появится в следующем шаге)"
  log_info "Проверить систему: ./install.sh check"
}
