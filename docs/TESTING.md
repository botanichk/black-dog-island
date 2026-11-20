# Тестирование BDI (для человека)
Проверка установщика на своей машине. Всё, что ниже, делает владелец руками;
агент в своём сеансе реальный install не запускает.

## Изоляция тестов (правило, не рекомендация)
Тесты не трогают сеанс владельца: Plank, xfconf, dconf, gsettings, панель
XFCE. Любой тест запускается на своей шине и со своими каталогами:

```
env -u DBUS_SESSION_BUS_ADDRESS -u XDG_RUNTIME_DIR \
    HOME=/tmp/fakehome \
    XDG_CONFIG_HOME=/tmp/fakehome/.config \
    XDG_CACHE_HOME=/tmp/fakehome/.cache \
    XDG_STATE_HOME=/tmp/fakehome/.local/state \
    dbus-run-session -- sh путь/к/тесту.sh
```

- `dbus-run-session` даёт отдельную шину: `xfconfd` стартует заново и видит
  системный дефолт, а не значения владельца.
- Пустые `XDG_*` уводят базы `dconf` и `gsettings` в `/tmp/fakehome`, поэтому
  реальный `~/.config/dconf/user` даже не открывается.
- Проверено 2026-11-20: на тестовой шине `xfce4-session`
  `/sessions/Failsafe/Client2_Command` читается как `xfce4-panel` (дефолт
  системы) вместо реального `true`; записи `TESTVALUE` в dconf и gsettings
  остались в `/tmp/bdi-iso/`; sha256 `~/.config/dconf/user` до и после
  совпал (`bf51af5b…`).
- Если тест обязан читать живые ключи XFCE — это не тест, а замер владельца.

## 1. Проверка системы (только чтение)

Самопроверка `lib/` (изолированно, ничего не меняет):

```
env -u DBUS_SESSION_BUS_ADDRESS -u XDG_RUNTIME_DIR HOME=/tmp/fakehome \
    XDG_CONFIG_HOME=/tmp/fakehome/.config XDG_STATE_HOME=/tmp/fakehome/.local/state \
    BDI_STATE=/tmp/fakehome/.local/state/bdi \
    dbus-run-session -- sh lib/selftest.sh
```

Ожидается 15 строк `ok` и `lib: всё ок`, код 0. Проверено 2026-11-20:
дистро arch/void/unknown, команды pacman и xbps, журнал (включая значение
с табуляцией), копия `~/.config/xfce4`, дамп xfconf, `last-backup`.

`./install.sh check` — каждая строка `OK`, `WARN` или `FAIL`, рядом как
исправить. Ничего не меняет, ничего не просит. В конце — готовая команда
установки отдельно для обязательных и для необязательных пакетов.

### Проверка `check` на заглушках (без реальной системы)

Система подменяется через `OS_RELEASE`, программы — через свой `PATH`.
Настоящий сеанс не трогается: `PATH` состоит только из каталога заглушек и
симлинков на базовые утилиты (`sed`, `awk`, `sort`, `mktemp`).

```
rm -rf /tmp/tv && mkdir -p /tmp/tv/bin /tmp/tv/sys /tmp/tv/home
for c in sed tr sort cut mktemp rm cat awk grep sh ls head dirname mkdir cp mv find; do
  ln -s "$(command -v $c)" /tmp/tv/sys/$c; done
# всё «стоит», кроме magick, nmcli, pactl, brightnessctl
for c in wmctrl xprop curl jq dconf plank ulauncher noctalia cargo pkg-config; do
  printf '#!/bin/sh\nexit 0\n' > /tmp/tv/bin/$c; chmod +x /tmp/tv/bin/$c; done
printf 'ID=void\n' > /tmp/tv/os
env -u DBUS_SESSION_BUS_ADDRESS HOME=/tmp/tv/home PATH=/tmp/tv/bin:/tmp/tv/sys \
  BDI_CONFIG=/tmp/tv/home/.c/bdi BDI_STATE=/tmp/tv/home/.s/bdi BDI_CACHE=/tmp/tv/home/.k/bdi \
  OS_RELEASE=/tmp/tv/os XDG_SESSION_TYPE=x11 XDG_CURRENT_DESKTOP=XFCE \
  sh ./install.sh check
```

Проверено 2026-11-20, Void: код 1, `FAIL` ровно на четырёх командах, в
команде установки четыре пакета без дублей
(`sudo xbps-install -S brightnessctl ImageMagick libpulseaudio NetworkManager`).
Arch (`ID=cachyos`): `sudo pacman -S --needed ...`, те же пакеты под
своими именами. Отдельно проверено, что `check` не создаёт
`~/.local/state/bdi/changes.log` и не меняет `~/.config/autostart`
(контрольная сумма списка файлов до и после совпала).

## 2. Установка (`install`)

Только по инструкции `docs/INSTALL.md`. Агент проверяет `install` на копии
репозитория в `/tmp` с заглушками (`git`, `cargo`, `xfconf-query`,
`xfce4-panel`), настоящий сеанс не трогает. Проверено 2026-11-20 на копии:
резервная копия создана, движок не пересобран (пин совпал), панель
отключена по найденному `Client2_Command`, `bdi.desktop` создан один раз,
второй запуск пишет «автозапуск уже на своём месте», в `changes.log` две
записи (xfconf и autostart).

### Void Linux

Установка на Void целиком **не проверялась** — нет машины. Что сверено:

- имена пакетов в `deps/void.txt` — по настоящему индексу репозитория
  (`repo-default.voidlinux.org/current/x86_64-repodata`, 2026-11-20);
- `pactl` даёт пакет `libpulseaudio`, заголовки для сборки —
  `pulseaudio-devel` (не `libpulseaudio-devel`, его в индексе нет);
- `gtk+3-devel`, `libdbusmenu-gtk3-devel`, `cargo`, `gcc`, `pkgconf` есть;
- `noctalia` и шрифта Meslo в индексе нет — цвета с обоев и глифы кнопок
  на Void недоступны без ручной установки, `check` скажет об этом `WARN`.

Если на Void стоит только PipeWire без PulseAudio-совместимого слоя,
`pactl` может не найти сервер: вкладка громкости покажет 0 %.

## 3. Обновление (`update`)

```
./install.sh update
```

Проверено 2026-11-20 на двух клонах в `/tmp` (один играет роль GitHub).
`git pull --ff-only` прошёл, движок не пересобирался при неизменном пине,
`changes.log` не создан (настроек `update` не меняет).

Проверено также, что `update` честно **падает** с кодом 1, если остров не
поднялся: до исправления `cmd 2>&1 | sed` код возврата терялся, потому что
в POSIX sh после pipe возвращается код `sed`. Теперь короткий вывод идёт
через `run_indent` (файл + `sed`), а сборка движка — без pipe вовсе, чтобы
прогресс шёл живым.

Ещё два случая, проверенные на копиях:

- локальные правки: `update` печатает `WARN в репозитории есть свои правки`
  и список файлов, правку не выбрасывает;
- каталог без `.git` (скачан ZIP-ом): `FAIL ... не клон git`, код 1.

## 4. Откат
Только после шага 5. Одна команда, журнал изменений в обратном порядке.

## Что прислать при проблеме
Вывод `./install.sh check` и последние 20 строк
`~/.local/state/bdi/changes.log`. Имя пользователя и домашний путь
заменить руками на `$USER` и `~`.
