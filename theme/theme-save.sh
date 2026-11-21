#!/bin/sh
# theme-save.sh - сохранить текущий вид острова как свою тему.
#
# usage: theme/theme-save.sh "<название>"
#
# Что сохраняется: палитра (обе ветки, тёмная и светлая) в формате Noctalia,
# в ~/.config/noctalia/palettes/<название>.json. Файл сразу появляется в
# разделе «Свои» вкладки «Цвета» и применяется.
#
# Почему из ответа `noctalia theme`, а не из готовой схемы: в схеме
# (theme/schemes/wallpaper.json) уже один режим - только светлый или только
# тёмный, и переключатель «Тёмная/Светлая» у сохранённой темы пропал бы.
# В ответе noctalia обе ветки целы (проверено: перекладка в палитру и обратно
# даёт те же цвета по всем ролям).
#
# Выбранный акцент переносится в роль primary: иначе сохранённая тема
# выглядела бы иначе при другом ~/.config/bdi/accent. Так она воспроизводится ровно
# так, как её видел человек в момент сохранения.
#
# Зависимости только из системы: sh, python3, noctalia (только для обоев).
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
THEME="$ROOT/theme"
BDI_CONFIG="${BDI_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/bdi}"
# PALETTES_DIR/SAVE_SOURCE/SAVE_NO_APPLY - только для --selftest: пишем в
# временный каталог и не трогаем действующую тему.
DIR=${PALETTES_DIR:-$HOME/.config/noctalia/palettes}

NAME=${1:-}
NAME=$(printf '%s' "$NAME" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')

if [ "$NAME" = "--selftest" ]; then
  # Проверка без записи в конфиг: имена и перекладка палитры в файл и обратно.
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/eww-island-selftest.XXXXXX")
  trap 'rm -rf "$tmp"' EXIT
  "$0" "" >/dev/null 2>&1 && { echo "FAIL пустое имя принято"; exit 1; }
  "$0" "a/b" >/dev/null 2>&1 && { echo "FAIL слэш в имени принят"; exit 1; }
  SAVE_SOURCE="$THEME/palettes/nord.json" SAVE_NO_APPLY=1 PALETTES_DIR="$tmp" \
    "$0" "Тест темы" >/dev/null || { echo "FAIL сохранение палитры"; exit 1; }
  python3 - "$tmp/Тест темы.json" "$THEME/palettes/nord.json" "$THEME" <<'PY' || exit 1
import json, pathlib, sys
saved, orig, theme = sys.argv[1:4]
sys.path.insert(0, theme)
import palette_lib as lib
a, b = lib.read_palette(saved), lib.read_palette(orig)
bad = 0
for mode in ("dark", "light"):
    ra, rb = a["roles"].get(mode, {}), b["roles"].get(mode, {})
    for role in ("primary", "onPrimary", "secondary", "surface", "onSurface",
                 "surfaceVariant", "outline", "error"):
        if ra.get(role) != rb.get(role):
            print(f"FAIL {mode}.{role}: {ra.get(role)} != {rb.get(role)}")
            bad = 1
meta = json.loads(pathlib.Path(saved).read_text())["_island"]
if meta["name"] != "Тест темы":
    print("FAIL имя в _island:", meta["name"])
    bad = 1
sys.exit(bad)
PY
  echo "selftest ok"
  exit 0
fi

[ -n "$NAME" ] || { echo "нужно название темы" >&2; exit 2; }
# Косая черта и NUL сломали бы путь; остальное (пробелы, кириллица) можно.
case "$NAME" in
  */*|*\\*) echo "в названии не должно быть / или \\" >&2; exit 2 ;;
esac

CURRENT=$(tr -d ' \t\r\n' < "$BDI_CONFIG/current" 2>/dev/null || echo default)
ACCENT=$(tr -d ' \t\r\n' < "$BDI_CONFIG/accent" 2>/dev/null || true)
case "$ACCENT" in secondary|tertiary) ;; *) ACCENT=primary ;; esac
MODE=$(tr -d ' \t\r\n' < "$BDI_CONFIG/mode" 2>/dev/null || true)
case "$MODE" in light|dark) ;; *) MODE=dark ;; esac
WALL_SCHEME=$(tr -d ' \t\r\n' < "$BDI_CONFIG/wallpaper-scheme" 2>/dev/null || true)

case "$CURRENT" in
  default|light)
    # Наша схема уже и есть тема: сохранять её копию незачем.
    [ -n "${SAVE_SOURCE:-}" ] || {
      echo "«Остров» уже тема - сохранять нечего. Выберите палитру или цвета с обоев." >&2
      exit 2 ;} ;;
esac

if [ -n "${SAVE_SOURCE:-}" ]; then
  SRC=$SAVE_SOURCE
else
  case "$CURRENT" in
    wallpaper)
      [ -n "$WALL_SCHEME" ] || WALL_SCHEME=m3-tonal-spot
      mkdir -p "$DIR"
      TMP=$(mktemp "${TMPDIR:-/tmp}/eww-island-save.XXXXXX.json")
      trap 'rm -f "$TMP"' EXIT
      WALL=$("$THEME/from-wallpaper.sh" --path 2>/dev/null) || {
        echo "не нашёл обои текущего стола" >&2; exit 3; }
      if ! noctalia theme "$WALL" --scheme "$WALL_SCHEME" --both >"$TMP" 2>"$TMP.err"; then
        echo "noctalia не смогла прочитать обои: $WALL" >&2
        sed 's/^/  /' "$TMP.err" >&2 || true
        rm -f "$TMP.err"
        exit 1
      fi
      rm -f "$TMP.err"
      SRC="$TMP" ;;
    *)
      SRC=$("$THEME/colors-pick.sh" path "$CURRENT") || {
        echo "не нашёл файл палитры для '$CURRENT'" >&2; exit 3; } ;;
  esac
fi

python3 - "$SRC" "$DIR" "$NAME" "$ACCENT" "$MODE" "$WALL_SCHEME" "$THEME" <<'PY'
import importlib.util
import json
import pathlib
import sys

src, dest_dir, name, accent, mode, wall_scheme, theme = sys.argv[1:8]
theme_path = pathlib.Path(theme)

# Тот же разбор формата, что у вкладки: M3-ответ noctalia и файл палитры
# читаются одной функцией, отдельного конвертера нет.
spec = importlib.util.spec_from_file_location("p2s", theme_path / "palette2scheme.py")
p2s = importlib.util.module_from_spec(spec)
spec.loader.exec_module(p2s)
sys.path.insert(0, str(theme_path))
import palette_lib as lib  # noqa: E402

raw = json.loads(pathlib.Path(src).read_text(encoding="utf-8"))
if isinstance(raw, dict) and "dark" in raw and "primary" in raw.get("dark", {}):
    # ответ `noctalia theme --both`: роли snake_case, обе ветки.
    # read_palette здесь не подходит: он ищет onPrimary, а в ответе on_primary,
    # и роли текста пропали бы.
    palette = {"name": name, "label": name,
               "roles": {m: p2s._from_theme_json(raw[m], m)["roles"][m]
                         for m in ("dark", "light") if isinstance(raw.get(m), dict)}}
else:
    palette = lib.read_palette(src)

# Акцент -> primary: тема должна выглядеть так, как её сохранили.
promoted = {}
for m, roles in palette["roles"].items():
    branch = dict(roles)
    chosen = branch.get(accent) or branch.get("primary")
    on_chosen = branch.get("on" + accent[:1].upper() + accent[1:]) or branch.get("onPrimary")
    if chosen:
        branch["primary"] = chosen
        if on_chosen:
            branch["onPrimary"] = on_chosen
    promoted[m] = branch

# Пишем в формате Noctalia (m<Роль>), чтобы файл понимали и она, и мы.
order = ["primary", "onPrimary", "secondary", "onSecondary", "tertiary",
         "onTertiary", "error", "onError", "surface", "onSurface",
         "surfaceVariant", "onSurfaceVariant", "outline", "shadow",
         "hover", "onHover"]
out = {}
for m, branch in promoted.items():
    out[m] = {"m" + r[:1].upper() + r[1:]: branch[r] for r in order if r in branch}
# Служебные поля: по ним видно, откуда тема снята. Noctalia их игнорирует,
# наш разбор тоже (он смотрит только роли).
out["_island"] = {"accent": accent, "mode": mode, "wallpaper_scheme": wall_scheme,
                  "name": name}

dest = pathlib.Path(dest_dir) / (name + ".json")
dest.parent.mkdir(parents=True, exist_ok=True)
dest.write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
# id и подпись в списке считаются от имени файла - тот же код, что у вкладки.
print("u-" + lib.slug_unique(name))
PY

ID=$(python3 -c "import sys; sys.path.insert(0,'$THEME'); import palette_lib as p; print('u-' + p.slug_unique(sys.argv[1]))" "$NAME")

# Применяем сразу: тема должна стать действующей, а не просто лечь файлом.
# В --selftest применять нечего: каталог временный.
if [ -z "${SAVE_NO_APPLY:-}" ]; then
  # BDI_NO_DETACH: сохранение ждёт, что тема станет действующей сразу -
  # отвязка (она для кнопок хаба) вернула бы управление до применения.
  BDI_NO_DETACH=1 "$THEME/colors-pick.sh" palette "$ID" "$MODE" >/dev/null

  # Поле названия чистим: иначе следующий клик по «Сохранить» молча перезаписал
  # бы ту же тему. Формально это сброс интерфейса, поэтому ошибку не считаем.
  EWW="$ROOT/build/target/release/eww"
  [ -x "$EWW" ] && "$EWW" --config "$ROOT/eww" update theme_name="" >/dev/null 2>&1 || true
fi

echo "тема «$NAME» сохранена: $DIR/$NAME.json"
echo "id: $ID"
