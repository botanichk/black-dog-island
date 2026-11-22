#!/bin/sh
# plank.sh - док Plank в стиль острова: заливка $surface, рамка $primary.
#
# usage: theme/plank.sh apply     # подтянуть тему (вызывается из apply.sh)
#        theme/plank.sh restore   # вернуть исходную тему Plank
#        theme/plank.sh status    # показать, что сейчас
#
# Раньше док красился одной строкой: OuterStrokeColor = $primary, а заливка
# оставалась тёмной из чужой темы (Tokyonight-Storm-B и т.п.). На светлых
# схемах острова это давало тёмное пятно под светлым островом. Теперь док -
# это остров: заливка $surface с лёгкой прозрачностью (FILL_ALPHA), рамка
# $primary, радиусы $r-surface (18 px), внутренняя обводка убрана.
#
# Форму берём у системной темы Matte, а не у той, что стояла у человека
# (Tokyonight-Storm-B и подобные копии Default). У Default поля вокруг
# значков большие (TopPadding=2.5 против 1.5, плюс IconShadowSize=1): рамка
# уезжает ниже значков и нижним краем режется краем экрана. У Matte
# HorizPadding=1, TopPadding=1.5, BottomPadding=2, IconShadowSize=0 -
# подложка облегает значки. Цвета и радиусы всё равно наши.
#
# Откуда Matte: /usr/share/plank/themes (пакет plank). Нет её - берём
# Default, он есть в любом пакете.
#
# Почему копия темы, а не правка твоей: тема Plank - это файл dock.theme из
# чужого набора, и правка в нём затрётся при любом обновлении набора.
# Поэтому рядом кладётся своя тема EwwIsland: полная копия исходной, в
# которой заменены только строки вида и заливки, перечисленные в SET_KEYS.
#
# Почему перезапуск Plank: он не перечитывает dock.theme на лету.
# Проверено: смена темы через dconf при живом процессе не меняет ни одного
# пикселя рамки, а после pkill -x plank + запуск - рамка появляется
# (оранжевая Mocha: 4183 px по контуру). Перезапуск ~1 с.
#
# Зависимости только из системы: sh, python3, dconf, pgrep, pkill.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
THEME_NAME=EwwIsland
USER_THEMES="$HOME/.local/share/plank/themes"
SYS_THEMES="/usr/share/plank/themes"
BDI_CONFIG="${BDI_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/bdi}"
STATE_DIR="$BDI_CONFIG"
BASE_FILE="$STATE_DIR/plank-base-theme"
LOG_DIR="${BDI_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/bdi}"
LOG="$LOG_DIR/plank.log"

mkdir -p "$LOG_DIR" 2>/dev/null || true
log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG" 2>/dev/null || true
}

. "$ROOT/theme/guard.sh"

dconf_key() {
  # Имя дока не хардкодим: берём первый из enabled-docks.
  # run_to обязателен: gsettings ходит через D-Bus, а на машине без живой
  # сессионной шины вызов не возвращается и вешает остров (проверено).
  _dock=$(run_to 5 gsettings get net.launchpad.plank enabled-docks 2>/dev/null \
    | sed "s/[][]//g; s/'//g; s/,.*//" | tr -d ' \t') || true
  [ -n "$_dock" ] || _dock=dock1
  printf '/net/launchpad/plank/docks/%s/theme\n' "$_dock"
}

plank_running() {
  run_to 3 pgrep -x plank >/dev/null 2>&1
}

restart_plank() {
  if plank_running; then
    run_to 3 pkill -x plank 2>/dev/null || true
    # ждём выхода, иначе новый процесс увидит старый и уйдёт
    _i=0
    while [ "$_i" -lt 30 ] && plank_running; do
      sleep 0.1
      _i=$((_i + 1))
    done
  fi
  run_to 10 setsid -f plank >/dev/null 2>&1 || {
    log "ошибка: plank не запустился"
    return 1
  }
  # ждём окно дока, чтобы следующие замеры видели уже новую тему.
  # Не дольше ~15 с: wmctrl под таймаутом, иначе мёртвый X-сервер растянул
  # бы ожидание на 40 итераций по 3 с, а смена темы обязана закончиться.
  _i=0
  while [ "$_i" -lt 15 ]; do
    if run_to 2 wmctrl -l 2>/dev/null | grep -qi plank; then
      return 0
    fi
    sleep 0.2
    _i=$((_i + 1))
  done
  return 0
}

# Каталог темы по имени: сначала пользовательские, потом системные.
theme_dir() {
  for _d in "$USER_THEMES/$1" "$SYS_THEMES/$1"; do
    if [ -f "$_d/dock.theme" ]; then
      printf '%s\n' "$_d"
      return 0
    fi
  done
  return 1
}

case "${1:-apply}" in
  apply) ;;
  restore) ACTION=restore ;;
  status) ACTION=status ;;
  *) echo "usage: plank.sh [apply|restore|status]" >&2; exit 2 ;;
esac

command -v dconf >/dev/null 2>&1 || {
  echo "нет dconf - без него тему Plank не выбрать" >&2
  exit 1
}
command -v plank >/dev/null 2>&1 || {
  echo "нет plank - нечего красить" >&2
  exit 1
}

KEY=$(dconf_key)
CUR=""
if _raw=$(run_to 5 dconf read "$KEY" 2>/dev/null); then
  CUR=$(printf '%s' "$_raw" | tr -d "'")
else
  # 124 = таймаут. Любой другой код - просто нет ключа, это не повод
  # пропускать покраску: на свежем профиле темы в dconf ещё нет.
  if timed_out $?; then
    log "предупреждение: dconf не ответил за 5 с - тема Plank не тронута"
    echo "dconf не ответил за 5 с, тема Plank не применена" >&2
    exit 0
  fi
fi
CUR=${CUR:-}

if [ "${ACTION:-apply}" = "status" ]; then
  echo "ключ:      $KEY"
  echo "тема:      ${CUR:-(не задана)}"
  echo "исходная:  $(cat "$BASE_FILE" 2>/dev/null || echo '(не записана)')"
  if [ -f "$USER_THEMES/$THEME_NAME/dock.theme" ]; then
    echo "рамка:     $(grep -m1 '^OuterStrokeColor=' "$USER_THEMES/$THEME_NAME/dock.theme" | cut -d= -f2)"
    echo "заливка:   $(grep -m1 '^FillStartColor=' "$USER_THEMES/$THEME_NAME/dock.theme" | cut -d= -f2)"
    echo "радиусы:   $(grep -m1 '^TopRoundness=' "$USER_THEMES/$THEME_NAME/dock.theme" | cut -d= -f2) px"
  fi
  echo "процесс:   $(plank_running && echo работает || echo не запущен)"
  exit 0
fi

# --- restore: вернуть исходную тему ---------------------------------------
if [ "${ACTION:-apply}" = "restore" ]; then
  BASE=$(cat "$BASE_FILE" 2>/dev/null || true)
  if [ -z "$BASE" ]; then
    echo "нечего возвращать: исходная тема не записана" >&2
    exit 1
  fi
  if ! run_to 5 dconf write "$KEY" "'$BASE'"; then
    log "предупреждение: dconf не принял тему за 5 с - осталась текущая"
    echo "dconf не ответил за 5 с, тема Plank не изменена" >&2
    rm -rf "$USER_THEMES/$THEME_NAME"
    exit 0
  fi
  rm -f "$BASE_FILE"
  rm -rf "$USER_THEMES/$THEME_NAME"
  restart_plank || true
  log "возврат на исходную тему: $BASE"
  echo "тема Plank: $BASE (наша $THEME_NAME убрана)"
  exit 0
fi

# --- 1. исходная тема ------------------------------------------------------
# Первый запуск: текущая тема и есть исходная. Дальше исходная берётся из
# state-файла, иначе наша же копия стала бы «исходной» и рамка застыла бы.
BASE=$(cat "$BASE_FILE" 2>/dev/null || true)
if [ -z "$BASE" ]; then
  if [ -z "$CUR" ] || [ "$CUR" = "$THEME_NAME" ]; then
    BASE=Default
  else
    BASE=$CUR
  fi
  mkdir -p "$STATE_DIR"
  printf '%s\n' "$BASE" > "$BASE_FILE"
  log "исходная тема Plank: $BASE"
fi

BASE_DIR=$(theme_dir "$BASE") || {
  log "ошибка: нет темы $BASE (искал в $USER_THEMES и $SYS_THEMES)"
  echo "нет темы Plank '$BASE'" >&2
  exit 1
}

# --- 2. цвет акцента -------------------------------------------------------
# Берём $primary из уже сгенерированного eww/colors.scss: туда попадает
# выбранный акцент (primary/secondary/tertiary) с поправкой на контраст,
# поэтому рамка совпадает с островом при любой схеме, включая «С обоев».
CSS="$ROOT/eww/colors.scss"
[ -f "$CSS" ] || { echo "нет $CSS - сначала theme/apply.sh" >&2; exit 1; }
PRIMARY=$(sed -n 's/^\$primary: *\(#[0-9a-fA-F]\{6\}\).*/\1/p' "$CSS" | head -1)
[ -n "$PRIMARY" ] || { echo "в $CSS нет \$primary" >&2; exit 1; }
# Поверхность острова: заливка дока должна совпадать с телом острова, иначе
# светлая схема острова и тёмный док спорят друг с другом.
SURFACE=$(sed -n 's/^\$surface: *\(#[0-9a-fA-F]\{6\}\).*/\1/p' "$CSS" | head -1)
[ -n "$SURFACE" ] || { echo "в $CSS нет \$surface" >&2; exit 1; }

# --- 3. собрать тему EwwIsland --------------------------------------------
# Док повторяет остров: заливка = $surface, рамка = $primary, радиусы = 18 px
# (как $r-surface у острова). Отличается только прозрачность: заливка чуть
# просвечивает (FILL_ALPHA), чтобы док не выглядел глухим пятном на светлых
# обоях. Раньше менялась одна строка (OuterStrokeColor), теперь - весь набор.
#
# Форму (поля вокруг значков) берём у системной Matte, а не у темы, которая
# стояла у владельца. Копии Default (Tokyonight-*, Catppuccin-* и прочие)
# оставляют вокруг значков большие поля и тень (IconShadowSize=1), поэтому
# подложка уходит ниже значков и её низ режется краем экрана. У Matte
# HorizPadding=1, TopPadding=1.5, BottomPadding=2, IconShadowSize=0 -
# подложка облегает значки. Цвета и радиусы при этом наши.
OUTDIR="$USER_THEMES/$THEME_NAME"
mkdir -p "$OUTDIR"

SHAPE_DIR=$(theme_dir Matte 2>/dev/null || true)
if [ -z "$SHAPE_DIR" ]; then
  log "нет темы Matte - беру форму у $BASE"
  SHAPE_DIR=$BASE_DIR
fi

# Лёгкая прозрачность заливки: 255 - непрозрачно. 230 = ~90 %, обои под доком
# угадываются, но текст и иконки не теряют контраст. 0 (полное стекло) владелец
# забраковал 2026-11-22: док читается только по рамке, значки висят в воздухе.
FILL_ALPHA=230
# Радиус углов дока = $r-surface острова (18 px), чтобы скругления совпадали.
ROUND=18
# Толщина рамки = 2 px, как обводка острова. У Matte этой строки нет вовсе,
# и Plank взял бы свою единицу - рамка была бы в два раза тоньше острова.
LINE_W=2

python3 - "$SHAPE_DIR/dock.theme" "$OUTDIR/dock.theme" "$PRIMARY" "$SURFACE" "$FILL_ALPHA" "$ROUND" "$LINE_W" <<'PY'
import sys, re

src, dst, primary, surface, fill_alpha, round_px, line_w = sys.argv[1:8]

def rgb(hexv):
    hexv = hexv.lstrip("#")
    return tuple(int(hexv[i:i + 2], 16) for i in (0, 2, 4))

pr, pg, pb = rgb(primary)
sr, sg, sb = rgb(surface)
alpha_out = 200      # прозрачность рамки - как в исходной теме
alpha_fill = int(fill_alpha)

text = open(src, encoding="utf-8", errors="replace").read()

def set_line(text, key, value, section="PlankTheme"):
    """Заменить ключ, иначе вставить его в нужную секцию.

    Вставка именно в секцию, а не в начало файла: у Matte в [PlankTheme]
    нет ни одной строки, и ключ, положенный перед заголовком, Plank просто
    проигнорировал бы - док остался бы без цвета.
    """
    pat = re.compile(r"^" + key + r"=.*$", re.M)
    if pat.search(text):
        return pat.sub(key + "=" + value, text, count=1)
    head = re.search(r"^\[" + section + r"\]\s*$", text, re.M)
    if head:
        return text[:head.end()] + "\n" + key + "=" + value + text[head.end():]
    lm = re.search(r"^LineWidth=.*$", text, re.M)
    if lm:
        return text[:lm.end()] + "\n" + key + "=" + value + text[lm.end():]
    return "[" + section + "]\n" + key + "=" + value + "\n" + text

m = re.search(r"^OuterStrokeColor=(\d+);;(\d+);;(\d+);;(\d+)\s*$", text, re.M)
if m:
    alpha_out = int(m.group(4))

text = set_line(text, "OuterStrokeColor", "%d;;%d;;%d;;%d" % (pr, pg, pb, alpha_out))
text = set_line(text, "FillStartColor", "%d;;%d;;%d;;%d" % (sr, sg, sb, alpha_fill))
text = set_line(text, "FillEndColor", "%d;;%d;;%d;;%d" % (sr, sg, sb, alpha_fill))
# Внутреннюю обводку убираем: у острова её нет, остаётся только рамка.
text = set_line(text, "InnerStrokeColor", "%d;;%d;;%d;;0" % (sr, sg, sb))
text = set_line(text, "LineWidth", line_w)
text = set_line(text, "TopRoundness", round_px)
text = set_line(text, "BottomRoundness", round_px)

open(dst, "w", encoding="utf-8").write(text)
PY
# Подпись темы для сравнения: все строки, которые мы задаём. Раньше сравнивали
# только рамку - с новой заливкой этого мало, док остался бы старым. Поля
# вокруг значков тоже в подписи: со сменой формы док обязан перезапуститься.
SIG_KEYS='^(OuterStrokeColor|FillStartColor|FillEndColor|InnerStrokeColor|LineWidth|TopRoundness|BottomRoundness|HorizPadding|TopPadding|BottomPadding|ItemPadding|IconShadowSize)='
NEWLINE=$(grep -E "$SIG_KEYS" "$OUTDIR/dock.theme" | tr '\n' ' ')

# --- 4. выбрать тему и перезапустить Plank --------------------------------
# Сравнивать надо с ПРЕДЫДУЩИМ содержимым, но снимок сделать уже поздно:
# python перезаписал файл. Поэтому сравниваем с тем, что сейчас показывает
# Plank - исходную тему, если выбрана она, иначе нашу (её набор сохранён в
# state-файле после прошлого применения).
STATE_COLOR="$STATE_DIR/plank-color"
SHOWN=$(cat "$STATE_COLOR" 2>/dev/null || true)
if [ "$CUR" != "$THEME_NAME" ]; then
  # Показывается исходная тема - её набор и есть текущий.
  SHOWN=$(grep -E "$SIG_KEYS" "$BASE_DIR/dock.theme" | tr '\n' ' ' || true)
fi

if [ "$CUR" = "$THEME_NAME" ] && [ "$NEWLINE" = "$SHOWN" ] && plank_running; then
  # Уже наша тема, набор тот же и Plank работает - перезапускать незачем.
  # Проверка plank_running обязательна: иначе закрытый док так и остался бы
  # закрытым (проверено - скрипт молча выходил «без изменений»).
  log "без изменений: $NEWLINE"
  exit 0
fi

if ! run_to 5 dconf write "$KEY" "'$THEME_NAME'"; then
  # Тема собрана на диске, но выбрать её в dconf не вышло. Продолжать
  # нельзя: перезапуск Plank подхватил бы старую тему, а следующий вызов
  # снова упёрся бы в тот же dconf. Пишем причину и выходим - остров живёт.
  log "предупреждение: dconf не ответил за 5 с - тема $THEME_NAME собрана, но не выбрана"
  echo "dconf не ответил за 5 с: тема $THEME_NAME собрана, но не выбрана" >&2
  exit 0
fi
restart_plank || true
mkdir -p "$STATE_DIR"
printf '%s\n' "$NEWLINE" > "$STATE_COLOR"
log "тема Plank: рамка $PRIMARY, заливка $SURFACE (тема $THEME_NAME из $BASE)"
echo "док Plank: рамка $PRIMARY, заливка $SURFACE"
