#!/bin/sh
# colors-list.sh - список палитр для вкладки «Цвета» хабa.
#
# usage: theme/colors-list.sh
#
# Печатает JSON для вкладки «Цвета». Цвета уже подобраны под режим из
# theme/mode: превью показывает ОДИН вариант палитры, тот, что сейчас выбран
# (тёмный или светлый), а не оба сразу.
#
#   {"builtin": [[карточка, карточка, карточка], [...]],
#    "user":    [[карточка, карточка], ...]}
#
#   карточка: {"id":"p-noctalia","label":"Noctalia","c1":"#070722",
#              "c2":"#11112d","c3":"#fff59b","cur":1}
#
#   id  - значение для theme/colors-pick.sh palette <id>;
#   c1  - surface, c2 - surface_container (второй уровень), c3 - primary
#         (после подгонки контраста, то есть ровно тот, что попадёт в интерфейс);
#   cur - 1 у действующей схемы.
#
# Строки нарезаны заранее: в GTK3 нет сетки, а вложенные for в yuck читать
# тяжело. Встроенные - по 3 в ряд (карточка 165 px), свои - по 2 (251 px):
# у своих имена произвольной длины, им нужно место.
#
# Источники:
#   n-island          - наши схемы default.json / light.json (вид до шага 11);
#   p-<слаг>          - theme/palettes/*.json (встроенные палитры Noctalia);
#   u-<слаг>          - ~/.config/noctalia/palettes/*.json (свои палитры).
#
# Список должен быть устойчив: один битый файл пропускается с сообщением в
# stderr, остальные остаются. Иначе кривая палитра убила бы всю вкладку.
#
# Зависимости только из системы: sh, python3. Ничего не ставим.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

exec python3 - "$ROOT" <<'PY'
import json
import os
import pathlib
import sys

sys.path.insert(0, os.path.join(sys.argv[1], "theme"))
import palette_lib as lib

root = pathlib.Path(sys.argv[1])
theme = root / "theme"

mode = "dark"
try:
    mode = (theme / "mode").read_text(encoding="utf-8").strip() or "dark"
except OSError:
    pass
if mode not in ("dark", "light"):
    mode = "dark"

try:
    current = (theme / "current").read_text(encoding="utf-8").strip() or "default"
except OSError:
    current = "default"

# Выбранный акцент (theme/accent, вне git). Пусто = primary, как до шага 1:
# без выбора внешний вид не меняется.
try:
    accent = (theme / "accent").read_text(encoding="utf-8").strip() or "primary"
except OSError:
    accent = "primary"
if accent not in ("primary", "secondary", "tertiary"):
    accent = "primary"

# Схема -> её карточка в списке. Наша схема живёт под общим id «n-island»:
# default - её тёмный вид, light - светлый, поэтому при смене режима
# подсветка остаётся на той же карточке.
NATIVE = {"default": "n-island", "light": "n-island"}
current_id = NATIVE.get(current, current)

items = []


def add(item):
    item["cur"] = 1 if item["id"] == current_id else 0
    items.append(item)


def colors_of_scheme(path):
    """c1/c2/c3 для нашей схемы: читаем готовый JSON как есть."""
    data = json.loads(path.read_text(encoding="utf-8"))
    c = data["colors"]
    return c["surface"], c["surface_container"], c["primary"]


# --- 1. наши схемы (вид до шага 11), подписи без смешения языков ---
native = theme / "schemes" / ("light.json" if mode == "light" else "default.json")
if native.exists():
    c1, c2, c3 = colors_of_scheme(native)
    # У нашей схемы один акцент: secondary/tertiary в ней нет, выбирать не из чего.
    add({"id": "n-island", "label": "Остров", "c1": c1, "c2": c2, "c3": c3,
         "acc": [["primary", c3]]})

# --- 2. встроенные палитры Noctalia ---
for path in sorted((theme / "palettes").glob("*.json")):
    try:
        pal = lib.read_palette(path)
        scheme = lib.scheme_for_mode(pal, mode, theme, accent=accent)
    except ValueError as exc:
        print("пропуск палитры: %s" % exc, file=sys.stderr)
        continue
    c = scheme["colors"]
    add({"id": "p-" + path.stem, "label": pal["label"],
         "c1": c["surface"], "c2": c["surface_container"], "c3": c["primary"],
         "acc": [[r, v] for r, v in lib.accents_for(pal, mode)]})

# --- 3. свои палитры пользователя (тот же каталог и формат, что у Noctalia) ---
user_dir = pathlib.Path(os.path.expanduser("~/.config/noctalia/palettes"))
if user_dir.is_dir():
    for path in sorted(user_dir.glob("*.json")):
        try:
            pal = lib.read_palette(path)
            scheme = lib.scheme_for_mode(pal, mode, theme, accent=accent)
        except ValueError as exc:
            print("пропуск своей палитры: %s" % exc, file=sys.stderr)
            continue
        c = scheme["colors"]
        # имя файла -> подпись: %20 это пробел, подчёркивания тоже
        label = path.stem.replace("%20", " ").replace("_", " ").strip()
        add({"id": "u-" + lib.slug_unique(path.stem),
             "label": pal["label"] if pal.get("label") != path.stem else label,
             "c1": c["surface"], "c2": c["surface_container"], "c3": c["primary"],
             "acc": [[r, v] for r, v in lib.accents_for(pal, mode)]})


def chunk(seq, size):
    return [seq[i:i + size] for i in range(0, len(seq), size)]


# наша схема всегда первая и одна: у неё отдельный ряд, чтобы не ломать сетку
head = items[:1]
rest = items[1:]
user = [x for x in rest if x["id"].startswith("u-")]
builtin = [x for x in rest if not x["id"].startswith("u-")]

out = {"builtin": chunk(builtin, 3), "user": chunk(user, 2)}
if head:
    out["native"] = head[0]
# JSON в одну строку: Eww читает его целиком, переносы ему не нужны.
sys.stdout.write(json.dumps(out, ensure_ascii=False, separators=(",", ":")) + "\n")
PY
