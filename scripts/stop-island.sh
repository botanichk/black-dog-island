#!/bin/sh
# Остановка демона прототипа. XFCE не затрагивается.
#
# Почему не просто `eww kill`: kill идёт по сокету, а сокет зависит от того,
# каким путём передан --config. Демон, запущенный как `eww --config eww daemon`
# (относительный путь), слушает ДРУГОЙ сокет, и `eww kill` с абсолютным путём
# его не видит - он остаётся жив с окном на экране. Поэтому добиваем все
# демоны этого конфига, найденные по /proc (lib/eww-proc.sh).
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CONF="$ROOT/eww"
EWW="$ROOT/build/target/release/eww"

# Сначала автоскрытие: он вернёт остров, если держал его скрытым.
AUTOHIDE="$ROOT/adapters/x11/island-autohide.py"
[ -x "$AUTOHIDE" ] && "$AUTOHIDE" stop >/dev/null 2>&1 || true

# Штатный путь. Код не проверяем: демона могло не быть вовсе.
"$EWW" --config "$CONF" kill >/dev/null 2>&1 || true

# Хвост: демоны того же конфига, до которых kill не достал.
. "$ROOT/lib/eww-proc.sh"
_pids=$(eww_daemon_pids "$CONF" 2>/dev/null || true)
for _p in $_pids; do
  kill "$_p" 2>/dev/null || true
done

# Дать им закрыться, потом добить упрямых. Окно -1 в wmctrl пропадает не сразу.
_i=0
while [ "$_i" -lt 20 ]; do
  [ -z "$(eww_daemon_pids "$CONF" 2>/dev/null || true)" ] && break
  sleep 0.1
  _i=$((_i + 1))
done
for _p in $(eww_daemon_pids "$CONF" 2>/dev/null || true); do
  kill -9 "$_p" 2>/dev/null || true
done
