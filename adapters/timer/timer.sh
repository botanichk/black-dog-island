#!/bin/sh
# Таймер острова: обратный отсчёт с будильником.
#
# usage: timer.sh start <время>   # 10, 6m, 1h30m, 90s
#        timer.sh pause | resume | reset | stop-sound
#        timer.sh status          # JSON одной строкой для Eww
#        timer.sh selftest        # проверка разбора времени (без звука)
#        timer.sh tick            # раз в секунду: двигает отсчёт, звонит
#        timer.sh watch           # сторож: звонит, даже если остров скрыт
#
# Почему время хранится меткой конца, а не счётчиком: отсчёт не зависит от
# того, открыта ли панель, жив ли Eww и сколько раз он перезапустился. Раньше
# в плагине Noctalia секунды вычитались в update() сервиса - там отсчёт умирал
# вместе с сервисом и шёл с ошибкой накопления.
#
# Состояние - файлы в ~/.cache/eww-island/timer/:
#   end      метка конца (unix-время, целые секунды); при паузе - пусто
#   left     остаток на паузе в секундах
#   total    длительность постановки (для полоски прогресса)
#   ringing  1, пока играет будильник
#
# Зависимости только системные: sh, date, mkdir, pw-play/paplay, notify-send.

set -eu

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/eww-island/timer"
SOUNDS="$HOME/eww-island/adapters/timer/sounds"
mkdir -p "$CACHE"

# Звук будильника: файлы из папки sounds/, выбранный - в $CACHE/sound (имя
# файла). Пусто или файл пропал - первый по алфавиту. Так звук меняется без
# правки кода: положил файл в папку, выбрал его кнопкой в панели.
current_sound() {
  _s=$(cat "$CACHE/sound" 2>/dev/null || true)
  if [ -n "$_s" ] && [ -f "$SOUNDS/$_s" ]; then
    printf '%s' "$SOUNDS/$_s"
  else
    _f=$(ls "$SOUNDS" 2>/dev/null | grep -iE '\.(wav|oga|ogg|mp3|flac)$' | head -1)
    [ -n "$_f" ] || return 1
    printf '%s' "$SOUNDS/$_f"
  fi
}

# Следующий файл по кругу - для кнопки выбора. Печатает имя нового звука.
next_sound() {
  _list=$(ls "$SOUNDS" 2>/dev/null | grep -iE '\.(wav|oga|ogg|mp3|flac)$')
  [ -n "$_list" ] || return 1
  _cur=$(basename "$(current_sound 2>/dev/null || echo -)")
  _first=$(printf '%s\n' "$_list" | head -1)
  _next=$_first
  _take=0
  for _f in $_list; do
    [ "$_f" = "$_cur" ] && { _take=1; continue; }
    [ "$_take" -eq 1 ] && { _next=$_f; break; }
  done
  printf '%s' "$_next"
}

now() { date +%s; }

# "10" - секунды, "6m", "1h30m", "90s", "1:30" - всё в секунды.
parse_duration() {
  _s=$(printf '%s' "$1" | tr -d ' \t')
  [ -n "$_s" ] || { echo 0; return; }
  case "$_s" in
    *:*)
      # mm:ss или hh:mm:ss
      _r=0
      _old_ifs=$IFS; IFS=:
      for _p in $_s; do _r=$((_r * 60 + ${_p:-0})); done
      IFS=$_old_ifs
      echo "$_r"; return ;;
    *[hms]*)
      _r=0; _rest=$_s
      while [ -n "$_rest" ]; do
        _val=${_rest%%[!0-9]*}
        _rest=${_rest#"$_val"}
        _unit=$(printf '%s' "$_rest" | cut -c1)
        _rest=${_rest#?}
        [ -n "$_val" ] || break
        case "$_unit" in
          h) _r=$((_r + _val * 3600)) ;;
          m) _r=$((_r + _val * 60)) ;;
          s) _r=$((_r + _val)) ;;
          *) _r=$((_r + _val)) ;;
        esac
      done
      echo "$_r"; return ;;
    *[!0-9]*|'') echo 0; return ;;
    *) echo "$_s" ;;
  esac
}

read_int() { [ -f "$1" ] && cat "$1" 2>/dev/null || echo 0; }

set_state() { printf '%s' "$2" > "$CACHE/$1"; }

# Сколько осталось. На паузе - из файла, иначе - из метки конца.
remaining() {
  if [ -f "$CACHE/end" ]; then
    _e=$(read_int "$CACHE/end")
    _r=$((_e - $(now)))
    [ "$_r" -gt 0 ] && echo "$_r" || echo 0
  else
    read_int "$CACHE/left"
  fi
}

# Короткий вид для кнопки на острове: минуты без часов, не длиннее 5 знаков
# (3725 -> "62:05"). Панель показывает точный fmt, кнопке хватает минут.
fmtshort() {
  printf '%d:%02d' "$(( ${1:-0} / 60 ))" "$(( ${1:-0} % 60 ))"
}

# 3725 -> "1:02:05", 125 -> "2:05"
fmt() {
  _v=${1:-0}
  _h=$((_v / 3600)); _m=$(((_v % 3600) / 60)); _s=$((_v % 60))
  if [ "$_h" -gt 0 ]; then
    printf '%d:%02d:%02d' "$_h" "$_m" "$_s"
  else
    printf '%d:%02d' "$_m" "$_s"
  fi
}

# Играет ли уже будильник: смотрим pid цикла, а не `pgrep pw-play`. У pw-play
# есть пауза между повторами, когда процесса нет ни мгновения - pgrep в этот
# момент возвращал "не играет", флаг снимался и будильник глох после первого
# проигрывания (поймано на 2-секундном таймере). Цикл живёт постоянно, его pid
# стабилен.
ringing() {
  [ -f "$CACHE/ringing" ] || return 1
  _pid=$(read_int "$CACHE/alarm.pid")
  [ "$_pid" -gt 0 ] && kill -0 "$_pid" 2>/dev/null
}

stop_sound() {
  _pid=$(read_int "$CACHE/alarm.pid")
  [ "$_pid" -gt 0 ] && kill "$_pid" 2>/dev/null || true
  pkill -f 'pw-play.*eww-island/adapters/timer/sounds/' 2>/dev/null || true
  rm -f "$CACHE/ringing" "$CACHE/alarm.pid"
}

start_alarm() {
  # Уже звенит (например, тик и сторож дошли одновременно) - второй цикл не нужен.
  [ -f "$CACHE/ringing" ] && return 0
  : > "$CACHE/ringing"
  # Будильник играет, пока не остановят: цикл по фоновому процессу. Цикл сам
  # снимает флаг, если вышел (pw-play пропал), чтобы док не показывал "звенит"
  # вечно. pid цикла - в alarm.pid, по нему tick отличает живой звонок от
  # осиротевшего флага.
  (
    while [ -f "$CACHE/ringing" ]; do
      ALARM=$(current_sound) || break
      # Не выходим при сбое звука: будильник должен звенеть до "Стоп", даже
      # если первый pw-play не достал устройство. Пауза на ошибке - чтобы
      # отсутствующий плеер не крутил цикл вхолостую.
      if ! pw-play --volume=0.5 "$ALARM" 2>/dev/null; then
        paplay "$ALARM" 2>/dev/null || sleep 1
      fi
    done
    rm -f "$CACHE/ringing" "$CACHE/alarm.pid"
  ) >/dev/null 2>&1 &
  echo $! > "$CACHE/alarm.pid"
  notify-send -a "Eww Island" "Таймер" "Время вышло" 2>/dev/null || true
}

status() {
  _left=$(remaining)
  _total=$(read_int "$CACHE/total")
  if [ -f "$CACHE/end" ]; then _state=run
  elif [ "$_left" -gt 0 ]; then _state=pause
  elif [ -f "$CACHE/ringing" ]; then _state=ring
  else _state=idle; fi
  # Полоска: сколько прошло от постановки, в процентах.
  _pct=0
  if [ "$_total" -gt 0 ]; then
    _pct=$(( (_total - _left) * 100 / _total ))
    [ "$_pct" -lt 0 ] && _pct=0
    [ "$_pct" -gt 100 ] && _pct=100
  fi
  printf '{"state":"%s","left":%d,"total":%d,"pct":%d,"fmt":"%s","short":"%s"}\n' \
    "$_state" "$_left" "$_total" "$_pct" "$(fmt "$_left")" "$(fmtshort "$_left")"
}

case "${1:-status}" in
  start)
    _dur=$(parse_duration "${2:-}")
    if [ "$_dur" -le 0 ]; then
      echo "usage: timer.sh start 10 | 6m | 1h30m" >&2; exit 2
    fi
    stop_sound
    set_state total "$_dur"
    set_state end "$(( $(now) + _dur ))"
    rm -f "$CACHE/left"
    # Сторож в отдельном процессе: тик живёт в defpoll острова, а остров
    # закрывается в fullscreen (игры, кино) - тогда будильник без сторожа
    # опоздал бы до выхода из полного экрана.
    setsid -f "$0" watch >/dev/null 2>&1 || true
    status ;;
  pause)
    if [ -f "$CACHE/end" ]; then
      _left=$(remaining)
      rm -f "$CACHE/end"
      set_state left "$_left"
    fi
    status ;;
  resume)
    if [ ! -f "$CACHE/end" ]; then
      _left=$(read_int "$CACHE/left")
      if [ "$_left" -gt 0 ]; then
        set_state end "$(( $(now) + _left ))"
        setsid -f "$0" watch >/dev/null 2>&1 || true
      fi
    fi
    status ;;
  reset)
    stop_sound
    rm -f "$CACHE/end" "$CACHE/left" "$CACHE/total" "$CACHE/ringing"
    status ;;
  stop-sound)
    stop_sound
    rm -f "$CACHE/end" "$CACHE/left" "$CACHE/total"
    status ;;
  sound-next)
    # Кнопка выбора в панели: следующий звук по кругу, сразу играет отрывок,
    # чтобы было слышно, что выбрал. Отрывок - тот же pw-play, ограниченный
    # по времени: будильник после выбора не остаётся.
    _s=$(next_sound) || { echo "нет звуков в $SOUNDS" >&2; exit 1; }
    printf '%s' "$_s" > "$CACHE/sound"
    _p="$SOUNDS/$_s"
    if command -v timeout >/dev/null 2>&1; then
      timeout 3 pw-play --volume=0.5 "$_p" 2>/dev/null || true
    fi
    printf '{"sound":"%s"}\n' "$_s" ;;
  sound-name)
    # Имя текущего звука без пути - для подписи на кнопке в панели.
    basename "$(current_sound 2>/dev/null || echo "нет звуков")" ;;
  open-sounds)
    # Открыть папку со звуками: там их добавляют. Папку создаём, если её нет -
    # иначе менеджер откроет пустоту. Менеджер берём по умолчанию (xdg-open),
    # а не наутилус жёстко: у разных людей разные файловые менеджеры.
    mkdir -p "$SOUNDS"
    if command -v xdg-open >/dev/null 2>&1; then
      setsid xdg-open "$SOUNDS" >/dev/null 2>&1 &
    else
      setsid nautilus "$SOUNDS" >/dev/null 2>&1 &
    fi
    echo "открыто: $SOUNDS" ;;
  tick)
    # Вызывается defpoll раз в секунду, пока остров жив.
    if [ -f "$CACHE/ringing" ] && ! ringing; then
      # Цикл будильника умер сам - снимаем флаг, чтобы не звонил вечно.
      rm -f "$CACHE/ringing" "$CACHE/alarm.pid"
    fi
    if [ -f "$CACHE/end" ] && [ "$(remaining)" -le 0 ]; then
      rm -f "$CACHE/end"
      set_state left 0
      start_alarm
    fi
    status ;;
  watch)
    # Отдельный процесс на один таймер: спит до конца и звонит, даже если
    # остров скрыт. Сверяет метку конца - сброс, пауза или новый таймер
    # отменяют звонок (метка изменилась или исчезла).
    _e=$(read_int "$CACHE/end")
    [ "$_e" -gt 0 ] || exit 0
    _w=$(( _e - $(now) ))
    if [ "$_w" -gt 0 ]; then sleep "$_w"; fi
    [ "$(read_int "$CACHE/end")" = "$_e" ] || exit 0
    rm -f "$CACHE/end"
    set_state left 0
    start_alarm ;;
  status) status ;;
  selftest)
    # Проверка разбора времени и форматирования - без таймера и без звука.
    _bad=0
    ck() { if [ "$1" = "$2" ]; then :; else echo "FAIL $3: '$1' != '$2'"; _bad=1; fi; }
    ck "$(parse_duration 10)" 10 "секунды"
    ck "$(parse_duration 6m)" 360 "минуты"
    ck "$(parse_duration 90s)" 90 "секунды с s"
    ck "$(parse_duration 1h30m)" 5400 "часы и минуты"
    ck "$(parse_duration 1:30)" 90 "mm:ss"
    ck "$(parse_duration 2:05:10)" 7510 "hh:mm:ss"
    ck "$(parse_duration "")" 0 "пусто"
    ck "$(parse_duration abc)" 0 "мусор"
    ck "$(fmt 0)" "0:00" "fmt 0"
    ck "$(fmt 125)" "2:05" "fmt 125"
    ck "$(fmt 3725)" "1:02:05" "fmt 3725"
  ck "$(fmtshort 0)" "0:00" "fmtshort 0"
  ck "$(fmtshort 125)" "2:05" "fmtshort 125"
  ck "$(fmtshort 3725)" "62:05" "fmtshort 3725"
    # Звуки: имя текущего непустое и существует в папке.
    _snd=$(current_sound)
    if [ -f "$_snd" ]; then :; else echo "FAIL звук: текущий '$_snd' не найден"; _bad=1; fi
    # Следующий по кругу на одном файле - он же; на двух - другой.
    _snd2=$(next_sound)
    if [ -f "$SOUNDS/$_snd2" ]; then :; else echo "FAIL звук: next_sound '$_snd2' не в папке"; _bad=1; fi
    ck "$(basename "$_snd" | grep -cE '\.(wav|oga|ogg|mp3|flac)$')" 1 "звук с расширением"
    [ "$_bad" -eq 0 ] && echo "selftest ok"
    exit "$_bad" ;;
  *) echo "usage: timer.sh start <время> | pause | resume | reset | stop-sound | tick | status" >&2; exit 2 ;;
esac
