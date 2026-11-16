#!/bin/sh
# Вкладка «Главная» хаба: состояния плиток и ползунков, плюс сами действия.
#
# usage: home.sh all                    - одна строка JSON для defpoll
#        home.sh set wifi on|off        - радиомодуль Wi-Fi
#        home.sh set bt on|off          - питание Bluetooth
#        home.sh set mute toggle        - звук: выключить/включить
#        home.sh set volume N           - громкость, 0..100
#        home.sh set brightness N       - яркость, 5..100
#
# Почему JSON одной строкой: defpoll с шестью отдельными командами запускал бы
# шесть процессов раз в 2 с. Здесь один вызов и одна переменная Eww.
#
# Яркость: писать в /sys/class/backlight/*/brightness напрямую нельзя (файл
# root:root, ACL для пользователя нет). brightnessctl идёт в
# org.freedesktop.login1.Session.SetBrightness - только так и меняем.
set -eu

PA_CMD="pactl"
MIN_BRIGHT=5

# --- чтение ---

wifi_state() {
  case "$(nmcli radio wifi 2>/dev/null || echo disabled)" in
    enabled) echo on ;;
    *)       echo off ;;
  esac
}

bt_state() {
  v=$(bluetoothctl show 2>/dev/null | sed -n 's/^[[:space:]]*Powered:[[:space:]]*//p' | head -1 || true)
  [ "${v:-no}" = "yes" ] && echo yes || echo no
}

mute_state() {
  v=$("$PA_CMD" get-sink-mute @DEFAULT_SINK@ 2>/dev/null | sed 's/.*:[[:space:]]*//' || true)
  [ "${v:-no}" = "yes" ] && echo yes || echo no
}

volume_state() {
  v=$("$PA_CMD" get-sink-volume @DEFAULT_SINK@ 2>/dev/null | grep -o '[0-9]\+%' | head -1 | tr -d % || true)
  echo "${v:-0}"
}

# Процент яркости. В этой версии brightnessctl (0.5.1) операция get с -m
# машиночитаемый формат не включает и печатает просто число: нужен `-m i`
# (info) - "устройство,класс,значение,процент,максимум".
brightness_state() {
  v=$(brightnessctl -m i 2>/dev/null | cut -d, -f4 | tr -d % || true)
  if [ -z "${v:-}" ]; then
    # Запасной путь - только чтение sysfs (на запись прав нет).
    cur=$(cat /sys/class/backlight/*/brightness 2>/dev/null | head -1 || true)
    max=$(cat /sys/class/backlight/*/max_brightness 2>/dev/null | head -1 || true)
    if [ -n "${cur:-}" ] && [ -n "${max:-}" ] && [ "$max" -gt 0 ]; then
      v=$((cur * 100 / max))
    else
      v=0
    fi
  fi
  echo "${v:-0}"
}

# Температура: максимум по датчикам hwmon. Имена ключей EWW_TEMPS зависят от
# машины (здесь CORETEMP_PACKAGE_ID_0, на другой машине его нет), поэтому
# берём максимум из sysfs: без угадывания ключей и без опроса в лог.
temp_state() {
  max=0
  for f in /sys/class/hwmon/hwmon*/temp*_input; do
    [ -r "$f" ] || continue
    t=$(cat "$f" 2>/dev/null || echo 0)
    t=$((t / 1000))
    [ "$t" -gt "$max" ] && max=$t
  done
  echo "$max"
}

# --- запись ---

# Текущее состояние -> новое: для "toggle" и для плиток.
toggle_of() { # toggle_of on|off|yes|no
  case "${1:-}" in
    on|yes) echo off ;;
    *)      echo on ;;
  esac
}

clamp() { # clamp <значение> <мин> <макс>
  v=$(printf '%.0f' "$1" 2>/dev/null || echo 0)
  [ "$v" -lt "$2" ] && v=$2
  [ "$v" -gt "$3" ] && v=$3
  echo "$v"
}

case "${1:-}" in
  all)
    # charging: "yes", пока адаптер подключён и батарея заряжается.
    st=$(cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -1 || true)
    case "${st:-}" in
      Charging|"Full") charging=yes ;;
      *)               charging=no ;;
    esac
    printf '{"wifi":"%s","bt":"%s","mute":"%s","volume":%s,"brightness":%s,"temp":%s,"charging":"%s"}\n' \
      "$(wifi_state)" "$(bt_state)" "$(mute_state)" \
      "$(volume_state)" "$(brightness_state)" "$(temp_state)" "$charging"
    ;;
  set)
    key=${2:-}
    val=${3:-}
    case "$key" in
      wifi)
        case "$val" in
          on)  nmcli radio wifi on ;;
          off) nmcli radio wifi off ;;
          toggle) nmcli radio wifi "$(toggle_of "$(wifi_state)")" ;;
          *)   echo "home.sh: wifi on|off|toggle" >&2; exit 2 ;;
        esac
        ;;
      bt)
        case "$val" in
          on)  bluetoothctl power on >/dev/null ;;
          off) bluetoothctl power off >/dev/null ;;
          toggle)
            # bluetoothctl печатает "Powered: yes/no"; состояние уже прочитано.
            [ "$(bt_state)" = "yes" ] && bluetoothctl power off >/dev/null || bluetoothctl power on >/dev/null ;;
          *)   echo "home.sh: bt on|off|toggle" >&2; exit 2 ;;
        esac
        ;;
      mute)
        case "$val" in
          toggle|"") "$PA_CMD" set-sink-mute @DEFAULT_SINK@ toggle ;;
          on)  "$PA_CMD" set-sink-mute @DEFAULT_SINK@ 0 ;;
          off) "$PA_CMD" set-sink-mute @DEFAULT_SINK@ 1 ;;
          *)   echo "home.sh: mute toggle|on|off" >&2; exit 2 ;;
        esac
        ;;
      volume)
        n=$(clamp "${val:-0}" 0 100)
        "$PA_CMD" set-sink-volume @DEFAULT_SINK@ "${n}%"
        ;;
      brightness)
        n=$(clamp "${val:-0}" "$MIN_BRIGHT" 100)
        brightnessctl set "${n}%" >/dev/null 2>&1 || true
        ;;
      *)
        echo "home.sh: set wifi|bt|mute|volume|brightness" >&2
        exit 2
        ;;
    esac
    ;;
  *)
    echo "usage: home.sh all | home.sh set wifi|bt|mute|volume|brightness <значение>" >&2
    exit 2
    ;;
esac
