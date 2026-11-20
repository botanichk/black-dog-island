# lib/log.sh - единый формат сообщений установщика.
# Подключается через `. lib/log.sh`; менять окружение не должен.
#
# Цвета только если stdout - терминал: в лог и в `report` попадает чистый текст.

if [ -t 1 ]; then
  _c_ok=$(printf '\033[32m'); _c_warn=$(printf '\033[33m')
  _c_err=$(printf '\033[31m'); _c_off=$(printf '\033[0m')
else
  _c_ok= _c_warn= _c_err= _c_off=
fi

# log_info "текст" - обычная строка.
log_info() { printf '%s\n' "$*"; }

# log_ok "текст" - проверка пройдена.
log_ok() { printf '%sOK%s   %s\n' "$_c_ok" "$_c_off" "$*"; }

# log_warn "текст" - работает, но с оговоркой.
log_warn() { printf '%sWARN%s %s\n' "$_c_warn" "$_c_off" "$*"; }

# log_fail "текст [как исправить]" - не работает.
log_fail() { printf '%sFAIL%s %s\n' "$_c_err" "$_c_off" "$*"; }

# log_step "текст" - начало этапа install.
log_step() { printf '\n== %s\n' "$*"; }

# log_ask "вопрос" - да/нет, код 0 для да. Читает stdin, поэтому в тестах
# подставляется `yes`/`no` через echo. Неинтерактивно - считаем "нет".
log_ask() {
  printf '%s [д/н] ' "$*"
  _ans=""
  read -r _ans 2>/dev/null || return 1
  case "$_ans" in
    д|Д|y|Y|да|yes) return 0 ;;
    *) return 1 ;;
  esac
}
