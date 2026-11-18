#!/bin/sh
# wall-schemes.sh - образцы M3-схем для обоев текущего стола.
#
# usage: theme/wall-schemes.sh
#
# Печатает JSON для вкладки «Цвета»: ряд образцов под блоком «С обоев».
# У каждой из десяти схем образец - цвет, который станет primary острова,
# если по ней кликнуть (с учётом theme/accent и подгонки контраста).
#
# Расчёт один раз на картинку: `noctalia theme` вызывается десять раз (по
# одному на схему), это ~1.3 с, поэтому результат кладётся в кэш по хэшу
# файла обоев: ~/.cache/eww-island/wall-schemes/<sha1>.v2.json. Повторный
# опрос (раз в 15 с) читает файл и стоит миллисекунды.
#
# Почему кэш по содержимому, а не по пути: владелец может перерисовать обои
# под тем же именем, и старые образцы тогда врали бы.
#
# Схемы берутся из списка самого noctalia (см. from-wallpaper.sh): других
# значений он не принимает. Если обоев нет или noctalia упала - печатается
# n=0, и ряд не рисуется: вкладка при этом цела.
#
# Зависимости только из системы: sh, python3, noctalia, sha1sum, xfconf-query.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/eww-island/wall-schemes"

# Порядок и подписи. Подписи короткие: они уходят в tooltip образца.
SCHEMES='m3-tonal-spot|Спокойная
m3-content|По картинке
m3-fruit-salad|Пёстрая
m3-rainbow|Радужная
m3-monochrome|Монохром
vibrant|Яркая
faithful|Точная
soft|Мягкая
muted|Тихая
dysfunctional|Резкая'

empty() {
  printf '%s\n' '{"id":"","n":0,"active":"m3-tonal-spot","active_label":"Спокойная"}'
  exit 0
}

# --- 1. обои, которые реально на экране -----------------------------------
# Тот же отбор, что и при сборке схемы (single-workspace-mode и т.д.):
# --path отдаёт путь, найденный тем же кодом, поэтому второй копии нет.
WALL=$("$ROOT/theme/from-wallpaper.sh" --path 2>/dev/null) || empty
[ -n "$WALL" ] && [ -f "$WALL" ] || empty

ROOT_HASH=$(sha1sum -- "$WALL" 2>/dev/null | cut -d' ' -f1)
[ -n "$ROOT_HASH" ] || empty

MODE=$(tr -d ' \t\r\n' < "$ROOT/theme/mode" 2>/dev/null || true)
case "$MODE" in light|dark) ;; *) MODE=dark ;; esac

WALL_SCHEME=$(tr -d ' \t\r\n' < "$ROOT/theme/wallpaper-scheme" 2>/dev/null || true)
[ -n "$WALL_SCHEME" ] || WALL_SCHEME=m3-tonal-spot
CURRENT=$(tr -d ' \t\r\n' < "$ROOT/theme/current" 2>/dev/null || true)

# --- 2. кэш ---------------------------------------------------------------
# Формат кэша в имени: в v1 лежал только primary, а образец обязан совпадать
# с тем, что реально применится (с учётом theme/accent - их три, плюс
# подгонка контраста к surface). Старый файл тогда просто не найдётся и
# пересоберётся сам.
mkdir -p "$CACHE" 2>/dev/null || empty
FILE="$CACHE/$ROOT_HASH.v2.json"

# Кэш валиден, если в нём есть все десять схем. Иначе (старый неполный
# файл, оборванная запись) считаем заново.
need_build=1
if [ -s "$FILE" ]; then
  if python3 - "$FILE" <<'PY' >/dev/null 2>&1
import json, sys
want = {"m3-tonal-spot", "m3-content", "m3-fruit-salad", "m3-rainbow",
        "m3-monochrome", "vibrant", "faithful", "soft", "muted",
        "dysfunctional"}
data = json.load(open(sys.argv[1], encoding="utf-8"))
sys.exit(0 if want <= set(data) else 1)
PY
  then need_build=0; fi
fi

if [ "$need_build" -eq 1 ]; then
  TMP="$FILE.tmp$$"
  trap 'rm -f "$TMP" "$TMP".part.*' EXIT
  # Каталог может оказаться недоступным для записи (чужой ~/.cache, полный
  # диск): тогда честно отдаём n=0, а не падаем с кодом 1 - вкладка должна
  # остаться целой. touch, а не `: >` - ошибка перенаправления у специальной
  # встроенной команды завершает весь скрипт до проверки.
  if ! touch "$TMP" 2>/dev/null; then empty; fi
  # Отдельный файл на схему: вывод noctalia многострочный (pretty JSON),
  # склеить десять ответов в один поток и разобрать по строкам нельзя -
  # первая попытка сохранила пустой кэш именно так.
  printf '%s\n' "$SCHEMES" | while IFS='|' read -r key label; do
    [ -n "$key" ] || continue
    # одна схема за вызов: --both отдаёт обе ветки, кэшу нужны обе - режим
    # переключается кнопкой в шапке, и образцы должны следовать за ним.
    noctalia theme "$WALL" --scheme "$key" --both -o "$TMP.part.$key" >/dev/null 2>&1 \
      || : > "$TMP.part.$key"
  done
  # сборка: десять файлов -> один объект {схема: {dark: {роли+surface}, ...}}
  python3 - "$TMP" "$TMP.build" <<'PY'
import json, sys
keys = ["m3-tonal-spot", "m3-content", "m3-fruit-salad", "m3-rainbow",
        "m3-monochrome", "vibrant", "faithful", "soft", "muted",
        "dysfunctional"]
prefix = sys.argv[1]
result = {}
for key in keys:
    try:
        branch = json.load(open(prefix + ".part." + key, encoding="utf-8"))
    except (OSError, ValueError):
        continue
    modes = {}
    for mode in ("dark", "light"):
        tokens = branch.get(mode) or {}
        roles = {}
        for role in ("primary", "secondary", "tertiary", "on_primary",
                     "on_secondary", "on_tertiary", "surface"):
            value = tokens.get(role)
            if isinstance(value, str) and value.startswith("#"):
                roles[role] = value
        if roles.get("surface") and roles.get("primary"):
            modes[mode] = roles
    if modes:
        result[key] = modes
json.dump(result, open(sys.argv[2], "w", encoding="utf-8"), ensure_ascii=False)
PY
  mv "$TMP.build" "$TMP"
  rm -f "$TMP".part.*
  [ -s "$TMP" ] && mv "$TMP" "$FILE"
  trap - EXIT
  rm -f "$TMP"
  # Старые картинки копятся по ~1.5 КБ: держим десять свежих, остальное
  # удаляем - кэш не должен расти бесконечно.
  ls -1t "$CACHE"/*.json 2>/dev/null | tail -n +11 | while read -r old; do
    rm -f "$old"
  done
fi

# --- 3. JSON для вкладки --------------------------------------------------
# Плоские поля k1..k10/l1..l10/c1..c10/a1..a10, а не массив: в этой сборке
# индексы и поля вложенных объектов внутри (for) не читаются - так же
# сделаны акценты (theme/accents.sh). Ряд из десяти слотов рисуется в yuck
# десятью виджетами с :visible по n.
#
# Цвет образца считается НЕ своей копией формул, а тем же кодом, что
# применяет схему: palette2scheme._from_theme_json + palette_lib.build_scheme.
# Первая версия брала tertiary как есть, и образец расходился с островом
# (у «Тихой» tertiary #626150, а применялось #756457: роль выпала из
# accents_for как дубль, и build_scheme откатился на primary, подогнанный по
# контрасту; у «Монохрома» #3b3b3b против #000000). Образец обязан совпадать
# с тем, что увидит человек после клика.
python3 - "$FILE" "$MODE" "$WALL_SCHEME" "$CURRENT" "$ROOT_HASH" "$ROOT/theme/accent" "$ROOT/theme" <<'PY'
import json, sys

sys.path.insert(0, sys.argv[7])
import palette_lib as lib
import palette2scheme

cache_path, mode, active, current, key = sys.argv[1:6]

# Акцент, который станет primary острова (theme/accent) - та же роль, что
# читает from-wallpaper.sh.
try:
    accent = open(sys.argv[6], encoding="utf-8").read().strip()
except OSError:
    accent = "primary"
if accent not in ("primary", "secondary", "tertiary"):
    accent = "primary"

try:
    data = json.load(open(cache_path, encoding="utf-8"))
except (OSError, ValueError):
    data = {}

# Порядок и подписи. Порядок фиксирован: слоты c1..c10 в yuck жёсткие.
labels = [
    ("m3-tonal-spot", "Спокойная"),
    ("m3-content", "По картинке"),
    ("m3-fruit-salad", "Пёстрая"),
    ("m3-rainbow", "Радужная"),
    ("m3-monochrome", "Монохром"),
    ("vibrant", "Яркая"),
    ("faithful", "Точная"),
    ("soft", "Мягкая"),
    ("muted", "Тихая"),
    ("dysfunctional", "Резкая"),
]


def sample_color(name):
    """primary схемы name в режиме mode - тем же кодом, что при применении."""
    modes = data.get(name) or {}
    branch = modes.get(mode) or modes.get("dark") or modes.get("light")
    if not branch:
        return None
    palette = palette2scheme._from_theme_json(branch, mode)
    # База - из theme/schemes/default.json или light.json, как в
    # scheme_for_mode: build_scheme берёт оттуда роли, которых у M3 нет
    # (цвета иллюстраций погоды), и без неё падает на weather_cloud.
    default, light = lib.load_bases(sys.argv[7])
    base = light if mode == "light" else default
    scheme, _warnings = lib.build_scheme(
        palette, mode,
        base_colors=base["colors"], base_alphas=base["alphas"],
        base_gradients=base.get("weather_gradients", {}), accent=accent)
    return scheme["colors"]["primary"]


out = {"id": key, "n": 0, "active": active,
       "active_label": dict(labels).get(active, "")}
want = active if current == "wallpaper" else ""
for idx, (name, label) in enumerate(labels, start=1):
    color = sample_color(name)
    out["k%d" % idx] = name
    out["l%d" % idx] = label
    out["c%d" % idx] = color or "#00000000"
    out["a%d" % idx] = 1 if (name == want) else 0
    if color:
        out["n"] = idx
print(json.dumps(out, ensure_ascii=False))
PY
