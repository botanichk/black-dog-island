#!/bin/sh
# Погода для выпадающей панели острова.
# Данные - Open-Meteo (тот же источник, что у Noctalia), координаты - из
# ~/.cache/noctalia/location.json, город - BigDataCloud (по-русски, как в Noctalia).
#
# usage: forecast.sh <ключ>
#   city | temp | feels | desc | wind | hum
#   d<N>name | d<N>desc | d<N>temp   (N = 0..3, прогноз по дням)
#   d<N>sun | d<N>set
set -eu

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/eww-island"
LOC="$HOME/.cache/noctalia/location.json"
SNAP="$CACHE/weather.json"
CITYF="$CACHE/city.txt"
mkdir -p "$CACHE"

key=${1:-}

# --- Координаты: сперва из Noctalia, иначе Город (по умолчанию) ---
if [ -r "$LOC" ]; then
  LAT=$(jq -r '.latitude // empty' "$LOC" 2>/dev/null || true)
  LON=$(jq -r '.longitude // empty' "$LOC" 2>/dev/null || true)
fi
[ -n "${LAT:-}" ] || LAT=0.0
[ -n "${LON:-}" ] || LON=0.0

# --- Кэш данных на 10 минут: панель открывается часто, лимит API не безграничен ---
need=0
[ -s "$SNAP" ] || need=1
[ "$need" -eq 0 ] && [ $(( $(date +%s) - $(stat -c %Y "$SNAP") )) -gt 600 ] && need=1

if [ "$need" -eq 1 ]; then
  tmp="$SNAP.tmp.$$"
  if curl -s --max-time 10 \
    "https://api.open-meteo.com/v1/forecast?latitude=$LAT&longitude=$LON&current=temperature_2m,apparent_temperature,weather_code,wind_speed_10m,relative_humidity_2m&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset&timezone=auto&forecast_days=4" \
    -o "$tmp" && [ -s "$tmp" ] && jq -e '.current.temperature_2m' "$tmp" >/dev/null 2>&1; then
    mv "$tmp" "$SNAP"
  else
    rm -f "$tmp"
  fi
fi

[ -s "$SNAP" ] || { printf '%s\n' "—"; exit 0; }

# --- Город по координатам (кеш на сутки) ---
if [ ! -s "$CITYF" ] || [ $(( $(date +%s) - $(stat -c %Y "$CITYF") )) -gt 86400 ]; then
  city=$(curl -s --max-time 8 \
    "https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=$LAT&longitude=$LON&localityLanguage=ru" \
    | jq -r '.city // .locality // .principalSubdivision // empty' 2>/dev/null || true)
  if [ -n "${city:-}" ]; then
    printf '%s\n' "$city" > "$CITYF.tmp.$$"
    mv "$CITYF.tmp.$$" "$CITYF"
  else
    rm -f "$CITYF.tmp.$$"
  fi
fi

# --- Названия погоды по кодам WMO (те же, что у Open-Meteo и Noctalia) ---
describe() {
  case "$1" in
    0) printf 'Ясно' ;;
    1) printf 'Преимущественно ясно' ;;
    2) printf 'Переменная облачность' ;;
    3) printf 'Пасмурно' ;;
    45|48) printf 'Туман' ;;
    51|53|55) printf 'Морось' ;;
    56|57) printf 'Ледяная морось' ;;
    61) printf 'Небольшой дождь' ;;
    63) printf 'Дождь' ;;
    65) printf 'Сильный дождь' ;;
    66|67) printf 'Ледяной дождь' ;;
    71|73|75|77) printf 'Снег' ;;
    80|81|82) printf 'Ливни' ;;
    85|86) printf 'Снегопад' ;;
    95) printf 'Гроза' ;;
    96|99) printf 'Гроза с градом' ;;
    *) printf 'Погода' ;;
  esac
}

# --- Дата по-русски: локали в системе называются по-разному ---
ru_wd() {
  case "$(LC_ALL=ru_RU.utf8 date -d "$1" '+%a' 2>/dev/null)" in
    Пн*) printf 'пн' ;; Вт*) printf 'вт' ;; Ср*) printf 'ср' ;; Чт*) printf 'чт' ;;
    Пт*) printf 'пт' ;; Сб*) printf 'сб' ;; Вс*) printf 'вс' ;;
    *) printf '%s' "$(LC_ALL=ru_RU.utf8 date -d "$1" '+%a' 2>/dev/null || date -d "$1" '+%a')" ;;
  esac
}

ru_mo() {
  case "$(LC_ALL=ru_RU.utf8 date -d "$1" '+%b' 2>/dev/null)" in
    янв*) printf 'янв' ;; фев*) printf 'фев' ;; мар*) printf 'мар' ;; апр*) printf 'апр' ;;
    май*) printf 'май' ;; июн*) printf 'июн' ;; июл*) printf 'июл' ;; авг*) printf 'авг' ;;
    сен*) printf 'сен' ;; окт*) printf 'окт' ;; ноя*) printf 'ноя' ;; дек*) printf 'дек' ;;
    *) printf '%s' "$(LC_ALL=ru_RU.utf8 date -d "$1" '+%b' 2>/dev/null || date -d "$1" '+%b')" ;;
  esac
}

case "$key" in
  city)  jq -r '.name // empty' "$CITYF" 2>/dev/null || cat "$CITYF" 2>/dev/null || printf '—' ;;
  temp)  jq -r '.current.temperature_2m' "$SNAP" ;;
  feels) jq -r '.current.apparent_temperature' "$SNAP" ;;
  desc)  describe "$(jq -r '.current.weather_code' "$SNAP")" ;;
  wind)  jq -r '.current.wind_speed_10m' "$SNAP" ;;
  hum)   jq -r '.current.relative_humidity_2m' "$SNAP" ;;
  d[0-3]name)
    i=${key#d}; i=${i%name}
    d=$(jq -r ".daily.time[$i]" "$SNAP")
    printf '%s %s %s' "$(ru_wd "$d")" "$(LC_ALL=ru_RU.utf8 date -d "$d" '+%d' 2>/dev/null || date -d "$d" '+%d')" "$(ru_mo "$d")"
    ;;
  d[0-3]desc)
    i=${key#d}; i=${i%desc}
    describe "$(jq -r ".daily.weather_code[$i]" "$SNAP")"
    ;;
  d[0-3]temp)
    i=${key#d}; i=${i%temp}
    printf '%s…%s' "$(jq -r ".daily.temperature_2m_min[$i]" "$SNAP")" "$(jq -r ".daily.temperature_2m_max[$i]" "$SNAP")"
    ;;
  d[0-3]sun)
    i=${key#d}; i=${i%sun}
    jq -r ".daily.sunrise[$i]" "$SNAP" | cut -dT -f2 | cut -d+ -f1
    ;;
  d[0-3]set)
    i=${key#d}; i=${i%set}
    jq -r ".daily.sunset[$i]" "$SNAP" | cut -dT -f2 | cut -d+ -f1
    ;;
  *)
    printf '%s\n' "—" >&2
    exit 2
    ;;
esac
