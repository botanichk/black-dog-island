# Факты для BDI (Black Dog Island), 2026-11-20

Задание 15, часть B. Только чтение: код не менялся, пакеты не ставились,
ничего не публиковалось. Дата: `date` -> `2026-11-20`.
Секреты соблюдены: домашний путь заменён на `~`, имя пользователя на `$USER`,
имена Wi-Fi сетей, город и координаты не печатаются.

У каждого утверждения - команда или файл-источник. Где не проверено -
`[не известно]`.

## B1. Что проект меняет в системе вне репозитория

### Статически (по коду)

| Путь или ключ | Кто пишет | Зачем | Откат |
|---|---|---|---|
| `xfce4-desktop/<key>.last-image` | `desktop.sh:86,89` (`xfconf-query -s`/`-n`) | обои текущего стола | `xfdesktop-settings` |
| `~/.config/hypr-wallpicker/apply-wallpaper.sh` | `wallpicker/install.sh:56` (`ln -sfn`) | хук обоев под XFCE | `rm` ссылки |
| `~/.cache/bdi/` (`$BDI_CACHE`) | `timer.sh:28`, `forecast.sh:17`, `wifi.sh:26`, `mpris.sh:30`, `screenshot.sh:107`, `wall-schemes.sh:66` | кэши, логи, `kbdlayout`, `pointer`, `theme.log` | `rm -rf` |
| `~/.config/bdi/` (`$BDI_CONFIG`) | `plank.sh:31`, `ulauncher.sh:41` | выбор темы, база и цвет темы Plank, тема Ulauncher | `rm -rf` |
| `~/.local/state/bdi/` (`$BDI_STATE`) | `apply.sh`, `colors-pick.sh`, `accents.sh`, `switch.sh`, `from-wallpaper.sh` | сгенерированные схемы (`schemes/`) | `rm -rf` |
| `~/.local/share/plank/themes/EwwIsland/` | `plank.sh` | док в цвет острова | `rm -rf` + тема через `dconf` |
| `~/.config/ulauncher/user-themes/light/` | `ulauncher.sh` | Ulauncher в цвета острова | `rm -rf` |
| `~/.config/noctalia/palettes/*.json` | `theme-save.sh` (по клику) | свои темы | удалить файл |
| `dconf` ключ темы Plank | `plank.sh:130` | переключить Plank на `EwwIsland` | прежнее имя |
| `xfce4-panel` канал | никто | панель отключена вручную (B2) | — |

`gsettings set` в проекте **нет** (`rg` пуст). Записей в `~/.config/autostart`
из репозитория тоже нет: файлы созданы руками (ниже).

### Фактически на этой машине

Содержимое `~/.cache/bdi/`: `art/`, `thumbs/`, `timer/`,
`wall-schemes/`, `kbdlayout`, `pointer`, `island-width`, `weather.json` и
логи (`autohide`, `plank`, `ulauncher`, `wallpicker`, `power`, `theme`).
`city.txt` содержит город владельца - значение не печатается.

```
~/.config/bdi/:        accent  current  hue-filter  mode  wallpaper-scheme
                       plank-base-theme  plank-color  ulauncher-theme
~/.local/state/bdi/:   schemes/  (22 сгенерированные схемы)
~/.cache/bdi/:         кэш, pid автоскрытия, island-width, логи
~/.config/hypr-wallpicker/apply-wallpaper.sh -> <клон>/adapters/wallpicker/apply.sh
~/.local/share/plank/themes/EwwIsland/   (19 ноября; остальные темы от янв. 2023)
~/.config/ulauncher/user-themes/light/   (18 ноября, наша)
~/src/hypr-wallpicker                    (исходники wallpicker, вне репозитория)
```

Старые пути `~/.config/eww-island` и `~/.cache/eww-island` больше не
пишутся: их переносит `scripts/migrate-state.sh` (идемпотентно, оригиналы
удаляет только при совпадении байт в байт).

### Автозапуск (создан вручную, не скриптами проекта)

```
~/.config/autostart/: eww-island  plank  ulauncher  xfdesktop
Exec: eww-island -> <клон>/scripts/run-island.sh  (сейчас: /home/$USER/eww-island/...)
      plank -> plank | ulauncher -> ulauncher --hide-window | xfdesktop -> xfdesktop
```

`eww-island.desktop` содержит полный личный путь: установщик обязан
записывать путь клона сам, иначе остров не поднимется после переноса.
Автозапуск **целиком** настраивался вручную, установщика в репозитории нет.

## B2. Как отключена панель XFCE

```
$ xfconf-query -c xfce4-session -lv | grep -i -E 'panel|client'
/sessions/Failsafe/Client0_Command  [xfwm4]
/sessions/Failsafe/Client1_Command  [xfsettingsd]
/sessions/Failsafe/Client2_Command  true
/sessions/Failsafe/Client3_Command  [Thunar, --daemon]
/sessions/Failsafe/Client4_Command  [xfdesktop]
(панели в списке клиентов сессии НЕТ)
```

`Client2_Command = true` - заглушка: так XFCE отключает клиента сессии.
Раньше на этом месте стояла `xfce4-panel`.

```
$ ls ~/.config/autostart | grep -i panel      -> пусто
$ ls ~/.config/xfce4/panel                    -> только screenshooter-8.rc (плагин, не панель)
$ pgrep -a xfce4-panel                        -> пусто (не запущена)
$ xfce4-panel --version                       -> xfce4-panel 4.20.8 (Xfce 4.20)
```

`/etc/xdg/autostart/` панели **не содержит** (`ls | grep -i panel` и
`rg -l 'xfce4-panel'` пусты). Значит панель поднималась восстановлением сессии,
не автозапуском. Ключа-выключателя нет: `/panels/panel-1` на месте, панель
просто не запущена. Файлов `~/.cache/sessions/*.session` нет.

### История оболочки (только строки про панель)

```
xfce4-panel --quit
xfce4-panel
xfce4-panel --quit
grep -RniE 'xfce4-panel' ~/.config/autostart /etc/xdg/autostart ~/.config/xfce4
xfce4-panel &
```

**Вывод о способе**: панель отключена вручную - команды `xfce4-panel --quit`
и правка списка клиентов сессии (`Client2_Command = true`). Автозапуска панели
нет ни в `/etc/xdg/autostart`, ни в `~/.config/autostart`, ни в сессии.

**Как проверить, что не вернётся**: после перезагрузки
`pgrep -a xfce4-panel` должен быть пустым, а
`xfconf-query -c xfce4-session -p /sessions/Failsafe/Client2_Command -v`
должен печатать `true`. Внимание: если XFCE сохранит сессию при выходе
(в настройках сеансов включено «сохранять»), панель может вернуться - флаг
сохранения сессии `[не известно: спросить владельца]`, в текущем
`xfce4-session.xml` сессии `Default` только `Failsafe`, файла `.session` нет.

## B3. Автозапуск и порядок

Порядок клиентов сессии (по `Priority`, меньше - раньше):

| Приоритет | Клиент | Что это |
|---|---|---|
| 15 | `xfwm4` | оконный менеджер (нужен раньше всех) |
| 20 | `xfsettingsd` | настройки XFCE (тема, шрифты) |
| 25 | `true` | отключённый клиент (был `xfce4-panel`) |
| 30 | `Thunar --daemon` | файловый менеджер |
| 35 | `xfdesktop` | рисует рабочий стол и обои |

`~/.config/autostart` (XDG, после сессии): `eww-island`, `plank`, `ulauncher`,
`xfdesktop`. `X-GNOME-Autostart-Phase` и задержек в файлах **нет** - стартуют
одновременно.

Остров поднимает `eww-island.desktop` -> `scripts/run-island.sh`, который ждёт
готовности окна (`until "$GEOM" xid; do sleep 0.05; done`, плюс `sleep 0.3` в
двух местах). Задержек «подождать Plank/Ulauncher» нет: на порядок опирается
**только трей** - значки приложений должны появляться после острова, иначе не
попадут в трей. Кодом это не проверить, нужно смотреть глазами после входа.

`Marsik FM` и `PortProtonQt` в автозапуске **не найдены**
(`ls ~/.config/autostart`, `pgrep -af` пусто): `[не известно: спросить владельца]`.

## B4. Зашитое под эту машину

| Значение | Файл:строка | Что делать |
|---|---|---|
| 619 (ширина острова) | `eww.scss:46` (`$island-w`), `island-autohide.py:64` (`DEFAULT_WIDTH`) | оставить (константа владельца); `DEFAULT_WIDTH` лучше читать из `$island-w` |
| 358 (высота хаба), 330 (тело) | `eww.scss:894`, `eww.scss:1175` | оставить, вычислено из вёрстки |
| 373, 1366, 768 | **только комментарии** (`wallpicker/run.sh:8-32`) | ничего: центровка из `run-island.sh:110-123` (`xrandr`) |
| `wlan0` | `wifi.sh:73` - запасное значение после автопоиска | оставить |
| `LVDS` | только комментарии (`desktop.sh:58`, `from-wallpaper.sh:26`) | оставить, монитор перебирается |
| `$HOME/eww-island` | **0 вхождений** после шага 14-portable | **сделано**: пути в `eww.yuck` и `timer.sh` идут через `$BDI_ROOT` |
| `eww-island` (кэш) | было ~15 мест | **сделано**: `$BDI_CACHE` (`~/.cache/bdi`) |
| `intel_backlight` | не найдено | — |
| имена Plank-тем, путь `noctalia`, число столов | берутся из `dconf` / по `command -v` / из `wmctrl -d` | оставить |
| город и координаты | **не в коде**: `~/.cache/noctalia/location.json` (`forecast.sh:14,23-24`) | оставить: личное вне репозитория |

Вычисляется само: позиция острова (`run-island.sh:110-123`, `xrandr` ->
`want_x = (SCREEN_W - iw) / 2`), размер панелей (`panel.sh` из `wmctrl`),
стол обоев (`desktop.sh` перебирает ключи), устройство Wi-Fi (`wifi.sh`).
**Не** вычисляется: ширина острова задана дважды (SCSS и Python).

Другой экран по коду: центровка работать должна (`xrandr` даёт ширину), но
**не проверено** - экрана нет. Числа `1366x768` в `wallpicker/run.sh` подобраны
под этот; на 1920x1080 сетка обоев будет иной, но не сломается.

## B5. Матрица возможностей

«тихо» = функция врёт без ошибки; «громко» = пишет в stderr.

| Функция | Нужные команды | Пакет Arch (проверено `pacman -Qo`) | Без команды (по коду и проверке) |
|---|---|---|---|
| Воркспейсы | `wmctrl`, `xprop` | `wmctrl 1.07-6`, `xorg-xprop 1.2.8-1` | `[не проверено]`, скорее пусто |
| Трей | сам Eww (XEmbed) | — (внутри `build/`) | трей пуст |
| Раскладка | `gcc` + `kbdlayout.c` | `gcc 16.2.1` | без `gcc` плашка молчит (сборка в кэш) |
| Громкость | `pactl` | `libpulse 17.0` | **тихо**: 0 % (проверено, `home.sh all` дал `volume:0`) |
| Яркость | `brightnessctl` | `0.5.1-3` | `[не проверено]`, запасной путь через `/sys` |
| Wi-Fi | `nmcli` | `networkmanager 1.58.1-3` | **тихо и опасно**: `state`->`отключено`, `level`->`none`, `radio`->`off`, `list`->пусто, код 0. Видно «Wi-Fi выключен», хотя он работает |
| Bluetooth | `bluetoothctl` | `bluez-utils 5.88-1` | `[не проверено]` |
| Питание: выход | `loginctl` + `xfce4-session-logout`/`dbus-send` | `systemd 262.2-1` | три пути с откатом (`power.sh:42-62`) |
| Питание: reboot/poweroff | `systemctl` | `systemd 262.2-1` | без systemd **не работает** (B6) |
| Снимки | `import`, `magick` | `imagemagick 7.1.2.35-1` | `[не проверено]`, запасной `-window` |
| Обои | `hypr-wallpicker` (из `~/src`), `xfconf-query`, `xrandr` | `xfconf 4.20.0-2`, `xorg-xrandr 1.5.4-1` | кнопка молчит, запасной `xfdesktop-settings` |
| Цвета с обоев | `noctalia` | `noctalia 5.5.0-1` | ряд «С обоев» не рисуется (`n=0`), вкладка цела |
| Plank-тема | `plank`, `dconf` | `plank 0.11.89-6` | `[не проверено]`, в лог «не применилась» |
| Погода | `curl`, `jq`, `noctalia` | `curl 8.23.0-2`, `jq 1.8.2-1` | **громко**: `curl: command not found` в stderr, на выходе `—` |
| Медиа | `busctl` | `systemd 262.2-1` | `[не проверено]`, пустой JSON |

Проверка «скрытой командой»: каталог со ссылками на 30 базовых утилит, кроме
проверяемой, затем `PATH=... sh script`.

### Что можно прятать

- Погода без `curl`/`jq`: вкладку скрыть целиком, данные всё равно `—`.
- Wi-Fi без `nmcli`: **нельзя** просто скрыть - сейчас «отключено». Нужен
  честный признак «NetworkManager недоступен».
- Громкость без `pactl`: `0` похоже на выключенный звук. Нужен признак.
- «С обоев» без `noctalia`: ряд скрывается сам (`n=0`) - так и оставить.

## B6. systemd и D-Bus

| Вызов | Файл:строка | Зачем |
|---|---|---|
| `busctl --user list` | `media/mpris.sh:37` | найти MPRIS-плееры |
| `busctl --user get-property` | `mpris.sh:62,81,121,127,313` | статус, позиция, метаданные |
| `busctl --user call` | `mpris.sh:92,96,100,125,128` | play/pause, next, prev, seek |
| `busctl --user --json=short` | `mpris.sh:148` (`spectrum.py`) | тихо: без ответа «не играет» |
| `systemctl reboot` / `poweroff` | `x11/power.sh:83-88` | перезагрузка, выключение |
| `loginctl list-sessions` | `power.sh:42` | найти текущую сессию (чтение) |
| `xfce4-session-logout --logout` | `power.sh:48-50` | выход (путь 1) |
| `dbus-send ... xfce.Session.Manager.Logout` | `power.sh:53-57` | выход (путь 2) |
| `notify-send` | `timer/timer.sh:165` | «Время вышло» |

`polkit` напрямую не вызывается: `systemctl poweroff`/`reboot` проходит, потому
что polkit разрешает это локальной активной сессии без пароля (`power.sh:6-7`).
Выход сделан **не** через `loginctl terminate-session`, чтобы не требовать
пароля (`power.sh:11-21`).

Без systemd не работают **перезагрузка, выключение и медиа** (`busctl`);
`loginctl` - только чтение. На Void с runit их надо заменить на
`poweroff`/`reboot` и `dbus-send`. `[не проверено]`: Void тут не стоит.

## B7. Лицензии

| Компонент | Лицензия / источник | Можно ли включать в репозиторий |
|---|---|---|
| Eww (движок) | MIT (`build/eww-src/LICENSE`: «MIT, Copyright (c) 2020 ElKowar») | код не копируем - решение владельца; патчи отдельно |
| `patches/*.patch` (4 шт.) | наш текст | да, включать |
| hypr-wallpicker | MIT (`~/src/hypr-wallpicker/LICENSE`: «MIT, © 2026 Horizon») | патчи да; код целиком лучше не тащить |
| Noctalia | `[не известно]`: `pacman -Qi` лицензию не печатает | палитры уже лежат в `theme/palettes/` (10), источник в `docs/THEME.md` |
| 41 палитра сообщества | в файлах **нет** ни автора, ни лицензии (ключи только `dark`/`light`) | **не включать без проверки** |
| Meslo Nerd Font | `[не известно]` | не включать: ставится пакетом |
| Темы Plank | наша `EwwIsland` - копия исходной с одной строкой (`plank.sh:10-13`) | нашу можно, чужие не тащим |
| Наши SVG | наши, генерируются из `theme/templates/` | да |
| Иллюстрации погоды (16 JPEG) | сгенерированы Qwen (`tasks/06...:16`) | условия сервиса `[не известно: владелец]` |
| Обои | личные картинки владельца | **нет**, вне репозитория |

## B8. Личное в репозитории и истории

### В текущем дереве (файл:строка, без содержимого)

```
$ git grep -nI -E '<имя пользователя>|/home/|<город>|<SSID>' | wc -l
12
adapters/wallpicker/apply.sh:25
adapters/weather/forecast.sh:21
docs/report-2026-11-12-prototype.md:280,282,283
docs/tasks/11-colors.md:27
docs/tasks/12-colors-accents.md:474,475
docs/tasks/13-wallpicker.md:123
docs/tasks/15-audit-and-bdi-facts.md:6,40,56
```

В **коде** два места, оба комментарии: `apply.sh:25`, `forecast.sh:21`.
Остальное - текст заданий и старый отчёт. Паролей, токенов, e-mail нет.

### В истории

| Что искали (слово не печатается) | Коммитов |
|---|---|
| имя пользователя | 5 |
| домашний путь | 5 |
| название города | 2 |
| SSID владельца, слово 1 | 1 |
| SSID владельца, слово 2 | 2 |

Слова остаются в истории, даже если убрать их из текущего дерева.

### Бинарники

`docs/screenshots`: 18 PNG, все в git, 856K. Тяжёлые объекты истории:
`adapters/timer/sounds/_old.wav` 0.5 МБ (из индекса убран, в истории остался),
`prototype-3-top.png` 0.4 МБ, `alarm.wav` 0.3 МБ.

**Утечёт при публикации текущей истории**: `$USER` (5 коммитов), домашний
путь (5), название города (2), имя Wi-Fi сети владельца (2 + 1), `_old.wav`
(0.5 МБ), 18 скриншотов стола (могут содержать чужие окна и имена файлов).
Чистая история или `filter-repo` - **за владельцем**. Аудит ничего не чистил.

## B9. Состояние внутри репозитория при работе (после шага 1 задания 16)

| Файл | Пишется при работе | В git? | Мешает `git pull`? |
|---|---|---|---|
| `eww/colors.scss` | да (`theme/apply.sh`) | нет (`.gitignore`) | нет |
| `eww/assets/*.svg` (19 шт.) | да (тот же `apply.sh`) | нет | нет |
| `~/.config/bdi/current` | да (`colors-pick.sh`, `apply.sh`) | вне репозитория | нет |
| `~/.config/bdi/mode` | да | вне репозитория | нет |
| `~/.config/bdi/{accent,wallpaper-scheme,hue-filter}` | да | вне репозитория | нет |
| `~/.local/state/bdi/schemes/*.json` | да | вне репозитория | нет |
| `theme/__pycache__/` | да (Python) | нет | нет |
| `adapters/timer/sounds/*` кроме `alarm.wav` | кладёт владелец | нет | нет |
| `eww/assets/weather-src/` | исходники генератора | нет | нет |

`git status` чистый после смены темы, акцента и обоев - это и есть приёмка
шага 1.

### Что осталось внутри репозитория и почему

`colors.scss` и 19 SVG генерируются в `eww/` на месте, а не в каталог
состояния. Причина: `eww.scss` импортирует `@import "colors"` относительно
своего каталога (абсолютный путь GTK не берёт), а `:path` в 19 местах
`eww.yuck` идут через `${EWW_CONFIG_DIR}/assets/`. Вынос потребовал бы
runtime-каталога симлинков и 19 правок yuck - за это время ничего не
окупается. Побочные следствия: `git clean -xfd` сносит тему (собирается
заново `theme/apply.sh` при старте острова), а запуск из каталога только на
чтение не сработает.

Остальное состояние вынесено: `$BDI_CONFIG` (выбор пользователя),
`$BDI_STATE` (сгенерированные схемы), `$BDI_CACHE` (кэш и pid-файлы).
Три переменные экспортирует один `scripts/run-island.sh`, дальше их читают
25 файлов; при ручном запуске скрипты берут те же значения по умолчанию.

## B10. Сборка и обновление

```
$ git -C build/eww-src describe --tags
v0.6.0-91-g48f5aa8
$ git -C build/eww-src log --oneline -1
48f5aa8 switch yolk link to website rather than git repo
$ rg '^version' build/eww-src/crates/eww/Cargo.toml
version = "0.6.0"
$ rustc --version; cargo --version
rustc 1.100.0 (0ef1bc386 2026-11-09)
cargo 1.100.0 (3acc79c0c 2026-11-05)
$ du -sh build/ build/target build/eww-src
2.0G  build/   2.0G  build/target   3.7M  build/eww-src
$ ls -la build/target/release/eww
23165376 байт, 19 ноя 18:19
```

Пин: коммит `48f5aa8`, тег-база `v0.6.0`. **В репозитории пин нигде не
записан**: `scripts/build-eww.sh` работает с уже распакованным `build/eww-src`
и `git checkout` не делает (комментарий `build-eww.sh:6`). Для установщика пин
придётся вписать отдельно - сейчас его взять неоткуда, кроме `build/eww-src`.

Время сборки с нуля **не измерено** (пересборка долгая и меняет `build/`,
что запрещено): `[не известно]`. `build/` = 2.0 ГБ, почти всё `target/`.

`CARGO_TARGET_DIR` вынести технически можно, но `build-eww.sh` его не
использует, а путь `build/target/release/eww` зашит в 20+ скриптах.
**Не проверено.** Для сборки нужны Rust 1.100.0 и dev-пакеты по
`docs/report-2026-11-12-deps.md` (в этой сессии не перепроверял).

Что делает каждый патч (по имени и заголовку файла):

| Патч | Что меняет |
|---|---|
| `eww-0001-onscroll-*` | `onscroll` отдаёт направление прокрутки |
| `eww-0002-spectrum-cairo-widget` | свой Cairo-виджет спектра |
| `hypr-wallpicker-blur-backdrop` | размытый фон под сеткой (`--blur`, `--scrim`) |
| `hypr-wallpicker-size-and-cancel` | размер сетки, отмена кликом мимо |

Повторное применение: `build-eww.sh:22-47` сначала проверяет
`git apply --reverse --check`, и если патч уже наложен - откатывает и
накладывает заново (идемпотентно). Где ждёт бинарник:
`build/target/release/eww` (жёстко, во всех скриптах через `$EWW`).

Скрипты, вызывающие `eww` без пути: **не найдено** (проверено
`rg '"eww "|\beww '` - только `$EWW` и упоминания в комментариях).
Значит системный `eww` другой версии не перехватит: все вызовы идут по
полному пути `build/target/release/eww`. Запуск `eww` из терминала владельцем
всё равно попадёт в системный - но это его действие, не скриптов.

Два экземпляра Eww одновременно (наш демон и чужой) конфликтуют за сокет
демона `--config`: `[не проверено]`, но именно поэтому путь к конфигу
передаётся явно везде.

## B11. Кандидаты для `bdi doctor`

| Команда | Что доказывает | Ожидаемое значение (вычисляемое) |
|---|---|---|
| `wmctrl -lG \| rg 'Eww - island'` | остров открыт и стоит на месте | x = (ширина монитора - ширина окна)/2, y = 0, h = 50 |
| `xprop -id <остров> _NET_WM_STRUT` | резерв сверху занят | третье число = высота острова |
| `xprop -id <остров> _NET_WM_STRUT_PARTIAL \| ...` | резерв не режет весь экран | последние числа = 0..(ширина-1) |
| `wmctrl -lG \| rg 'Eww - panel-hub'` | хаб открывается и той же ширины | x и w как у острова, y = высота острова |
| `import -window <остров> -crop 1x1+1+1 txt:-` | углы скруглены (прозрачны) | `#000000` в углу при закрытом хабе |
| `import -window <остров> -crop 1x1+<центр>+<низ> txt:-` | тело на месте | цвет `$surface` текущей схемы |
| `pgrep -c -f 'eww --config .* daemon'` | ровно один демон | 1 |
| `pgrep -c -f island-autohide.py` | автоскрытие живо | 1 |
| `build/.../eww --config eww reload` | конфиг разбирается | код 0, пустой вывод |
| `sh -n` по всем `*.sh` | синтаксис | код 0 |
| `python3 -m py_compile` по `*.py` | синтаксис | код 0 |
| `nmcli -t -f RUNNING general` | NetworkManager жив | `running` |
| `nmcli radio wifi` | радио включено | `enabled` (только чтение) |
| `pactl get-sink-volume @DEFAULT_SINK@` | звук доступен | код 0 и число процентов |
| `brightnessctl -m` | яркость читается | код 0 |
| `bluetoothctl show \| rg Powered` | Bluetooth есть | `Powered: yes` (только чтение) |
| `command -v noctalia` | палитры с обоев доступны | путь |
| `command -v xfconf-query xrandr wmctrl xprop magick` | базовые зависимости | пути |
| `xfconf-query -c xfce4-panel -l 2>/dev/null \| wc -l` | панель не запущена | ключи есть, но `pgrep xfce4-panel` пуст |
| `pgrep -a xfce4-panel` | панель XFCE не вернулась | пусто |
| `ls ~/.config/hypr-wallpicker/apply-wallpaper.sh` | хук обоев на месте | символическая ссылка жива |

Важно для doctor: **не** считать «Wi-Fi выключен» по `wifi.sh state`, если
`nmcli` нет - это даст ложное «всё плохо» (см. B5).

## B12. Условия для чистой проверки установки

```
$ id
uid=1000($USER) gid=1000($USER), группы: sys, network, nopasswdlogin, rfkill,
users, video, storage, lp, audio, wheel
$ getent passwd | awk -F: '$3>=1000 && $3<65534' | wc -l
1                       (один обычный пользователь; имя не печатаю)
$ df -h /home
доступно 77G из 224G
$ command -v qemu-system-x86_64 virt-manager systemd-nspawn machinectl distrobox podman docker xvfb-run Xephyr Xnest
systemd-nspawn  /usr/bin/systemd-nspawn
machinectl      /usr/bin/machinectl
(остальные: НЕТ)
```

Второй X-сеанс поднять **нечем**: `Xephyr`, `Xnest`, `xvfb-run` не
установлены; `systemd-nspawn`/`machinectl` есть, но это контейнеры без X и
требуют root. Значит проверка установки сейчас возможна только «в живую»,
с риском для рабочего стола. `[не известно]`, пока не поставлен Xephyr/QEMU.

## B13. Решения владельца (дописать в docs/TASKS.md, раздел «Решения»)

Из задания 15, часть B13 - переношу как есть:

- Установщик делает всё сам, включая отключение панели XFCE и автозапуск.
- Откат двухуровневый: архив настроек + журнал изменений.
- Поддерживаются чистый и уже настроенный XFCE.
- Цель: «взял и установил».
- Имя BDI (Black Dog Island), отдельный репозиторий.
- Код Eww не копируется: берётся по закреплённому коммиту, патчи наши.
- Встроенные палитры Noctalia лежат в репозитории, сама Noctalia есть на
  целевых машинах.
- Целевые системы: CachyOS и Void Linux.
- Спеки по этим решениям пишутся по слову владельца.

## Что проверено не до конца

| Что | Почему |
|---|---|
| Время и команда полной сборки Eww | не запускал: долго и меняет `build/` (запрещено правилами) |
| Поведение на другом разрешении экрана | другого экрана нет, `[не проверено]` |
| Void Linux без systemd (питание, медиа) | Void не установлен |
| Лицензия Noctalia и её палитр | `pacman -Qi` не печатает лицензию, апстрим не открывал |
| Условия Qwen для иллюстраций погоды | нужен ответ владельца |
| Порядок трея при входе (остров раньше приложений) | нужно смотреть глазами после входа |
| Причина `os error 11` на первом `eww reload` | воспроизводится не всегда (см. аудит) |
| Marsik FM и PortProtonQt: как связаны с островом | не в автозапуске, `[не известно: спросить владельца]` |

Владельцу проверить глазами: перечисленные выше «не проверено» - глазами;
файл стоит просмотреть целиком перед отправкой наружу.
