#!/bin/sh
# Остановка демона прототипа. XFCE не затрагивается.
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# Сначала автоскрытие: он вернёт остров, если держал его скрытым.
AUTOHIDE="$ROOT/adapters/x11/island-autohide.py"
[ -x "$AUTOHIDE" ] && "$AUTOHIDE" stop >/dev/null 2>&1 || true
"$ROOT/build/target/release/eww" --config "$ROOT/eww" kill
