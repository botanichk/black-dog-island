#!/bin/sh
# colors-list.sh - список палитр для вкладки «Цвета» хабa.
#
# usage: theme/colors-list.sh
#
# Печатает JSON для вкладки «Цвета». Цвета уже подобраны под режим из
# ~/.config/bdi/mode: превью показывает ОДИН вариант палитры, тот, что сейчас выбран
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
#   u-<слаг>          - ~/.config/bdi/palettes/*.json (свои палитры, старый
#                        каталог noctalia/palettes тоже читается);
#   c-<слаг>          - ~/.local/state/noctalia/community-palettes/*.json
#                       (каталог сообщества, 41 палитра). В репозиторий не
#                       копируется: список строится из каталога при каждом
#                       запуске. Каталога нет - раздела нет, вкладка цела.
#
# Список должен быть устойчив: один битый файл пропускается с сообщением в
# stderr, остальные остаются. Иначе кривая палитра убила бы всю вкладку.
#
# Зависимости только из системы: sh, python3. Ничего не ставим.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BDI_CONFIG="${BDI_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/bdi}"

exec python3 - "$ROOT" "$BDI_CONFIG" <<'PY'
import json
import os
import pathlib
import sys

sys.path.insert(0, os.path.join(sys.argv[1], "theme"))
import palette_lib as lib

root = pathlib.Path(sys.argv[1])
theme = root / "theme"
cfg = pathlib.Path(sys.argv[2])

mode = "dark"
try:
    mode = (cfg / "mode").read_text(encoding="utf-8").strip() or "dark"
except OSError:
    pass
if mode not in ("dark", "light"):
    mode = "dark"

try:
    current = (cfg / "current").read_text(encoding="utf-8").strip() or "default"
except OSError:
    current = "default"

# Выбранный акцент (~/.config/bdi/accent, вне git). Пусто = primary, как до шага 1:
# без выбора внешний вид не меняется.
try:
    accent = (cfg / "accent").read_text(encoding="utf-8").strip() or "primary"
except OSError:
    accent = "primary"
if accent not in ("primary", "secondary", "tertiary"):
    accent = "primary"

# Фильтр оттенка для каталога сообщества. Состояние в ~/.config/bdi/hue-filter
# (вне git): all / green / blue / warm / gray. Нет файла - all.
try:
    hue = (cfg / "hue-filter").read_text(encoding="utf-8").strip() or "all"
except OSError:
    hue = "all"
if hue not in ("all", "green", "blue", "warm", "gray"):
    hue = "all"

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

# --- 3. свои палитры (~/.config/bdi/palettes, плюс старый каталог Noctalia) ---
for _id, pal, path in lib.read_user():
    name = path.stem.replace("%20", " ")
    label = name.replace("_", " ").strip()
    try:
        scheme = lib.scheme_for_mode(pal, mode, theme, accent=accent)
    except ValueError as exc:
        print("пропуск своей палитры: %s" % exc, file=sys.stderr)
        continue
    c = scheme["colors"]
    add({"id": _id, "label": pal["label"] if pal.get("label") != name else label,
         "c1": c["surface"], "c2": c["surface_container"], "c3": c["primary"],
         "acc": [[r, v] for r, v in lib.accents_for(pal, mode)]})


# --- 4. каталог сообщества (c-*) -----------------------------------------
# Палитры сообщества лежат отдельно от своих и от встроенных. Читаем общим
# кодом (lib.read_community): формат тот же, конвертер не дублируем.
for cid, pal, _path in lib.read_community():
    try:
        scheme = lib.scheme_for_mode(pal, mode, theme, accent=accent)
    except ValueError as exc:
        print("пропуск палитры сообщества: %s" % exc, file=sys.stderr)
        continue
    c = scheme["colors"]
    add({"id": cid, "label": pal["label"],
         "c1": c["surface"], "c2": c["surface_container"], "c3": c["primary"],
         "acc": [[r, v] for r, v in lib.accents_for(pal, mode)],
         # фильтр по оттенку: green / blue / warm / gray (palette_lib.hue_bucket)
         "hue": lib.palette_hue(pal, mode)})


def chunk(seq, size):
    return [seq[i:i + size] for i in range(0, len(seq), size)]


# наша схема всегда первая и одна: у неё отдельный ряд, чтобы не ломать сетку
head = items[:1]
rest = items[1:]
user = [x for x in rest if x["id"].startswith("u-")]
community = [x for x in rest if x["id"].startswith("c-")]
community_all = len(community)
# «Зелёные» первыми: в списке фильтров это первый чип, а внутри категории
# порядок алфавитный - он уже такой после sorted() при чтении каталога.
if hue != "all":
    community = [x for x in community if x.get("hue") == hue]
builtin = [x for x in rest
           if not x["id"].startswith(("u-", "c-"))]

out = {"builtin": chunk(builtin, 3), "user": chunk(user, 2)}
# Раздел сообщества показываем только когда каталог реально есть: пустой
# ряд из ничего не отличить от сломанного.
# Раздел показываем, если каталог есть - даже когда фильтр отсёк всё:
# иначе человек не поймёт, куда делись палитры.
if community_all:
    out["community"] = chunk(community, 3)
    out["community_n"] = len(community)
    out["community_all"] = community_all
    out["hue"] = hue
if head:
    out["native"] = head[0]
# JSON в одну строку: Eww читает его целиком, переносы ему не нужны.
sys.stdout.write(json.dumps(out, ensure_ascii=False, separators=(",", ":")) + "\n")
PY
