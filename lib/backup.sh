# lib/backup.sh - резервная копия настроек перед изменениями.
# Уровень 1 откатa: копия каталогов и дамп xfconf. Уровень 2 - журнал
# (lib/journal.sh), он возвращает отдельные значения.
#
# Что копируем: только то, что установщик может изменить. Своё состояние
# (~/.config/bdi) копируем тоже: там выбор темы и согласие на покраску дока,
# и после отката человек ждёт прежний вид, а не «спросить заново».

BDI_BACKUP_DIR=""

# backup_items - что копируем, по одному пути в строке. Один список на
# backup_create и на подсчёт размера: разъедутся - покажем один размер,
# а скопируем другой.
backup_items() {
  # ~/src/hypr-wallpicker не копируем: это чужой клон на 244 МБ, а откат
  # возвращает только симлинк на бинарник (cat 1 файл, см. journal file).
  printf '%s\n' \
    "$HOME/.config/xfce4" \
    "$HOME/.config/autostart" \
    "$HOME/.config/plank" \
    "$HOME/.config/ulauncher" \
    "$HOME/.config/bdi" \
    "$HOME/.local/share/plank/themes"
}

# backup_size - сколько МБ займёт копия. Печатается ДО создания: в ~/.config
# бывает 300 МБ картинок у ulauncher_cache, и «внезапно» это плохо.
backup_size() {
  _total=0
  while IFS= read -r _p; do
    [ -e "$_p" ] || continue
    _kb=$(du -sk "$_p" 2>/dev/null | awk '{print $1}')
    [ -n "${_kb:-}" ] && _total=$((_total + _kb))
  done <<EOF
$(backup_items)
EOF
  # Печатаем с одним знаком: копия обычно меньше мегабайта, и «0 МБ»
  # выглядело бы как ошибка. awk, а не bc: bc не входит в базовую систему.
  printf '%s\n' "$(awk -v k="$_total" 'BEGIN{printf "%.1f", k/1024}')"
}

# backup_create - создать копию, путь положить в BDI_BACKUP_DIR.
# Код 0 при успехе. Если копировать нечего - всё равно создаём каталог:
# uninstall должен иметь куда смотреть.
backup_create() {
  _stamp=$(date '+%Y%m%d-%H%M%S')
  BDI_BACKUP_DIR="${BDI_STATE:-$HOME/.local/state/bdi}/backup-$_stamp"
  mkdir -p "$BDI_BACKUP_DIR" || return 1

  # Каталоги настроек. Нет каталога - не ошибка (чистый XFCE, нет Plank).
  _n=0
  while IFS= read -r _p; do
    [ -d "$_p" ] || continue
    _name=$(printf '%s' "$_p" | sed "s|^$HOME/||; s|/|_|g")
    cp -a "$_p" "$BDI_BACKUP_DIR/$_name" 2>/dev/null && _n=$((_n + 1))
  done <<EOF
$(backup_items)
EOF

  # Дамп xfconf: только каналы, которые установщик трогает. Читаем в файл,
  # чтобы uninstall мог показать прежние значения руками, если журнал потерян.
  if command -v xfconf-query >/dev/null 2>&1; then
    : > "$BDI_BACKUP_DIR/xfconf.txt"
    for _ch in xfce4-panel xfce4-session xfwm4 xfce4-desktop; do
      printf '### %s\n' "$_ch" >> "$BDI_BACKUP_DIR/xfconf.txt"
      xfconf-query -c "$_ch" -lv >> "$BDI_BACKUP_DIR/xfconf.txt" 2>/dev/null || true
    done
  fi

  printf '%s\n' "$BDI_BACKUP_DIR" > "${BDI_STATE:-$HOME/.local/state/bdi}/last-backup"
  printf 'резервная копия: %s (%s каталогов)\n' "$BDI_BACKUP_DIR" "$_n"
}
