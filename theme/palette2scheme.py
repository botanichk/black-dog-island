#!/usr/bin/env python3
"""palette2scheme.py - палитра -> схема в формате theme/schemes/*.json.

usage:
    palette2scheme.py <палитра.json> --mode dark|light [--out <файл>]
    palette2scheme.py <палитра.json> --list
    palette2scheme.py --theme-json <json от `noctalia theme`> --mode dark --out ...

Печатает схему на stdout (или пишет в --out). Роли палитры переводятся в наши
имена, отсутствующие роли выводятся по формулам Noctalia
(src/theme/fixed_palette.cpp тега v5.4.1), контраст акцента доводится до 4.5
спуском по светлоте. Подробности - theme/palette_lib.py.

Зависимости только из системы: python3. Ничего не ставим.
"""

import argparse
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import palette_lib as lib  # noqa: E402

THEME_DIR = pathlib.Path(__file__).resolve().parent


def main(argv):
    ap = argparse.ArgumentParser(add_help=True, description=__doc__.splitlines()[0])
    ap.add_argument("palette", nargs="?", help="файл палитры (наш формат или Noctalia)")
    ap.add_argument("--theme-json",
                    help="JSON от `noctalia theme --both` (ветки dark/light)")
    ap.add_argument("--mode", choices=("dark", "light"), default="dark")
    ap.add_argument("--out", help="куда писать схему (иначе stdout)")
    ap.add_argument("--list", action="store_true",
                    help="перечислить палитры theme/palettes и выйти")
    args = ap.parse_args(argv)

    if args.list:
        for path in sorted((THEME_DIR / "palettes").glob("*.json")):
            try:
                pal = lib.read_palette(path)
                print("%s\t%s" % (path.stem, pal["label"]))
            except ValueError as exc:
                print("пропуск: %s" % exc, file=sys.stderr)
        return 0

    if args.theme_json:
        # ветки dark/light от Noctalia: ключи новые (snake_case), роли другие.
        raw = json.loads(pathlib.Path(args.theme_json).read_text(encoding="utf-8"))
        branch = raw.get(args.mode) or raw.get("dark")
        if not isinstance(branch, dict):
            print("нет ветки %s в %s" % (args.mode, args.theme_json), file=sys.stderr)
            return 2
        palette = _from_theme_json(branch, args.mode)
    elif args.palette:
        try:
            palette = lib.read_palette(args.palette)
        except ValueError as exc:
            print("плохая палитра: %s" % exc, file=sys.stderr)
            return 2
    else:
        ap.print_help()
        return 2

    try:
        scheme = lib.scheme_for_mode(palette, args.mode, THEME_DIR)
    except ValueError as exc:
        print("не собралась схема: %s" % exc, file=sys.stderr)
        return 2

    text = json.dumps(scheme, indent=2, ensure_ascii=False) + "\n"
    if args.out:
        lib.write_scheme(scheme, args.out)
        print("схема: %s (%s)" % (args.out, args.mode))
    else:
        sys.stdout.write(text)
    return 0


def _from_theme_json(branch, mode):
    """74 токена от `noctalia theme` -> палитра в нашем разборе.

    У M3-схем роли называются snake_case и полнее, чем у палитры, но нам нужны
    те же 16. surface_variant -> surfaceVariant, outline -> outline.
    """
    mapping = {
        "primary": "primary", "on_primary": "onPrimary",
        "secondary": "secondary", "on_secondary": "onSecondary",
        "tertiary": "tertiary", "on_tertiary": "onTertiary",
        "error": "error", "on_error": "onError",
        "surface": "surface", "on_surface": "onSurface",
        # в M3 ветке есть и surface_variant, и surface_container_low;
        # берём surface_variant как «следующий уровень после surface»
        "surface_variant": "surfaceVariant",
        "on_surface_variant": "onSurfaceVariant",
        "outline": "outline", "shadow": "shadow",
        "hover": "hover", "on_hover": "onHover",
    }
    roles = {}
    for src, dst in mapping.items():
        value = branch.get(src)
        if isinstance(value, str) and value.startswith("#"):
            roles[dst] = lib.rgb_hex(lib.hex_rgb(value))
    if "hover" not in roles and "primary_container" in branch:
        # у M3 нет hover: ближайший смысл - primary_container
        roles["hover"] = lib.rgb_hex(lib.hex_rgb(branch["primary_container"]))
    if "onHover" not in roles and "on_primary_container" in branch:
        roles["onHover"] = lib.rgb_hex(lib.hex_rgb(branch["on_primary_container"]))
    if "shadow" not in roles:
        roles["shadow"] = roles.get("surface", "#000000")
    return {"name": "wallpaper-%s" % mode, "label": "С обоев",
            "roles": {mode: roles}}


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
