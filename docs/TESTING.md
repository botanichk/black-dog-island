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
Ставится в шаге 3 установщика; пока `install.sh` нет, проверяется то, что есть.

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

Ожидается после шага 3:

```
./install.sh check
```

Каждая строка — `OK`, `WARN` или `FAIL`, рядом как исправить. Ничего не
меняет, ничего не просит.

## 2. Установка на тестовом пользователе
Только по готовой инструкции (`docs/INSTALL.md`), после шага 4.

## 3. Откат
Только после шага 5. Одна команда, журнал изменений в обратном порядке.

## Что прислать при проблеме
Вывод `./install.sh check` и последние 20 строк
`~/.local/state/bdi/changes.log`. Имя пользователя и домашний путь
заменить руками на `$USER` и `~`.
