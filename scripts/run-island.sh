#!/bin/sh
# Запуск прототипа Eww Island. Автозапуск не настраивается, XFCE Panel не трогаем.
#
# Поведение:
#   * если демон Eww уже работает - второй не запускаем, работаем с существующим;
#   * если демон не ответил за отведённое время - ошибка с ненулевым кодом;
#   * если окно острова не появилось или его ширину не удалось измерить - ошибка;
#   * в успешном случае код 0, независимо от того, был ли демон запущен сейчас.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
# Корень проекта для конфига: в eww.yuck он подставляется как ${BDI_ROOT}.
# EWW_CONFIG_DIR движок в defpoll/defvar не пускает ("cannot access variables
# here"), а в окружение команд не экспортирует, поэтому передаём своё.
BDI_ROOT="$ROOT"
# Состояние живёт вне репозитория: выбор темы - в ~/.config/bdi, схемы - в
# ~/.local/state/bdi, кэш - в ~/.cache/bdi. Скрипты читают эти же переменные,
# поэтому запуск руками (без run-island.sh) тоже работает.
BDI_CONFIG="${BDI_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/bdi}"
BDI_STATE="${BDI_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/bdi}"
BDI_CACHE="${BDI_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/bdi}"
export BDI_ROOT BDI_CONFIG BDI_STATE BDI_CACHE
mkdir -p "$BDI_CONFIG" "$BDI_STATE/schemes" "$BDI_CACHE" 2>/dev/null || true
EWW="$ROOT/build/target/release/eww"
CONF="$ROOT/eww"
GEOM="$ROOT/adapters/x11/island-geom.sh"

# Сколько ждём ответа демона на ping (секунды).
PING_TIMEOUT=10
# Сколько ждём появления окна острова (секунды).
OPEN_TIMEOUT=10

[ -x "$EWW" ] || { echo "eww не собран: $EWW" >&2; exit 1; }
[ -x "$GEOM" ] || { echo "нет скрипта поиска окна: $GEOM" >&2; exit 1; }

err() { echo "ошибка: $*" >&2; exit 1; }

# Старое состояние из репозитория переносим один раз (скрипт идемпотентный).
[ -x "$ROOT/scripts/migrate-state.sh" ] && "$ROOT/scripts/migrate-state.sh" >/dev/null 2>&1 || true
# colors.scss и SVG генерируются из шаблонов и в git не лежат: на свежем
# клоне их надо собрать до старта демона, иначе Eww не поднимется.
# Пустой ~/.config/bdi или битая схема не должны мешать запуску: apply.sh
# сам откатывается на default, а если и он не вышел - берём цвета из
# последнего удачного рендера (colors.scss уже на диске) и стартуем.
if [ ! -f "$CONF/colors.scss" ]; then
  "$ROOT/theme/apply.sh" >/dev/null 2>&1 ||
    echo "предупреждение: не удалось сгенерировать тему, см. $BDI_CACHE/theme.log" >&2
fi
if [ ! -f "$CONF/colors.scss" ]; then
  err "нет $CONF/colors.scss и собрать не удалось (см. $BDI_CACHE/theme.log)"
fi

# --- 1. Демон: используем существующий или запускаем новый ---
# "eww daemon" при занятом сокете виснет вечно: родительский процесс ждёт ответа
# дочернего по IPC, а чужой процесс на сокете не отвечает (см. client.rs:
# do_server_call читает ответ до упора). Поэтому запускаем демон в фоне под
# timeout и проверяем готовность ping'ом, тоже под timeout.
# Проверяем: жив ли демон И пригоден ли он. Демон без BDI_ROOT бесполезен
# (пути команд в eww.yuck становятся /adapters/...), его убиваем и идём
# запускать свой - без рекурсии, одним проходом.
#
# Важно: смотрим /proc ПЕРЕД ping. Демон, поднятый с относительным --config,
# слушает другой сокет, ping его не видит, а окно на экране он держит.
_need_start=0
. "$ROOT/lib/eww-proc.sh"
_bad=""
for _p in $(eww_daemon_pids "$CONF" 2>/dev/null || true); do
  [ -n "$(eww_proc_root "$_p" 2>/dev/null || true)" ] || _bad="$_bad $_p"
done
if [ -n "$_bad" ]; then
  echo "демон без BDI_ROOT (pid$_bad): пути кнопок ведут в /adapters - перезапускаю"
  for _p in $_bad; do kill "$_p" 2>/dev/null || true; done
  sleep 0.5
  for _p in $_bad; do kill -9 "$_p" 2>/dev/null || true; done
  sleep 0.3
  _need_start=1
elif timeout 3 "$EWW" --config "$CONF" ping >/dev/null 2>&1; then
  echo "демон Eww уже работает, использую существующий"
else
  _need_start=1
fi

if [ "$_need_start" -eq 1 ]; then
  echo "запускаю демон Eww"
  # Лог Eww дописывается между запусками: в хвосте копятся строки прошлых
  # сессий ("kill command" и т.п.) и путают проверки. Чистим только при
  # старте нового демона; при живом демоне (ветка выше) логи не трогаем.
  for f in "${XDG_CACHE_HOME:-$HOME/.cache}/eww/eww_"*.log; do
    [ -f "$f" ] && : > "$f"
  done
  ( timeout 30 "$EWW" --config "$CONF" daemon >/dev/null 2>&1 || true ) &
  i=0
  while [ "$i" -lt $((PING_TIMEOUT * 10)) ]; do
    if timeout 2 "$EWW" --config "$CONF" ping >/dev/null 2>&1; then
      echo "демон Eww запущен"
      break
    fi
    i=$((i + 1))
    sleep 0.1
  done
  [ "$i" -lt $((PING_TIMEOUT * 10)) ] || err "демон Eww не ответил на ping за ${PING_TIMEOUT} с (возможно, сокет занят другим процессом)"
fi

# --- 2. Окно острова: если прошлый запуск оставил его скрытым, вернуть ---
AUTOHIDE="$ROOT/adapters/x11/island-autohide.py"
if [ -x "$AUTOHIDE" ]; then
  "$AUTOHIDE" restore >/dev/null 2>&1 || true
fi

if ! "$GEOM" xid >/dev/null 2>&1; then
  echo "окна острова нет, открываю"
  # Позицию задаём сразу при открытии: открыть в 0x0 и потом перенести - это
  # кадр, в котором остров виден слева, а потом прыжок в центр. Ширину берём
  # из того же кэша, что и автоскрытие (файл island-width), чтобы оба пути
  # открывали окно одинаково; нет кэша - открываем в 0x0 и центрируем ниже.
  WIDTHFILE="$BDI_CACHE/island-width"
  OPEN_X=0
  if [ -r "$WIDTHFILE" ]; then
    W=$(tr -cd '0-9' < "$WIDTHFILE")
    SW=$(xrandr --current | awk '/\*/{print $1; exit}' | cut -d x -f1)
    if [ -n "$W" ] && [ -n "$SW" ] && [ "$W" -gt 0 ] && [ "$W" -lt "$SW" ]; then
      OPEN_X=$(( (SW - W) / 2 ))
    fi
  fi
  # --no-daemonize: демон только что запущен выше; если клиент не достучался -
  # ошибка и повтор, а не второй демон со своим окном-клоном.
  # Вывод НЕ выбрасываем: при неудаче именно здесь видно причину (битый
  # конфиг, SCSS, разные ошибки), а без него остаётся «окно не появилось».
  out=$(timeout 10 "$EWW" --config "$CONF" --no-daemonize open island --pos "${OPEN_X}x0" 2>&1) || true
  [ -z "$out" ] || printf '%s\n' "$out" | sed 's/^/  eww: /'
  i=0
  until "$GEOM" xid >/dev/null 2>&1; do
    i=$((i + 1))
    [ "$i" -lt $((OPEN_TIMEOUT * 20)) ] || {
      [ -z "$out" ] || printf '%s\n' "$out" >&2
      err "окно острова не появилось за ${OPEN_TIMEOUT} с"
    }
    sleep 0.05
  done
  # Eww отдаёт размер окна по факту раскладки: первые ~200 мс он ещё "устаканивается",
  # поэтому меряем после короткой паузы, иначе ширина берётся заниженной.
  sleep 0.3
fi

# --- 3. Геометрия острова ---
geom=$("$GEOM" 2>/dev/null || true)
[ -n "$geom" ] || err "не удалось определить положение и размеры окна острова"

xid=$(echo "$geom" | awk '{print $1}')
ix=$(echo "$geom" | awk '{print $2}')
iy=$(echo "$geom" | awk '{print $3}')
iw=$(echo "$geom" | awk '{print $4}')
ih=$(echo "$geom" | awk '{print $5}')
[ "$iw" -gt 0 ] || err "не удалось измерить ширину окна острова"

# Ширина нужна автоскрытию, чтобы открывать остров сразу по центру, а не
# открывать в 0x0 и переносить (это видимый прыжок слева). Ширина острова от
# содержимого не зависит, поэтому кэш безопасен; оба пути пишут один файл.
WIDTHFILE="$BDI_CACHE/island-width"
mkdir -p "$(dirname "$WIDTHFILE")" 2>/dev/null || true
printf '%s\n' "$iw" > "$WIDTHFILE" 2>/dev/null || true

# --- 4. Центрирование относительно монитора острова ---
# Монитор определяем по координатам окна, а не по первому разрешению из xrandr:
# при нескольких мониторах первый может быть не тем, на котором открыт остров.
SCREEN_W=$(xrandr --current | awk -v x="$ix" -v y="$iy" '
  / connected/ {
    pos = $0; n = split(pos, f, "+");
    ox = f[n - 1] + 0; oy = f[n] + 0;
    # ищем разрешение этого выхода
    for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+x[0-9]+$/) { res = $i; break }
    split(res, r, "x");
    if (x >= ox && x < ox + r[1] && y >= oy && y < oy + r[2]) { print r[1]; exit }
  }')
[ -n "${SCREEN_W:-}" ] || SCREEN_W=$(xrandr --current | awk '/\*/{print $1; exit}' | cut -d x -f1)
[ -n "${SCREEN_W:-}" ] || err "не удалось определить ширину монитора острова"

want_x=$(( (SCREEN_W - iw) / 2 ))
[ "$want_x" -lt 0 ] && want_x=0

# Остров - dock-окно: xfwm4 игнорирует его перемещение через wmctrl,
# поэтому позицию задаём при открытии. Проверяем, что он действительно по центру.
if [ "$ix" -ne "$want_x" ] || [ "$iy" -ne 0 ]; then
  echo "остров смещён (сейчас ${ix},${iy}, нужно ${want_x},0) - центрирую"
  timeout 10 "$EWW" --config "$CONF" --no-daemonize open island --pos "${want_x}x0" >/dev/null 2>&1 || true
  sleep 0.3
  geom=$("$GEOM" 2>/dev/null || true)
  ix=$(echo "$geom" | awk '{print $2}')
  iy=$(echo "$geom" | awk '{print $3}')
  [ "$ix" -eq "$want_x" ] || err "не удалось отцентрировать остров (стал ${ix}, ожидалось ${want_x})"
fi

echo "остров готов: x=${ix} y=${iy} w=${iw} h=${ih} (монитор ${SCREEN_W} px)"

# --- 5. Автоскрытие: прячет остров, когда активное окно его перекрывает ---
if [ -x "$AUTOHIDE" ]; then
  if "$AUTOHIDE" start >/dev/null 2>&1; then
    echo "автоскрытие: включено (island-autohide.py)"
  else
    echo "предупреждение: автоскрытие не запустилось" >&2
  fi
fi
