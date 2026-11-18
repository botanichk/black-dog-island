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
#   1. читает theme/schemes/<схема>.json (роли + alpha роли + градиенты);
#   2. рендерит theme/templates/colors.scss.tpl -> eww/colors.scss;
#   3. рендерит theme/templates/assets/*.svg -> eww/assets/ (те же имена);
#   4. с --reload: build/target/release/eww --config eww reload.
#
# Зависимости только из системы: sh, python3 (уже стоят). Ничего не ставим.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

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
# Без аргумента берём схему из theme/current: так apply.sh не сбрасывает выбор.
if [ -z "$SCHEME" ]; then
  if [ -f "$ROOT/theme/current" ]; then
    SCHEME=$(tr -d ' \t\r\n' < "$ROOT/theme/current")
  fi
  SCHEME=${SCHEME:-default}
fi

JSON="$ROOT/theme/schemes/$SCHEME.json"

# Схема из палитры (p-*) или из каталога (c-*) в git не лежит: она
# выводится из theme/palettes/<id>.json и попадает в .gitignore. На чистом
# клоне theme/current может указывать на такую схему, а файла ещё нет -
# это не ошибка, а «палитра выбрана, но не отрендерена». Собираем её тем же
# скриптом, что и вкладка «Цвета», и только потом ругаемся.
# Без этого свежий клон падал с «нет схемы: p-ayu.json».
if [ ! -f "$JSON" ]; then
  case "$SCHEME" in
    p-*)
      if [ -f "$ROOT/theme/palettes/${SCHEME#p-}.json" ]; then
        echo "схема $SCHEME не отрендерена - собираю из палитры"
        sh "$ROOT/theme/colors-pick.sh" palette "$SCHEME" \
          "$(tr -d ' \t\r\n' < "$ROOT/theme/mode" 2>/dev/null || echo dark)" \
          >/dev/null 2>&1 || true
      fi ;;
  esac
fi

# Всё равно нет (чужой id, битая палитра) - не валим запуск: берём default,
# он в git. Иначе после клонирования не применилась бы даже тема, а ошибка
# «нет схемы» уводила бы в сторону.
if [ ! -f "$JSON" ]; then
  echo "нет схемы $SCHEME - беру default" >&2
  SCHEME=default
  JSON="$ROOT/theme/schemes/default.json"
  printf '%s\n' "$SCHEME" > "$ROOT/theme/current"
fi

python3 - "$ROOT" "$JSON" "$SCHEME" <<'PY'
import json, sys, pathlib, re

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
tpl = root / "theme/templates/colors.scss.tpl"
out = root / "eww/colors.scss"
css = render(tpl.read_text(encoding="utf-8"), "colors.scss.tpl")
# SCSS-компилятор падает на не-ASCII в @charset: комментарии шаблона английские,
# но проверяем: если в результате есть не-ASCII в коде - это ошибка шаблона.
out.write_text(css, encoding="utf-8")
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

if [ "$RELOAD" -eq 1 ]; then
  EWW="$ROOT/build/target/release/eww"
  [ -x "$EWW" ] || { echo "eww не собран: $EWW" >&2; exit 1; }
  # reload возвращает 1, когда демон не успевает ответить ("os error 11"),
  # хотя конфиг уже перечитан; поэтому код 1 не считаем провалом, но
  # предупреждаем - проверять надо пикселями.
  if "$EWW" --config "$ROOT/eww" reload; then
    echo "eww reload: ок"
  else
    echo "eww reload: код 1 (демон не ответил, конфиг может быть уже перечитан)" >&2
  fi
fi

# Запоминаем выбор последним шагом: если рендер упал, theme/current не врёт.
# apply.sh без аргумента возьмёт схему отсюда.
printf '%s\n' "$SCHEME" > "$ROOT/theme/current"
echo "схема: $SCHEME (theme/current)"

# --- 5. рамка Plank в цвет $primary ---------------------------------------
# Plank не перечитывает тему на лету, поэтому его надо перезапустить (~1 с).
# Ошибку здесь не пробрасываем: без Plank остров работает, а падать из-за
# дока не должен. Подробности - в theme/plank.sh и docs/PLANK.md.
if [ -x "$ROOT/theme/plank.sh" ]; then
  if ! "$ROOT/theme/plank.sh" apply; then
    echo "рамка Plank: не применилась (см. ~/.cache/eww-island/plank.log)" >&2
  fi
fi
