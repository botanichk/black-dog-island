#!/usr/bin/env python3
"""wp-palette.py - палитра из картинки без внешних программ, кроме magick.

usage:
    wp-palette.py <картинка> [--scheme m3-tonal-spot] [--both]
    wp-palette.py <картинка> --all -o <каталог>

Печатает JSON того же вида, что `noctalia theme` (ветки dark/light, роли
snake_case), поэтому theme/palette2scheme.py --theme-json и
theme/wall-schemes.sh работают без правок.

Почему своя замена: noctalia в индексе Void нет, и на свежей машине раздел
«С обоев» молчал целиком. Нужны-то всего доминирующие цвета картинки:
остальные роли (surface_variant, outline, контраст) и так считает
palette_lib.build_scheme.

Схемы (Спокойная, Яркая, Точная...) - это профили обработки одной и той же
тройки цветов: сдвиг оттенка, множитель насыщенности, светлота фона. Так
десять образцов дают заметно разные схемы, а не десять оттенков одного цвета.

Зависимости только из системы: python3, magick (ImageMagick).
"""

import argparse
import colorsys
import json
import pathlib
import subprocess
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import palette_lib as lib  # noqa: E402

# name -> (сдвиг оттенка в градусах, множитель насыщенности, светлота фона, сдвиг светлоты акцента)
# Подобраны так, чтобы соседние схемы различались глазом: «Радужная» уводит
# оттенки в разные стороны, «Монохром» гасит цвет в серый, «Яркая» выкручивает
# насыщенность, «Мягкая»/«Тихая» наоборот.
PROFILES = {
    "m3-tonal-spot":   (0,   1.0,  0.12, 0.00),
    "m3-content":      (12,  1.15, 0.13, 0.02),
    "m3-fruit-salad":  (105, 1.35, 0.11, 0.03),
    "m3-rainbow":      (200, 1.30, 0.12, 0.05),
    "m3-monochrome":   (0,   0.0,  0.12, 0.00),
    "vibrant":         (0,   1.55, 0.10, 0.04),
    "faithful":        (0,   1.0,  0.14, 0.00),
    "soft":            (-10, 0.75, 0.16, -0.04),
    "muted":           (8,   0.45, 0.18, -0.06),
    "dysfunctional":   (-25, 2.0,  0.09, 0.08),
}
ORDER = ["m3-tonal-spot", "m3-content", "m3-fruit-salad", "m3-rainbow",
         "m3-monochrome", "vibrant", "faithful", "soft", "muted",
         "dysfunctional"]


def dominant_colors(path, count=12):
    """Доминирующие цвета картинки: [(hex, вес)].

    magick уже обязательная зависимость проекта, поэтому своего разбора PNG
    нет. Уменьшаем до 100x100 (скорость) и просим палитру: 0.2 с на обои.
    """
    try:
        out = subprocess.run(
            ["magick", str(path), "-resize", "100x100", "-colors", str(count),
             "-format", "%c", "histogram:info:-"],
            capture_output=True, text=True, timeout=30, check=False)
    except (OSError, subprocess.SubprocessError):
        return []
    if out.returncode != 0:
        return []
    colors = []
    for line in out.stdout.splitlines():
        line = line.strip()
        if "#" not in line:
            continue
        try:
            weight = int(line.split(":", 1)[0].strip())
        except ValueError:
            continue
        hexv = line.split("#", 1)[1].split()[0][:6]
        if len(hexv) != 6:
            continue
        try:
            lib.hex_rgb(hexv)
        except ValueError:
            continue
        colors.append(("#" + hexv.lower(), weight))
    return colors


def pick_accents(colors):
    """Три акцента из палитры: разные по оттенку, заметные.

    Акцент должен быть цветным (насыщенность >= 0.15), иначе на серых обоях
    primary выйдет серым и интерфейс потеряет вид. На одноцветных обоях
    (закат, вода) оттенков на три роли не набирается, поэтому недостающие
    получают сдвиг по кругу - ряд кружков должен показывать разные цвета,
    а не три копии одного.
    """
    ranked = []
    for hexv, weight in colors:
        hue, sat, light = lib.rgb_to_hsl(hexv)
        # Средние тона выигрывают: почти белый и почти чёрный не годятся
        # в акцент, даже если занимают пол-картинки.
        sane = min(max(1.0 - abs(light - 0.5) * 2, 0.0), 1.0)
        ranked.append((weight * (0.25 + sat) * (0.4 + sane), hexv, hue, sat))
    ranked.sort(reverse=True)

    colorful = [item for item in ranked if item[3] >= 0.15]
    pool = colorful or ranked
    if not pool:
        return ["#4a7ba7", "#7a5a9a", "#4f8f6a"]

    picked = []
    for _score, hexv, hue, _sat in pool:
        if all(min(abs(hue - h2), 360 - abs(hue - h2)) >= 40
               for _h, h2 in picked):
            picked.append((hexv, hue))
        if len(picked) == 3:
            break

    # Недостающие - сдвиг оттенка первого акцента: +35 и +70 градусов
    # читаются как другой цвет, но остаются в характере картинки.
    base_hex, base_hue = picked[0] if picked else (pool[0][1], pool[0][2])
    _bh, base_sat, base_light = lib.rgb_to_hsl(base_hex)
    for step in (35, 70):
        if len(picked) == 3:
            break
        use_hue = (base_hue + step) % 360
        if all(min(abs(use_hue - h2), 360 - abs(use_hue - h2)) >= 30
               for _h, h2 in picked):
            picked.append((lib.hsl_to_rgb(use_hue, max(base_sat, 0.35),
                                         base_light), use_hue))
    while len(picked) < 3:
        picked.append(picked[0])
    return [hexv for hexv, _h in picked[:3]]


def base_surface(colors):
    """Тон фона: самый частый цвет картинки, приведённый к тёмному/светлому."""
    if not colors:
        return "#141414"
    top = max(colors, key=lambda c: c[1])[0]
    return top


def tweak(hexv, hue_shift, sat_mul, light_shift=0.0):
    hue, sat, light = lib.rgb_to_hsl(hexv)
    hue = (hue + hue_shift) % 360
    sat = min(max(sat * sat_mul, 0.0), 1.0)
    light = min(max(light + light_shift, 0.0), 1.0)
    return lib.hsl_to_rgb(hue, sat, light)


def build_branch(primary, secondary, tertiary, surface_src, profile, mode):
    hue_shift, sat_mul, light_target, accent_shift = PROFILES[profile]
    dark = mode == "dark"

    primary = tweak(primary, hue_shift, sat_mul, accent_shift)
    secondary = tweak(secondary, hue_shift, max(sat_mul, 0.3), accent_shift)
    tertiary = tweak(tertiary, hue_shift, max(sat_mul, 0.3), accent_shift)

    surface = lib.shift_lightness(surface_src, 0)
    _h, _s, cur = lib.rgb_to_hsl(surface)
    surface = lib.hsl_to_rgb(_h, min(_s, 0.25), light_target)
    if not dark:
        surface = lib.hsl_to_rgb(_h, min(_s, 0.12), 1.0 - light_target + 0.06)

    on_surface = lib.best_ink(surface)
    return {
        "primary": primary,
        "on_primary": lib.best_ink(primary),
        "secondary": secondary,
        "on_secondary": lib.best_ink(secondary),
        "tertiary": tertiary,
        "on_tertiary": lib.best_ink(tertiary),
        "surface": surface,
        "on_surface": on_surface,
        "surface_variant": lib.shift_lightness(
            surface, 0.06 if dark else -0.06),
        "on_surface_variant": lib.mix(on_surface, surface, 0.35),
        "outline": lib.mix(lib.shift_lightness(surface, 0.06 if dark else -0.06),
                           on_surface, 0.25),
        "shadow": "#000000",
        "hover": lib.mix(primary, surface, 0.55),
        "on_hover": lib.best_ink(lib.mix(primary, surface, 0.55)),
    }


def build(path, profile):
    colors = dominant_colors(path)
    if not colors:
        return None
    primary, secondary, tertiary = pick_accents(colors)
    surface_src = base_surface(colors)
    return {mode: build_branch(primary, secondary, tertiary, surface_src,
                               profile, mode)
            for mode in ("dark", "light")}


def main(argv):
    ap = argparse.ArgumentParser(add_help=True,
                                 description=__doc__.splitlines()[0])
    ap.add_argument("image", help="файл картинки")
    ap.add_argument("--scheme", default="m3-tonal-spot", choices=ORDER)
    ap.add_argument("--all", action="store_true",
                    help="все десять схем, по файлу на схему в -o")
    ap.add_argument("-o", "--out", help="каталог для --all")
    args = ap.parse_args(argv)

    if not pathlib.Path(args.image).is_file():
        print("нет файла: %s" % args.image, file=sys.stderr)
        return 2

    if args.all:
        if not args.out:
            print("--all требует -o <каталог>", file=sys.stderr)
            return 2
        outdir = pathlib.Path(args.out)
        outdir.mkdir(parents=True, exist_ok=True)
        built = 0
        for name in ORDER:
            data = build(args.image, name)
            if data is None:
                continue
            (outdir / (name + ".json")).write_text(
                json.dumps(data, ensure_ascii=False), encoding="utf-8")
            built += 1
        if built == 0:
            print("не удалось прочитать картинку: %s" % args.image,
                  file=sys.stderr)
            return 1
        return 0

    data = build(args.image, args.scheme)
    if data is None:
        print("не удалось прочитать картинку: %s" % args.image,
              file=sys.stderr)
        return 1
    json.dump(data, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
