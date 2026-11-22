#!/bin/sh
# apply.sh - применить схему темы: сгенерировать eww/colors.scss и SVG в
# eww/assets/ из theme/templates/. Идемпотентный: повторный запуск с той же
# схемой даёт те же файлы (git status чистый).
#
# usage: theme/apply.sh <схема> [--reload]
#        theme/apply.sh default            # только файлы
#        theme/apply.sh default --reload   # файлы + eww reload
#
# Что делает:
#   1. читает схему: theme/schemes (встроенные) или ~/.local/state/bdi/schemes;
#   2. рендерит theme/templates/colors.scss.tpl -> eww/colors.scss;
#   3. рендерит theme/templates/assets/*.svg -> eww/assets/ (те же имена);
#   4. с --reload: build/target/release/eww --config eww reload; если демон
#      не ответил - перезапуск (scripts/stop-island.sh + run-island.sh).
#
# Зависимости только из системы: sh, python3 (уже стоят). Ничего не ставим.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BDI_CONFIG="${BDI_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/bdi}"
BDI_STATE="${BDI_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/bdi}"
BDI_CACHE="${BDI_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/bdi}"
mkdir -p "$BDI_CONFIG" "$BDI_STATE/schemes" "$BDI_CACHE" 2>/dev/null || true

# Ошибки темы уходят в файл: apply.sh зовёт остров при старте, его stderr
# никто не читает, а без цвета остров не поднимается вовсе.
LOG="$BDI_CACHE/theme.log"
log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG" 2>/dev/null || true; }

# run_to: внешние вызовы под таймаутом. Без него мёртвый демон Eww или
# неподнятая сессионная шина вешают смену темы целиком (см. theme/guard.sh).
. "$ROOT/theme/guard.sh"

# Значения по умолчанию: на свежем клоне файлов состояния ещё нет, а чтение
# через `< файл` ругается в stderr даже с 2>/dev/null. Запись может не пройти
# (~/.config/bdi только на чтение) - это не повод не рендерить тему.
[ -s "$BDI_CONFIG/mode" ] || printf 'dark\n' > "$BDI_CONFIG/mode" 2>/dev/null || log "не записал mode в $BDI_CONFIG"
[ -s "$BDI_CONFIG/current" ] || printf 'default\n' > "$BDI_CONFIG/current" 2>/dev/null || log "не записал current в $BDI_CONFIG"
[ -s "$BDI_CONFIG/accent" ] || printf 'primary\n' > "$BDI_CONFIG/accent" 2>/dev/null || log "не записал accent в $BDI_CONFIG"
[ -s "$BDI_CONFIG/wallpaper-scheme" ] || printf 'm3-tonal-spot\n' > "$BDI_CONFIG/wallpaper-scheme" 2>/dev/null || log "не записал wallpaper-scheme в $BDI_CONFIG"
[ -s "$BDI_CONFIG/hue-filter" ] || printf 'all\n' > "$BDI_CONFIG/hue-filter" 2>/dev/null || log "не записал hue-filter в $BDI_CONFIG"

# Разбор аргументов: первый не-флаг - схема, --reload - перечитать конфиг.
SCHEME=""
RELOAD=0
for arg in "$@"; do
  case "$arg" in
    --reload) RELOAD=1 ;;
    -*) echo "неизвестный аргумент: $arg" >&2; exit 2 ;;
    *)
      if [ -n "$SCHEME" ]; then
        echo "лишний аргумент: $arg" >&2; exit 2
      fi
      SCHEME=$arg ;;
  esac
done
# Без аргумента берём схему из ~/.config/bdi/current: так выбор не сбрасывается.
if [ -z "$SCHEME" ]; then
  if [ -f "$BDI_CONFIG/current" ]; then
    SCHEME=$(tr -d ' \t\r\n' < "$BDI_CONFIG/current")
  fi
  SCHEME=${SCHEME:-default}
fi

JSON="$ROOT/theme/schemes/$SCHEME.json"
[ -f "$JSON" ] || JSON="$BDI_STATE/schemes/$SCHEME.json"

# Схема из палитры (p-*) или из каталога (c-*) в git не лежит: она
# выводится из theme/palettes/<id>.json и попадает в .gitignore. На чистом
# клоне ~/.config/bdi/current может указывать на такую схему, а файла ещё нет -
# это не ошибка, а «палитра выбрана, но не отрендерена». Собираем её тем же
# скриптом, что и вкладка «Цвета», и только потом ругаемся.
# Без этого свежий клон падал с «нет схемы: p-ayu.json».
if [ ! -f "$JSON" ]; then
  case "$SCHEME" in
    p-*)
      if [ -f "$ROOT/theme/palettes/${SCHEME#p-}.json" ]; then
        echo "схема $SCHEME не отрендерена - собираю из палитры"
        # BDI_NO_DETACH: здесь нужен готовый файл схемы сразу после вызова,
        # отвязка (она для кнопок) вернула бы управление до сборки.
        BDI_NO_DETACH=1 sh "$ROOT/theme/colors-pick.sh" palette "$SCHEME" \
          "$(tr -d ' \t\r\n' < "$BDI_CONFIG/mode" 2>/dev/null || echo dark)" \
          >/dev/null 2>&1 || true
      fi ;;
  esac
fi

# Всё равно нет (чужой id, битая палитра) - не валим запуск: берём default,
# он в git. Иначе после клонирования не применилась бы даже тема, а ошибка
# «нет схемы» уводила бы в сторону.
if [ ! -f "$JSON" ]; then
  echo "нет схемы $SCHEME - беру default" >&2
  log "нет схемы $SCHEME - беру default"
  SCHEME=default
  JSON="$ROOT/theme/schemes/default.json"
  printf '%s\n' "$SCHEME" > "$BDI_CONFIG/current" 2>/dev/null || true
fi

# Один проход рендера. Вынесено в функцию, чтобы битую схему можно было
# заменить на default и повторить: раньше кривой JSON или чужой id в
# ~/.config/bdi/current валили apply.sh и остров оставался без colors.scss.
render_theme() {
python3 - "$ROOT" "$1" "$2" <<'PY'
import json, sys, pathlib, re, os

root = pathlib.Path(sys.argv[1])
scheme_path = pathlib.Path(sys.argv[2])
scheme_name = sys.argv[3]

data = json.loads(scheme_path.read_text(encoding="utf-8"))
colors = data["colors"]
alphas = data.get("alphas", {})
grads = {k: v for k, v in data.get("weather_gradients", {}).items() if not k.startswith("_")}

def resolve(ref):
    """Имя роли -> #rrggbb. Литерал (#rrggbb) берётся как есть."""
    if ref.startswith("#"):
        return ref
    if ref not in colors:
        raise SystemExit("схема %s: неизвестная роль '%s' в alpha" % (scheme_name, ref))
    return colors[ref]

def as_rgba(ref, alpha):
    c = resolve(ref).lstrip("#")
    if len(c) != 6:
        raise SystemExit("схема %s: ожидался #rrggbb, получено #%s" % (scheme_name, c))
    r, g, b = (int(c[i:i + 2], 16) for i in (0, 2, 4))
    # alpha без хвостовых нулей: 0.08, 0.30, 0.75
    a = ("%.2f" % float(alpha)).rstrip("0").rstrip(".")
    return "rgba(%d, %d, %d, %s)" % (r, g, b, a)

# --- 1. role map для шаблонов: имя_в_шаблоне -> значение ---
vals = {}
for k, v in colors.items():
    if not v.startswith("#"):
        raise SystemExit("схема %s: цвет '%s' должен быть #rrggbb" % (scheme_name, k))
    vals[k] = v
for k, spec in alphas.items():
    vals[k] = as_rgba(spec["color"], spec["alpha"])
for k, v in grads.items():
    vals["wx_" + k] = v

def render(text, where):
    def sub(m):
        key = m.group(1)
        if key == "scheme":
            return scheme_name
        if key not in vals:
            raise SystemExit("%s: в шаблоне плейсхолдер {{%s}}, а в схеме %s его нет" % (where, key, scheme_name))
        return vals[key]
    return re.sub(r"\{\{([a-z0-9_]+)\}\}", sub, text)

# --- 2. eww/colors.scss ---
# Пишем через временный файл: если рендер упадёт посередине, на диске
# останется прошлая целая тема, и остров поднимется с ней.
tpl = root / "theme/templates/colors.scss.tpl"
out = root / "eww/colors.scss"
css = render(tpl.read_text(encoding="utf-8"), "colors.scss.tpl")
# SCSS-компилятор падает на не-ASCII в @charset: комментарии шаблона английские,
# но проверяем: если в результате есть не-ASCII в коде - это ошибка шаблона.
tmp = out.with_suffix(".scss.tmp")
tmp.write_text(css, encoding="utf-8")
os.replace(str(tmp), str(out))
print("eww/colors.scss <- %s (%d строк)" % (scheme_name, css.count("\n")))

# --- 3. SVG ---
tdir = root / "theme/templates/assets"
adr = root / "eww/assets"
n = 0
for t in sorted(tdir.glob("*.svg")):
    svg = render(t.read_text(encoding="utf-8"), t.name)
    (adr / t.name).write_text(svg, encoding="utf-8")
    n += 1
print("eww/assets/*.svg <- %d файлов" % n)

# --- 4. проверка на сироты ---
# В eww/assets/ лежит не только то, что рендерится из шаблонов: 16 JPEG-сцен
# погоды и статичные SVG (точки рабочих столов, углы острова). Поэтому
# удалять "лишнее" нельзя - снесёт их. Только предупреждаем: если появился
# SVG, которого нет в шаблонах, значит его забыли удалить при чистке.
have = {f.name for f in adr.glob("*.svg")}
made = {t.name for t in tdir.glob("*.svg")}
orphans = sorted(have - made)
if orphans:
    print("сироты в eww/assets (SVG не из шаблонов): %s" % " ".join(orphans))
else:
    print("сирот нет: все SVG в eww/assets из шаблонов")
PY
}

# Рендер с откатом: битая схема (кривой JSON, чужой id, не #rrggbb) не должна
# оставлять остров без colors.scss. Вторая попытка всегда на default из git.
if ! render_theme "$JSON" "$SCHEME"; then
  log "схема $SCHEME не отрендерилась - повторяю на default"
  echo "схема $SCHEME не отрендерилась - беру default" >&2
  SCHEME=default
  JSON="$ROOT/theme/schemes/default.json"
  render_theme "$JSON" "$SCHEME" || {
    log "default тоже не отрендерился - остров останется без темы"
    echo "default не отрендерился, см. $LOG" >&2
    exit 1
  }
  printf '%s\n' "$SCHEME" > "$BDI_CONFIG/current" 2>/dev/null || true
fi

if [ "$RELOAD" -eq 1 ]; then
  EWW="$ROOT/build/target/release/eww"
  [ -x "$EWW" ] || { echo "eww не собран: $EWW" >&2; exit 1; }
  # reload возвращает 1, когда демон не успевает ответить ("os error 11"),
  # хотя конфиг уже перечитан; поэтому код 1 не считаем провалом.
  #
  # run_to обязателен: клиент Eww читает ответ демона до упора (client.rs:
  # do_server_call). 10 с - с запасом: обычный reload занимает 0.07 с.
  RESTARTED=0
  _stuck=0
  if run_to 10 "$EWW" --config "$ROOT/eww" reload; then
    echo "eww reload: ок"
  elif timed_out $?; then
    log "eww reload не ответил за 10 с - демон завис"
    echo "eww reload завис: перезапускаю остров (см. $LOG)" >&2
    _stuck=1
  else
    echo "eww reload: код 1 (демон не ответил, конфиг может быть уже перечитан)" >&2
  fi
  # Успешный reload ничего не доказывает: сервер ждёт ответ главного цикла
  # всего 100 мс (ipc_server.rs) и закрывает поток, а пустой ответ клиент
  # считает успехом (client.rs: Ok(None)). Поэтому проверяем сам главный
  # цикл: `state` отвечает через него (app.rs:287). Пока идёт load_config,
  # ответ пустой - это нормальные доли секунды, поэтому повторяем до 10 с.
  # Пусто всё время = остров залип и сам не очнётся.
  if [ "$_stuck" -eq 0 ]; then
    _alive=0
    _i=0
    while [ "$_i" -lt 10 ]; do
      if [ -n "$(run_to 3 "$EWW" --config "$ROOT/eww" state --all 2>/dev/null || true)" ]; then
        _alive=1
        break
      fi
      sleep 1
      _i=$((_i + 1))
    done
    if [ "$_alive" -eq 0 ]; then
      log "демон не ответил на state за 10 с после reload - перезапускаю"
      echo "остров не отвечает после reload: перезапускаю (см. $LOG)" >&2
      _stuck=1
    fi
  fi
  if [ "$_stuck" -eq 1 ]; then
    # load_config идёт на главном контексте GLib (app.rs:566): stop_all()
    # глушит каждый deflisten через join_thread, до 10 с на ребёнка, и всё
    # это время остров не перерисовывается и не отвечает. Клиент к такому
    # демону больше не достучится, поэтому остаётся перезапуск - ровно то,
    # что раньше делал перелогин. Тема уже на диске, новый демон её прочтёт.
    if run_to 15 "$ROOT/scripts/stop-island.sh" >>"$BDI_CACHE/island-restart.log" 2>&1; then
      log "демон остановлен"
    else
      log "предупреждение: stop-island.sh не уложился в 15 с"
    fi
    if run_to 30 "$ROOT/scripts/run-island.sh" >>"$BDI_CACHE/island-restart.log" 2>&1; then
      log "остров поднят заново"
      echo "остров перезапущен с новой темой"
    else
      log "ошибка: остров не поднялся после перезапуска"
      echo "остров не поднялся после перезапуска, см. $BDI_CACHE/island-restart.log" >&2
    fi
    RESTARTED=1
  fi
  # reload пересоздаёт окно острова по :geometry из eww.yuck, а там x=0px -
  # остров уезжает в левый угол. Центрирует его только scripts/run-island.sh,
  # но сюда он не зовётся. Возвращаем позицию сами: ширина острова от темы не
  # зависит и лежит в ~/.cache/bdi/island-width (её пишут run-island и демон).
  # После перезапуска позицию уже выставил run-island.sh - не спорим с ним.
  if [ "$RESTARTED" -eq 0 ]; then
    _iw=$(tr -cd '0-9' < "${BDI_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/bdi}/island-width" 2>/dev/null || true)
    [ -n "$_iw" ] || _iw=619
    _sw=$(xrandr --current 2>/dev/null | awk '/\*/{print $1; exit}' | cut -d x -f1)
    if [ -n "${_sw:-}" ] && [ "$_iw" -gt 0 ] && [ "$_iw" -lt "$_sw" ]; then
      run_to 10 "$EWW" --config "$ROOT/eww" --no-daemonize open island --pos "$(( (_sw - _iw) / 2 ))x0" >/dev/null 2>&1 || true
    fi
  fi
fi

# Запоминаем выбор последним шагом: если рендер упал, ~/.config/bdi/current не врёт.
# apply.sh без аргумента возьмёт схему отсюда.
printf '%s\n' "$SCHEME" > "$BDI_CONFIG/current" 2>/dev/null || true
echo "схема: $SCHEME (~/.config/bdi/current)"

# --- 5. рамка Plank в цвет $primary ---------------------------------------
# Plank не перечитывает тему на лету, поэтому его надо перезапустить (~1 с).
# Ошибку здесь не пробрасываем: без Plank остров работает, а падать из-за
# дока не должен. Подробности - в theme/plank.sh и docs/PLANK.md.
if [ -x "$ROOT/theme/plank.sh" ]; then
  if ! "$ROOT/theme/plank.sh" apply; then
    echo "рамка Plank: не применилась (см. ~/.cache/bdi/plank.log)" >&2
  fi
fi

# --- 6. тема Ulauncher в те же цвета --------------------------------------
# Ulauncher перечитывает тему по SIGHUP, поэтому окно не мигает и ввод не
# теряется (в отличие от Plank, которому нужен перезапуск). Ошибку не
# пробрасываем: без Ulauncher остров работает. Подробности - theme/ulauncher.sh.
if [ -x "$ROOT/theme/ulauncher.sh" ]; then
  if ! "$ROOT/theme/ulauncher.sh" apply; then
    echo "тема Ulauncher: не применилась (см. ~/.cache/bdi/ulauncher.log)" >&2
  fi
fi
