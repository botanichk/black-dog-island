#!/bin/sh
# accents.sh - образцы акцентов действующей палитры для вкладки «Цвета».
#
# usage: ~/.config/bdi/accents.sh
#
# Печатает строку JSON с ПЛОСКИМИ полями, без массивов:
#   {"id":"p-noctalia","n":2,"active":"primary",
#    "r1":"primary","h1":"#fff59b","r2":"secondary","h2":"#a9aefe",
#    "r3":"","h3":"#00000000"}
#
# Почему плоско: (for p in {...}) в Eww раскрывается в массив значений
# (build_widget.rs, build_loop_special_widget -> as_array), а вложенный
# доступ вида p[0] в выражениях не читается - ряд акцентов рисовался
# пустым, ни одного пикселя цвета акцента на вкладке не было. Три
# фиксированных слота проще и предсказуемее: пустой слот - прозрачный.
#
# n      - сколько акцентов реально предлагать (без дублей и серых, см.
#          palette_lib.accents_for). n < 2 - выбирать не из чего, ряд не
#          рисуется;
# active - какой акцент сейчас действует. Если выбранный в ~/.config/bdi/accent у
#          палитры отсутствует, действует primary (так же считает
#          build_scheme), поэтому «активным» показываем реально применённый.
#
# У схем «С обоев» акценты приходят из M3 (secondary/tertiary там часто серые),
# поэтому фильтр тот же, что у палитр.
#
# Зависимости только из системы: sh, python3. Ничего не ставим.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BDI_CONFIG="${BDI_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/bdi}"
BDI_STATE="${BDI_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/bdi}"
mkdir -p "$BDI_CONFIG" "$BDI_STATE/schemes" 2>/dev/null || true

exec python3 - "$ROOT" "$BDI_CONFIG" "$BDI_STATE" <<'PY'
import json
import os
import pathlib
import sys

sys.path.insert(0, os.path.join(sys.argv[1], "theme"))
import palette_lib as lib

root = pathlib.Path(sys.argv[1])
theme = root / "theme"
cfg = pathlib.Path(sys.argv[2])
state = pathlib.Path(sys.argv[3])


def read_trim(name, default=""):
    try:
        return (cfg / name).read_text(encoding="utf-8").strip() or default
    except OSError:
        return default


def filter_accents(pairs):
    """Пары (роль, цвет) -> образцы без дублей и серых."""
    out = []
    seen = set()
    for role, value in pairs:
        if not value:
            continue
        norm = value.lower()
        if norm in seen:
            continue
        if lib.rgb_to_hsl(value)[1] < 0.12:
            continue
        seen.add(norm)
        out.append({"role": role, "hex": value})
    return out


mode = read_trim("mode", "dark")
if mode not in ("dark", "light"):
    mode = "dark"
current = read_trim("current", "default")
accent = read_trim("accent", "primary")
if accent not in ("primary", "secondary", "tertiary"):
    accent = "primary"

scheme_id = current
items = []

if current in ("default", "light"):
    # Наша схема: акцент один, secondary/tertiary в ней не хранятся.
    scheme_id = "n-island"
    name = "light.json" if (current == "light" or mode == "light") else "default.json"
    path = theme / "schemes" / name
    if path.exists():
        try:
            colors = json.loads(path.read_text(encoding="utf-8"))["colors"]
            items = [{"role": "primary", "hex": colors["primary"]}]
        except (OSError, KeyError, json.JSONDecodeError):
            items = []
elif current == "wallpaper":
    # У M3-схемы роли уже готовые цвета: берём их как посчитал noctalia и
    # пропускаем через тот же фильтр дублей/серых.
    path = state / "schemes" / "wallpaper.json"
    if path.exists():
        try:
            colors = json.loads(path.read_text(encoding="utf-8"))["colors"]
        except (OSError, KeyError, json.JSONDecodeError):
            colors = {}
        items = filter_accents([
            ("primary", colors.get("accent_primary")),
            ("secondary", colors.get("accent_secondary")),
            ("tertiary", colors.get("accent_tertiary")),
        ])
else:
    palette = None
    if current.startswith("p-"):
        path = theme / "palettes" / (current[2:] + ".json")
        if path.exists():
            try:
                palette = lib.read_palette(path)
            except ValueError as exc:
                print("пропуск палитры: %s" % exc, file=sys.stderr)
    elif current.startswith("c-"):
        # каталог сообщества: id строит та же read_community, что и список
        palette = next((p for cid, p, _f in lib.read_community()
                        if cid == current), None)
    else:
        user_dir = pathlib.Path(os.path.expanduser("~/.config/noctalia/palettes"))
        if user_dir.is_dir():
            for path in sorted(user_dir.glob("*.json")):
                if "u-" + lib.slug_unique(path.stem) != current:
                    continue
                try:
                    palette = lib.read_palette(path)
                except ValueError as exc:
                    print("пропуск своей палитры: %s" % exc, file=sys.stderr)
                break
    if palette:
        items = filter_accents(lib.accents_for(palette, mode))

roles = [item["role"] for item in items]
active = accent if accent in roles else (roles[0] if roles else "primary")
if len(items) < 2:
    items = []

out = {"id": scheme_id, "n": len(items), "active": active}
for i in range(3):
    role, hexv = (items[i]["role"], items[i]["hex"]) if i < len(items) else ("", "#00000000")
    out["r%d" % (i + 1)] = role
    out["h%d" % (i + 1)] = hexv

print(json.dumps(out, ensure_ascii=False, separators=(",", ":")))
PY
