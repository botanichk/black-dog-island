# lib/backup.sh - резервная копия настроек перед изменениями.
# Уровень 1 откатa: копия каталогов и дамп xfconf. Уровень 2 - журнал
# (lib/journal.sh), он возвращает отдельные значения.
#
# Что копируем: только то, что установщик может изменить. Своё состояние
# (~/.config/bdi) не копируем - его uninstall и так оставляет.

BDI_BACKUP_DIR=""

# backup_create - создать копию, путь положить в BDI_BACKUP_DIR.
# Код 0 при успехе. Если копировать нечего - всё равно создаём каталог:
# uninstall должен иметь куда смотреть.
backup_create() {
  _stamp=$(date '+%Y%m%d-%H%M%S')
  BDI_BACKUP_DIR="${BDI_STATE:-$HOME/.local/state/bdi}/backup-$_stamp"
  mkdir -p "$BDI_BACKUP_DIR" || return 1

  # Каталоги настроек. Нет каталога - не ошибка (чистый XFCE, нет Plank).
  _n=0
  for _p in "$HOME/.config/xfce4" "$HOME/.config/autostart" \
            "$HOME/.config/plank" "$HOME/.config/ulauncher" \
            "$HOME/.config/hypr-wallpicker"; do
    [ -d "$_p" ] || continue
    _name=$(printf '%s' "$_p" | sed "s|^$HOME/||; s|/|_|g")
    cp -a "$_p" "$BDI_BACKUP_DIR/$_name" 2>/dev/null && _n=$((_n + 1))
  done

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
