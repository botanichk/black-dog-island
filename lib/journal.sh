# lib/journal.sh - журнал изменений для отката (уровень 2).
#
# Формат строки, разделитель - TAB, чтобы значения с пробелами не ломались:
#   <время>  <тип>  <цель>  <старое>  <новое>
#   тип: xfconf | file | autostart | pkg | process
#   пустое старое = "ключа не было", пустое новое = "ключа не должно быть"
#
# uninstall идёт по журналу снизу вверх и возвращает значение, только если
# текущее совпадает с записанным "новым". Иначе пользователь уже поменял сам.
# Нет записи - нет изменения: всё, что менять, проходит через journal_add.

BDI_JOURNAL="${BDI_STATE:-$HOME/.local/state/bdi}/changes.log"

journal_add() {  # journal_add <тип> <цель> <старое> <новое>
  mkdir -p "$(dirname "$BDI_JOURNAL")" 2>/dev/null || true
  # TAB внутри значений недопустим - заменяем на пробел.
  _t=$(printf '%s' "$1" | tr '\t' ' ')
  _c=$(printf '%s' "$2" | tr '\t' ' ')
  _o=$(printf '%s' "$3" | tr '\t' ' ')
  _n=$(printf '%s' "$4" | tr '\t' ' ')
  printf '%s\t%s\t%s\t%s\t%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" \
    "$_t" "$_c" "$_o" "$_n" >> "$BDI_JOURNAL"
}

# journal_get <тип> <цель> - последнее записанное "старое", печатает в stdout.
# Код 1, если записи нет.
journal_get() {
  [ -r "$BDI_JOURNAL" ] || return 1
  _v=$(awk -F'\t' -v t="$1" -v c="$2" '$2==t && $3==c {v=$4} END{print v}' "$BDI_JOURNAL")
  [ -n "$_v" ] || return 1
  printf '%s\n' "$_v"
}

# journal_count - сколько записей, для отчёта uninstall.
journal_count() {
  [ -r "$BDI_JOURNAL" ] || { echo 0; return 0; }
  wc -l < "$BDI_JOURNAL" | tr -d ' '
}
