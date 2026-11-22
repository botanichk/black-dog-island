# desktop.sh - обои XFCE: какой стол действует и как их записать.
#
# Подключается через `. "$ROOT/theme/desktop.sh"`. Нужен, чтобы правило
# single-workspace-mode жило в ОДНОМ месте: его используют и расчёт палитры
# (theme/from-wallpaper.sh), и хук выбора обоев (adapters/wallpicker/apply.sh).
# Вторая копия правила уже один раз разъехалась с экраном: скрипт читал обоями
# текущего стола «бурю», а xfdesktop показывал обои стола 2.
#
# Зависимости только из системы: sh, xfconf-query, xprop, xrandr.
#
# Почему xfconf, а не feh/xsetroot: обои рисует xfdesktop, и он читает
# /backdrop/.../last-image. feh писал бы поверх, и xfdesktop при любом
# обновлении стола возвращал бы свои.
#
# Почему все вызовы через run_to: xfconf-query и xprop ходят в чужие службы
# (xfconfd, X-сервер). На машине, где служба не отвечает, они висят вечно, а
# этим файлом пользуется и смена темы, и хук выбора обоев - остров замирал бы
# вместе с ними. См. theme/guard.sh.
if ! command -v run_to >/dev/null 2>&1; then
  if [ -n "${ROOT:-}" ] && [ -f "$ROOT/theme/guard.sh" ]; then
    . "$ROOT/theme/guard.sh"
  else
    # Без ROOT (файл подключили вручную) таймаута нет, но и падать нечему.
    run_to() { shift; "$@"; }
  fi
fi

# Номер стола, чьи обои РЕАЛЬНО на экране.
# При /backdrop/single-workspace-mode=true это /backdrop/single-workspace-number
# (xfdesktop рисует его на всех столах), иначе текущий стол.
xfce_desktop_workspace() {
  _single=$(run_to 5 xfconf-query -c xfce4-desktop -p /backdrop/single-workspace-mode 2>/dev/null || true)
  _ws=$(run_to 5 xprop -root _NET_CURRENT_DESKTOP 2>/dev/null | sed -n 's/.*= *//p')
  _ws=${_ws:-0}
  if [ "$_single" = "true" ]; then
    _num=$(run_to 5 xfconf-query -c xfce4-desktop -p /backdrop/single-workspace-number 2>/dev/null || true)
    [ -n "$_num" ] && _ws=$_num
  fi
  printf '%s\n' "$_ws"
}

# Ключи last-image этого стола (по одному на монитор), по одному в строке.
xfce_wallpaper_keys() {
  run_to 5 xfconf-query -c xfce4-desktop -l 2>/dev/null \
    | grep "/workspace$1/last-image$" || true
}

# Первый существующий файл обоев стола $1. Пусто, если у стола нет обоев.
xfce_wallpaper_of() {
  xfce_wallpaper_keys "$1" | while read -r _prop; do
    _value=$(run_to 5 xfconf-query -c xfce4-desktop -p "$_prop" 2>/dev/null || true)
    if [ -n "$_value" ] && [ -f "$_value" ]; then
      printf '%s\n' "$_value"
      break
    fi
  done
}

# Обои, которые сейчас на экране: действующий стол, а если у него пусто -
# стол 0 (у нового стола XFCE наследует обои первого).
xfce_current_wallpaper() {
  _ws=$(xfce_desktop_workspace)
  _wall=$(xfce_wallpaper_of "$_ws")
  if [ -z "$_wall" ] && [ "$_ws" != "0" ]; then
    _wall=$(xfce_wallpaper_of 0)
  fi
  [ -n "$_wall" ] && printf '%s\n' "$_wall"
}

# Префикс ключа /backdrop/<screen>/<monitor> - из уже существующих ключей,
# чтобы не хардкодить monitorLVDS-1. Если ключей нет вообще (свежий профиль),
# берём первый подключённый выход xrandr: XFCE зовёт его monitor<ИМЯ>.
xfce_backdrop_prefix() {
  _key=$(run_to 5 xfconf-query -c xfce4-desktop -l 2>/dev/null \
    | grep -m1 "/workspace[0-9]*/last-image$" || true)
  if [ -n "$_key" ]; then
    printf '%s\n' "${_key%/workspace*/last-image*}"
    return 0
  fi
  _out=$(run_to 5 xrandr --query 2>/dev/null | awk '/ connected/{print $1; exit}')
  if [ -n "$_out" ]; then
    printf '/backdrop/screen0/monitor%s\n' "$_out"
    return 0
  fi
  return 1
}

# Поставить обои $1 на действующий стол. Печатает ключ, в который записали.
# Путь не разбирается на слова: он всегда в кавычках и передаётся как есть,
# поэтому пробелы, кириллица, $() и ; в имени безопасны.
xfce_set_wallpaper() {
  _path=$1
  [ -f "$_path" ] || return 1
  _ws=$(xfce_desktop_workspace)
  _prefix=$(xfce_backdrop_prefix) || return 1
  _key="$_prefix/workspace$_ws/last-image"

  if run_to 5 xfconf-query -c xfce4-desktop -p "$_key" >/dev/null 2>&1; then
    run_to 5 xfconf-query -c xfce4-desktop -p "$_key" -s "$_path" || return 1
  else
    # Ключа нет (стол новый или профиль пустой) - создаём.
    run_to 5 xfconf-query -c xfce4-desktop -p "$_key" -n -t string -s "$_path" || return 1
  fi

  printf '%s\n' "$_key"
}
