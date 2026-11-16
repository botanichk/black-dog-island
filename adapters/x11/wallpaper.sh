#!/bin/sh
# Кнопка обоев на острове (этап 6, шаг 4).
# Открывает настройщик обоев XFCE. Пакеты не нужны: xfdesktop рисует рабочий
# стол и читает настройки из xfconf, а xfdesktop-settings - его родной GUI.
#
# Если окно настройщика уже открыто - не плодим копию, а поднимаем его.
# Вызов отвязанный (setsid -f) - окно должно пережить таймаут команды кнопки.
set -eu

CLASS="xfdesktop-settings.Xfdesktop-settings"
BIN="xfdesktop-settings"

command -v "$BIN" >/dev/null 2>&1 || {
  echo "ошибка: $BIN не найден" >&2
  exit 1
}

# Окно уже открыто: поднять и выйти.
if wmctrl -lx 2>/dev/null | grep -q " $CLASS "; then
  id=$(wmctrl -lx 2>/dev/null | awk -v c="$CLASS" '$3 == c {print $1; exit}')
  [ -n "$id" ] && wmctrl -i -a "$id" 2>/dev/null || true
  exit 0
fi

setsid -f "$BIN" >/dev/null 2>&1

# Ждём появления окна (до 2 с): так повторный клик сразу поднимет его,
# а не запустит второй процесс.
i=0
while [ "$i" -lt 20 ]; do
  wmctrl -lx 2>/dev/null | grep -q " $CLASS " && exit 0
  sleep 0.1
  i=$((i + 1))
done

echo "предупреждение: окно $CLASS не появилось за 2 с" >&2
exit 0
