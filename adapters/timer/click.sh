#!/bin/sh
# Клик по кнопке таймера на острове.
# Звенит - глушим звук; иначе открываем или закрываем панель (panel.sh сам
# разбирается, открыта она или нет).
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
TIMER="$ROOT/adapters/timer/timer.sh"

if "$TIMER" status | grep -q '"state":"ring"'; then
  "$TIMER" stop-sound
else
  "$ROOT/adapters/x11/panel.sh" panel-timer
fi
