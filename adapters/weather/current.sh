#!/bin/sh
# Погода из wttr.in (без ключа API). Нет сети или пустой ответ — прочерк.
set -eu

out=$(curl -s --max-time 8 "https://wttr.in/?format=%t+%C&lang=ru" | tr -s ' ' | sed 's/^ *//; s/ *$//')

if [ -n "$out" ]; then
  printf '%s\n' "$out"
else
  printf '%s\n' "—"
fi
