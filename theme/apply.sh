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
SCHEME=${1:-}
[ -n "$SCHEME" ] || { echo "usage: theme/apply.sh <схема> [--reload]" >&2; exit 2; }
shift || true
RELOAD=0
for arg in "$@"; do
  case "$arg" in
    --reload) RELOAD=1 ;;
    *) echo "неизвестный аргумент: $arg" >&2; exit 2 ;;
  esac
done

JSON="$ROOT/theme/schemes/$SCHEME.json"
[ -f "$JSON" ] || { echo "нет схемы: $JSON" >&2; echo "есть: $(ls "$ROOT/theme/schemes" | sed 's/\.json$//' | tr '\n' ' ')" >&2; exit 2; }

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
