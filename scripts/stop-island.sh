#!/bin/sh
# Остановка демона прототипа. XFCE не затрагивается.
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
"$ROOT/build/target/release/eww" --config "$ROOT/eww" kill
