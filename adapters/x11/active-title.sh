#!/bin/sh
# Печатает заголовок активного окна при каждой смене фокуса (X11, событийно).
# shortcut: заголовок перечитывается только при смене фокуса, поэтому переименованное активное окно сохранит старое имя.
xprop -spy -root _NET_ACTIVE_WINDOW 2>/dev/null | while IFS= read -r line; do
  id=$(printf '%s\n' "$line" | sed -n 's/.*# \(0x[0-9a-fA-F]*\).*/\1/p')
  if [ -z "$id" ] || [ "$id" = "0x0" ]; then
    echo ""
    continue
  fi
  t=$(xprop -id "$id" _NET_WM_NAME 2>/dev/null | sed -n 's/^_NET_WM_NAME(UTF8_STRING) = "\(.*\)"$/\1/p')
  [ -n "$t" ] || t=$(xprop -id "$id" WM_NAME 2>/dev/null | sed -n 's/^WM_NAME(STRING) = "\(.*\)"$/\1/p')
  # Обрезку и многоточие делает GTK (свойства :limit-width/:truncate у label).
  echo "${t:-}"
done
