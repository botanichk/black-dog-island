#!/usr/bin/env python3
"""palette_lib.py - общая библиотека палитр: разбор, HSL, контраст, сборка схемы.

Одна логика для трёх мест, чтобы они не разъехались:
  palette2scheme.py  - палитра -> схема нашего формата (theme/schemes/*.json);
  colors-list.sh     - данные для вкладки «Цвета» (JSON для yuck);
  from-wallpaper.sh  - палитра из обоев через wp-palette.py (magick).

Формат палитры понимаем двух видов:
  1) наш файл theme/palettes/<слаг>.json:
         {"name":..., "label":..., "roles": {"dark": {...}, "light": {...}}}
  2) файл Noctalia (~/.config/noctalia/palettes/<Имя>.json):
         {"dark": {"mPrimary": "#...", ...}, "light": {...}}
     Ключи с префиксом "m" и без равнозначны: Noctalia сначала ищет mPrimary,
     потом primary (theme_service.cpp, readColorField). Ветки light может не быть -
     тогда для обоих режимов берётся dark (там же).

Зависимости только из системы: python3. Ничего не ставим.
"""

import hashlib
import json
import os
import pathlib
import re
import sys
import urllib.parse

# --- роли Noctalia (v5.4.1), 16 штук, в порядке файла ---------------------
NOTCALIA_ROLES = [
    "primary", "onPrimary", "secondary", "onSecondary", "tertiary", "onTertiary",
    "error", "onError", "surface", "onSurface", "surfaceVariant",
    "onSurfaceVariant", "outline", "shadow", "hover", "onHover",
]

MODES = ("dark", "light")


# --- цвет -----------------------------------------------------------------

def hex_rgb(value):
    """'#rrggbb' (или '#rgb') -> (r, g, b). Ошибка, если не похоже на цвет."""
    s = str(value).strip().lstrip("#")
    if len(s) == 3:
        s = "".join(ch * 2 for ch in s)
    if len(s) != 6 or not re.fullmatch(r"[0-9a-fA-F]{6}", s):
        raise ValueError("не цвет: %r" % (value,))
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


def rgb_hex(rgb):
    return "#%02x%02x%02x" % tuple(max(0, min(255, int(round(v)))) for v in rgb)


def _linear(channel):
    c = channel / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def luminance(value):
    """Относительная яркость WCAG."""
    r, g, b = hex_rgb(value)
    return 0.2126 * _linear(r) + 0.7152 * _linear(g) + 0.0722 * _linear(b)


def contrast(a, b):
    """Контраст WCAG двух цветов: от 1.0 (одинаковые) до 21.0."""
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def mix(a, b, t):
    """Линейное смешение a -> b на долю t (0..1), как interpolateColor у Noctalia."""
    ra, rb = hex_rgb(a), hex_rgb(b)
    return rgb_hex([ra[i] + (rb[i] - ra[i]) * t for i in range(3)])


# --- HSL (нужен «спуск по светлоте», а не смешение) -----------------------

def rgb_to_hsl(value):
    r, g, b = (v / 255.0 for v in hex_rgb(value))
    mx, mn = max(r, g, b), min(r, g, b)
    light = (mx + mn) / 2
    if mx == mn:
        return 0.0, 0.0, light
    d = mx - mn
    sat = d / (2 - mx - mn) if light > 0.5 else d / (mx + mn)
    if mx == r:
        hue = ((g - b) / d) % 6
    elif mx == g:
        hue = (b - r) / d + 2
    else:
        hue = (r - g) / d + 4
    return hue * 60, sat, light


def hsl_to_rgb(hue, sat, light):
    h = (hue % 360) / 60
    c = (1 - abs(2 * light - 1)) * sat
    x = c * (1 - abs(h % 2 - 1))
    m = light - c / 2
    i = int(h) % 6
    r, g, b = [(c, x, 0), (x, c, 0), (0, c, x),
               (0, x, c), (x, 0, c), (c, 0, x)][i]
    return rgb_hex(((r + m) * 255, (g + m) * 255, (b + m) * 255))


def shift_lightness(value, delta, cap_low=None, cap_high=None):
    """Сдвинуть светлоту HSL, оттенок и насыщенность не трогая.

    Так делает Noctalia для surface_container_high/highest
    (fixed_palette.cpp:288-291): ±0.04 / ±0.08 с ограничением сверху/снизу.
    """
    hue, sat, light = rgb_to_hsl(value)
    new = light + delta
    if cap_high is not None:
        new = min(new, cap_high)
    if cap_low is not None:
        new = max(new, cap_low)
    return hsl_to_rgb(hue, sat, new)


def ensure_contrast(fg, bg, target=4.5):
    """Довести контраст fg к bg до target, двигая ТОЛЬКО светлоту fg.

    Почему не смешением с on_surface: смешение тянет цвет к серому и убивает
    оттенок (Ayu light #FF8F40 -> #996846, серо-коричневый). Спуск по светлоте
    оттенок и насыщенность сохраняет (#bf4f00, оранжевый остаётся оранжевым).

    Возвращает (цвет, сдвиг 0..1). Если не вышло - крайний чёрный/белый.
    """
    if contrast(fg, bg) >= target:
        return fg, 0.0
    hue, sat, light = rgb_to_hsl(fg)
    dark_bg = rgb_to_hsl(bg)[2] < 0.5
    sign = 1 if dark_bg else -1          # к светлому на тёмном фоне, и наоборот
    best, best_step = fg, 0.0
    for i in range(1, 201):
        step = i / 200.0
        cand = hsl_to_rgb(hue, sat, min(max(light + sign * step, 0.0), 1.0))
        ratio = contrast(cand, bg)
        if ratio > contrast(best, bg):
            best, best_step = cand, step
        if ratio >= target:
            return cand, step
    return best, best_step


def best_ink(background, candidates=("#ffffff", "#000000")):
    """Самый контрастный к фону цвет из кандидатов (для текста на плашке)."""
    return max(candidates, key=lambda c: contrast(c, background))


# --- разбор палитр --------------------------------------------------------

def _mode_map(raw, mode):
    """Ветка режима с учётом правила «нет light - берём dark»."""
    if not isinstance(raw, dict):
        return {}
    branch = raw.get(mode)
    if not isinstance(branch, dict):
        branch = raw.get("dark") if mode != "dark" else None
    return branch if isinstance(branch, dict) else {}


def _read_role(branch, role):
    """Роль из ветки: сначала mRole, потом role (как Noctalia)."""
    for key in ("m" + role[0].upper() + role[1:], role):
        value = branch.get(key)
        if isinstance(value, str) and value.startswith("#"):
            try:
                hex_rgb(value)
                return rgb_hex(hex_rgb(value))
            except ValueError:
                continue
    return None


def read_palette(path):
    """Прочитать палитру (наш формат или формат Noctalia).

    Возвращает {'name', 'label', 'roles': {'dark': {...}, 'light': {...}}}
    или бросает ValueError с понятным текстом (вызывающий её пропускает).
    """
    path = pathlib.Path(path)
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError("%s: %s" % (path.name, exc))
    if not isinstance(raw, dict):
        raise ValueError("%s: ожидался объект JSON" % path.name)

    source = raw.get("roles") if isinstance(raw.get("roles"), dict) else raw
    roles = {}
    for mode in MODES:
        branch = _mode_map(source, mode)
        got = {}
        for role in NOTCALIA_ROLES:
            value = _read_role(branch, role)
            if value is not None:
                got[role] = value
        roles[mode] = got

    if not roles["dark"] and not roles["light"]:
        raise ValueError("%s: нет ни одной роли палитры" % path.name)

    name = raw.get("name") or path.stem
    label = raw.get("label") or name
    return {"name": name, "label": label, "roles": roles}


# --- каталог своих тем -----------------------------------------------------
# Наши темы лежат в ~/.config/bdi/palettes: это НАШЕ состояние, а не чужое.
# Раньше theme-save.sh писал в ~/.config/noctalia/palettes - каталог Noctalia,
# и удаление палитры у нас стирало файл у неё. Чужой каталог теперь только
# читается (см. USER_DIR ниже), чтобы темы, сохранённые до переезда, не
# пропали из списка.
OWN_DIR = "~/.config/bdi/palettes"
USER_DIR = "~/.config/noctalia/palettes"


def own_dir():
    return pathlib.Path(os.path.expanduser(OWN_DIR))


def user_dir():
    return pathlib.Path(os.path.expanduser(USER_DIR))


def read_user() -> list:
    """Свои палитры: [(id, палитра, файл)] - сначала bdi/palettes, потом
    старый noctalia/palettes. Один слаг у двух файлов (перенесли, но старая
    копия осталась) - побеждает наш, чужой дубль пропускаем."""
    out = []
    seen = set()
    for directory in (own_dir(), user_dir()):
        if not directory.is_dir():
            continue
        for path in sorted(directory.glob("*.json")):
            name = urllib.parse.unquote(path.stem)
            slug_name = slug_unique(name)
            if slug_name in seen:
                continue
            try:
                palette = read_palette(path)
            except ValueError as exc:
                print("пропуск своей палитры: %s" % exc, file=sys.stderr)
                continue
            seen.add(slug_name)
            out.append(("u-" + slug_name, palette, path))
    return out


# --- каталог сообщества ---------------------------------------------------
# `noctalia` кладёт скачанные палитры в ~/.local/state/noctalia, а не в
# ~/.config: это состояние, а не настройки, при обновлении каталога файлы
# перезаписываются. Формат тот же, что у своих (mPrimary/...), поэтому
# читаем тем же read_palette - отдельного конвертера не нужно.
COMMUNITY_DIR = "~/.local/state/noctalia/community-palettes"


def community_dir():
    return pathlib.Path(os.path.expanduser(COMMUNITY_DIR))


def read_community(limit=None):
    """Палитры каталога сообщества: [(id, палитра, файл)].

    id - c-<слаг>. Слаг считается от имени БЕЗ %20: в каталоге имена
    закодированы («Catppuccin%20Mocha%20Green.json»), и без раскодирования
    id получился бы «catppuccin-20mocha-20green». Битый файл не роняет
    список: пропускаем и говорим в stderr.
    """
    directory = community_dir()
    if not directory.is_dir():
        return []
    out = []
    used = {}
    for path in sorted(directory.glob("*.json")):
        name = urllib.parse.unquote(path.stem)
        try:
            palette = read_palette(path)
        except ValueError as exc:
            print("пропуск палитры сообщества: %s" % exc, file=sys.stderr)
            continue
        # подпись: имя файла, а не path.stem - иначе в карточке «%20»
        palette["label"] = urllib.parse.unquote(palette["label"])
        slug_name = slug_unique(name)
        # два разных файла могут дать один слаг («Ayu Blue» и «Ayu_Blue»)
        if slug_name in used:
            used[slug_name] += 1
            slug_name = "%s-%d" % (slug_name, used[slug_name])
        else:
            used[slug_name] = 1
        out.append(("c-" + slug_name, palette, path))
        if limit is not None and len(out) >= limit:
            break
    return out


def slug(text):
    """ASCII-slug: имя схемы попадает в ~/.config/bdi/current и в комментарий
    eww/colors.scss, а тот обязан быть ASCII (иначе SCSS вставляет @charset
    и GTK выбрасывает весь stylesheet). Не-ASCII -> дефисы."""
    out = re.sub(r"[^a-z0-9]+", "-", str(text).lower()).strip("-")
    return out or "scheme"


def slug_unique(text):
    """slug + короткий хвост, если имя потеряло смысл при переводе в ASCII.

    Без хвоста «Своя тема» и «Моя тема» дают одинаковый пустой slug, а
    «тест-ADW» и «ADW» - один и тот же «adw». Тогда две разные палитры
    писали бы одну схему. Хвост считается от исходного имени, поэтому
    он стабилен между запусками (не случайный)."""
    base = slug(text)
    has_non_ascii = any(ord(ch) > 127 for ch in str(text))
    if base != "scheme" and not has_non_ascii:
        return base
    tail = hashlib.sha1(str(text).encode("utf-8")).hexdigest()[:6]
    return "%s-%s" % (base, tail) if base else tail


# --- схема нашего формата -------------------------------------------------

# --- оттенок акцента ------------------------------------------------------
# Владелец просил «зелёные» первыми. Порог 0.2 по насыщенности отделяет
# цветной акцент от серого (#c6c6c6 s=0, #ffffff s=0), тот же смысл, что
# у фильтра акцентов (0.12), только строже: при s<0.2 «зелёный» уже не
# отличить от серого.
HUE_BUCKETS = (
    ("green", 75.0, 165.0),
    ("blue", 165.0, 300.0),
    ("warm", 300.0, 435.0),      # 300..360 и 0..75 - это warm, см. hue_bucket
)


def hue_bucket(color):
    """Категория оттенка: green / blue / warm / gray.

    green - 75..165 (от салатового до мятного), blue - 165..300,
    warm - остальное цветное (300..360 и 0..75). Серое (насыщенность
    <= 0.2) в отдельную категорию: у него hue случайный.
    """
    if not color:
        return "gray"
    hue, sat, _light = rgb_to_hsl(color)
    if sat <= 0.2:
        return "gray"
    if 75.0 <= hue <= 165.0:
        return "green"
    if 165.0 < hue <= 300.0:
        return "blue"
    return "warm"


def palette_hue(palette, mode):
    """Оттенок ПАЛИТРЫ: по её акцентам, а не по одному primary.

    Владелец выбирает не только primary: у Aura зелёный - secondary, у
    Noctalia мятный - tertiary. Поэтому категория берётся по всем
    доступным акцентам, и «зелёная» палитра - та, у которой хоть один
    акцент зелёный. Порядок важности: green, blue, warm, gray.
    """
    buckets = {hue_bucket(value) for _role, value in accents_for(palette, mode)}
    for name in ("green", "blue", "warm"):
        if name in buckets:
            return name
    return "gray"


def accents_for(palette, mode):
    """Акценты палитры, которые есть смысл предлагать на выбор.

    Убираем:
      - дубли: у GitHub Dark secondary == tertiary, у Mine тоже - два
        одинаковых кружка выглядят как ошибка;
      - серые: насыщенность < 0.12 (m3-content/m3-rainbow/monochrome дают
        c6c6c6), иначе «выбор акцента» между двумя оттенками серого.
    Если после фильтра не осталось ничего, возвращаем primary: без акцента
    интерфейс существовать не может.
    """
    roles = palette["roles"][mode]
    if not roles:
        alt = "light" if mode == "dark" else "dark"
        roles = palette["roles"].get(alt) or {}
    out = []
    seen = set()
    for role in ("primary", "secondary", "tertiary"):
        value = roles.get(role)
        if not value:
            continue
        norm = value.lower()
        if norm in seen:
            continue
        if rgb_to_hsl(value)[1] < 0.12:
            continue
        seen.add(norm)
        out.append((role, value))
    if not out:
        fallback = roles.get("primary")
        if fallback:
            out = [("primary", fallback)]
    return out


def build_scheme(palette, mode, base_colors, base_alphas, base_gradients,
                 accent="primary"):
    """Палитра + режим -> схема в формате theme/schemes/*.json.

    base_colors / base_alphas / base_gradients - из theme/schemes/default.json
    и light.json: оттуда берутся роли, которых у палитры нет (цвета иллюстраций
    погоды), alpha-слои и градиенты.

    accent - какая из трёх ролей (primary/secondary/tertiary) становится
    акцентом острова. В схему попадают все три как образцы выбора, а в
    цвета - только выбранная, уже подогнанная по контрасту.
    """
    roles = palette["roles"][mode]
    if not roles:
        alt = "light" if mode == "dark" else "dark"
        roles = palette["roles"].get(alt) or {}
    if not roles:
        raise ValueError("палитра «%s»: пустой режим %s" % (palette["name"], mode))

    # Неполная палитра - обычное дело: у человека может быть только
    # primary+surface, а у Noctalia при отсутствии роли подставляется
    # прозрачный чёрный (мы так не хотим - получилось бы чёрное на чёрном).
    # Поэтому недостающее выводим и говорим об этом в stderr.
    missing = []
    surface = roles.get("surface")
    primary_raw = roles.get("primary")
    if not surface or not primary_raw:
        raise ValueError("палитра «%s»: нет %s"
                         % (palette["name"],
                            "surface" if not surface else "primary"))
    if not roles.get("surfaceVariant"):
        # следующий уровень после surface, как surface_container у Noctalia
        roles["surfaceVariant"] = shift_lightness(
            surface, 0.06 if rgb_to_hsl(surface)[2] < 0.5 else -0.06)
        missing.append("surfaceVariant")
    if not roles.get("onSurface"):
        roles["onSurface"] = best_ink(surface)
        missing.append("onSurface")
    if not roles.get("onSurfaceVariant"):
        roles["onSurfaceVariant"] = mix(roles["onSurface"], surface, 0.35)
        missing.append("onSurfaceVariant")
    if not roles.get("outline"):
        roles["outline"] = mix(roles["surfaceVariant"], roles["onSurface"], 0.25)
        missing.append("outline")
    if not roles.get("error"):
        roles["error"] = "#e5484d" if rgb_to_hsl(surface)[2] < 0.5 else "#b3261e"
        missing.append("error")
    if missing:
        print("палитра «%s»: нет ролей %s - выведены по формулам"
              % (palette["name"], ", ".join(missing)), file=sys.stderr)

    surface = roles["surface"]
    variant = roles["surfaceVariant"]

    # Три акцента палитры. Нужны все: вкладка показывает их образцами, и
    # клик по образцу меняет роль primary острова. Дубли и серые не
    # предлагаем (см. accents_for) - здесь просто переносим как есть.
    accents = {}
    for role, label in (("primary", "Основной"), ("secondary", "Второй"),
                        ("tertiary", "Третий")):
        value = roles.get(role)
        if value:
            accents[role] = value

    # Акцент проверяем тем же фильтром, что и вкладка (accents_for): если
    # выбранная роль серая или дублирует другую, предлагать её нельзя, иначе
    # схема применит цвет, которого в ряду кружков нет (проверено на ADW
    # light: secondary #2e3436 - серый, primary стал им, а ряд показывал
    # активным primary).
    allowed = [role for role, _ in accents_for(palette, mode)]
    if accent not in allowed:
        accent = allowed[0] if allowed else "primary"
    if accent not in accents:
        accent = "primary"
    chosen = accents[accent]

    # контраст акцента: 8 из 10 светлых палитр Noctalia не проходят 4.5
    primary, _ = ensure_contrast(chosen, surface, 4.5)
    on_primary = best_ink(primary)

    # primary_dim работает и как текст, и как плашка под текстом - держим оба
    primary_dim = mix(primary, surface, 0.45)
    if contrast(primary_dim, surface) < 3.0:
        primary_dim, _ = ensure_contrast(primary_dim, surface, 3.0)
    on_primary_dim = best_ink(primary_dim)
    if contrast(on_primary_dim, primary_dim) < 4.5:
        primary_dim, _ = ensure_contrast(primary_dim, best_ink(primary_dim), 4.5)
        on_primary_dim = best_ink(primary_dim)

    # error как фон под on_primary: у встроенных палитр белый даёт 2.9-4.1,
    # поэтому чернила выбираем отдельно от on_primary
    error = roles["error"]
    on_error = best_ink(error)
    if contrast(on_error, error) < 4.5:
        error, _ = ensure_contrast(error, on_error, 4.5)
        on_error = best_ink(error)

    dark = mode == "dark"
    colors = {
        "surface": surface,
        "surface_container": variant,
        "surface_high": shift_lightness(
            variant, 0.04 if dark else -0.04,
            cap_low=None if dark else 0.60,
            cap_high=0.40 if dark else None),
        "surface_highest": shift_lightness(
            variant, 0.08 if dark else -0.08,
            cap_low=None if dark else 0.55,
            cap_high=0.45 if dark else None),
        "outline": roles["outline"],
        "on_surface": roles["onSurface"],
        "on_surface_variant": roles["onSurfaceVariant"],
        "primary": primary,
        "primary_dim": primary_dim,
        "error": error,
        "on_primary": on_primary,
        "on_primary_dim": on_primary_dim,
        # Образцы акцентов палитры (до подгонки контраста - в интерфейсе они
        # только кружки выбора, текст на них не пишется). Схема-потребитель
        # может их не использовать: шаблоны берут лишь {{primary}}.
        "accent_primary": accents.get("primary", chosen),
        "accent_secondary": accents.get("secondary", chosen),
        "accent_tertiary": accents.get("tertiary", chosen),
        # текст поверх фотографий всегда светлый: картинка под ним тёмная
        "on_media": "#ffffff",
        # цвета иллюстраций погоды от палитры не зависят
        "weather_cloud": base_colors["weather_cloud"],
        "weather_snow": base_colors["weather_snow"],
    }

    scheme = {"colors": colors, "alphas": dict(base_alphas),
              "weather_gradients": dict(base_gradients)}
    return scheme, on_error


def load_bases(theme_dir):
    """База для ролей, которых нет у палитры: default.json и light.json."""
    theme_dir = pathlib.Path(theme_dir)
    default = json.loads((theme_dir / "schemes" / "default.json").read_text(encoding="utf-8"))
    light = json.loads((theme_dir / "schemes" / "light.json").read_text(encoding="utf-8"))
    return default, light


def scheme_for_mode(palette, mode, theme_dir, accent="primary"):
    """Собрать схему с правильной базой alpha/градиентов под режим."""
    default, light = load_bases(theme_dir)
    base = light if mode == "light" else default
    scheme, on_error = build_scheme(
        palette, mode,
        base_colors=base["colors"],
        base_alphas=base["alphas"],
        base_gradients=base.get("weather_gradients", {}),
        accent=accent,
    )
    scheme["_comment"] = (
        "Схема сгенерирована из палитры «%s» (%s) скриптом "
        "theme/palette2scheme.py. Не править вручную: выбор живёт в ~/.config/bdi/current."
        % (palette["name"], mode))
    scheme["name"] = "%s-%s" % (slug(palette["name"]), mode)
    return scheme


def write_scheme(scheme, path):
    path = pathlib.Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(scheme, indent=2, ensure_ascii=False) + "\n",
                    encoding="utf-8")
    return path
