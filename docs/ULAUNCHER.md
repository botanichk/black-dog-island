# Тема Ulauncher в цвета острова

Ulauncher перекрашивается вместе с островом: рамка в `$primary`, фон в
`$surface`, активная строка темнее неактивных, углы скруглены. Сменил
палитру, акцент или обои — Ulauncher перекрасился, отдельной настройки нет.

Сделано по образцу Plank (`theme/plank.sh`, `docs/PLANK.md`), но с одним
важным отличием: **Ulauncher не надо перезапускать**.

## Как это устроено

```
theme/apply.sh                     рендерит eww/colors.scss ($primary, $surface)
  -> theme/ulauncher.sh apply      собирает копию темы из этих цветов
  -> ~/.config/ulauncher/user-themes/<твоя-тема>/theme.css
  -> kill -HUP <pid ulauncher>     перечитать (reload_config -> init_theme)
```

`theme/ulauncher.sh` вызывается из `theme/apply.sh` последним шагом (после
`plank.sh`), поэтому работает при любом способе смены темы: вкладка «Цвета»,
смена акцента, переключение режима, схема «С обоев» и хук выбора обоев.
Если `ulauncher.sh` отсутствует или упал, `apply.sh` продолжает работу —
остров не должен зависеть от лаунчера.

## Почему без перезапуска

В `main.py` Ulauncher висит обработчик `SIGHUP` → `reload_config()` →
`init_theme()`. Тот заново вызывает `load_available_themes()`, читает
`manifest.json` и грузит CSS в `CssProvider`. Проверено: правка `theme.css`
+ `kill -HUP` перечитывается без перезапуска процесса — окно не мигает и не
теряет введённый запрос.

Plank так не умеет (`docs/PLANK.md`), поэтому там `pkill` и ~1 с мигания.

## Почему наша тема называется как твоя

`SIGHUP` перечитывает **CSS**, но **не** `settings.json`: `Settings` в памяти
— синглтон, файл читается один раз при старте. Если бы мы завели тему с
отдельным именем (`eww-island`), пришлось бы править `theme-name` в
`settings.json` и перезапускать демона.

Поэтому мы кладём копию в `user-themes/<имя-твоей-текущей-темы>/`.
`load_available_themes()` читает сначала `/usr/share/ulauncher/themes`, потом
`user-themes`, и перезаписывает словарь по имени — наша копия перекрывает
системную. `theme-name` не меняется вообще.

Побочный эффект: в настройках Ulauncher тема по-прежнему называется
«Elementary Light», хотя внутри цвета острова. Это цена отсутствия
перезапуска; захочешь отдельное имя — скажи, переделаю.

Если сменишь тему в настройках на другую, `apply` заметит это и перенесёт
копию под новое имя, а старую уберёт (метка `.eww-island` в каталоге).

## Какие цвета откуда

| `@define-color` | откуда | зачем |
|---|---|---|
| `bg_color`, `window_bg` | `$surface` | фон окна |
| `window_border_color` | `$primary` | рамка, как у Plank |
| `item_box_selected` | `$surface-container-high` | активная строка |
| `item_name`, `input_color` | `$on-surface` | текст, ввод |
| `item_text`, `item_name_selected` | `$on-surface-variant` | вторичный текст |
| `caret_color` | `$primary` | каретка ввода |
| `selected_bg_color` | `$surface-container-high` | выделение в поле ввода |
| `prefs_backgroud` | `$surface-container` | фон кнопки настроек |
| `window_shadow` | `rgba(0,0,0,0.45)` | тень окна |

Про «активное темнее, неактивное светлее»: в CSS Ulauncher нет класса
«наведение», есть только `.selected.item-box`. Строки сами по себе
прозрачные (фон окна `$surface`), а активная получает `$surface-container-high`
— в светлой схеме это **темнее** фона, в тёмной **светлее**. Роль выбрана
так, чтобы выделение работало в обеих схемах, а не «темнее на N шагов».

## Скругления и рамка

`.app` — само окно: `border: 2px solid $primary`, `border-radius: 16px`.
Активная строка — `border-radius: 10px`. Боковые линии исходной темы
(`border-left`/`border-right` у `.selected.item-box`) убраны: с нашей рамкой
они давали двойную обводку.

Порядок правил в файле важен: сначала тело исходной темы, **потом** наши
правила. При равной специфичности в CSS побеждает последнее, поэтому при
первом прогоне наши 16px перебивались исходными 4px — было поймано замером.

## Количество строк результатов

Это `show-recent-apps` в `~/.config/ulauncher/settings.json` — сколько частых
приложений Ulauncher показывает при пустом вводе. CSS этого не задаёт: строки
создаёт Python.

```sh
theme/ulauncher.sh rows 6     # перезапуск ~0.44 с (settings.json меняется)
```

Перезапуск нужен именно потому, что `Settings` — синглтон в памяти.
Проверено: `rows 5` пишет файл, поднимает демона за 0.44 с.

⚠️ Строк может оказаться меньше запрошенного: Ulauncher показывает только те
приложения из `app_stat_v2.db`, которые реально существуют. Если в базе
4 записи и одна `.desktop` удалена — покажет 3, сколько ни проси.

## Команды

```sh
theme/ulauncher.sh apply      # перекрасить (это же делает apply.sh)
theme/ulauncher.sh status     # тема, наша копия, цвета, pid, строк
theme/ulauncher.sh restore    # убрать нашу копию, вернуть системную
theme/ulauncher.sh rows <n>   # сколько строк результатов (1..20)
```

`restore` удаляет нашу копию и кэш темы, посылает `SIGHUP`. Повторный
`restore` отвечает «нечего возвращать» и выходит с кодом 1.

## Как проверить

```sh
grep -m1 '^\$primary:' eww/colors.scss      # например #be4601
grep -m1 '^\$surface:' eww/colors.scss      # например #eff1f5
theme/ulauncher.sh status                    # рамка/фон/активная строка
# окно: gdbus call --session --dest net.launchpad.ulauncher \
#   --object-path /net/launchpad/ulauncher \
#   --method net.launchpad.ulauncher.toggle_window
import -window root /tmp/p.png               # замер пикселей PIL
```

Замеры на этой машине (тема `light`, схема `c-catppuccin-mocha-pink`):

| что | цвет | где на экране | пикселей |
|---|---|---|---|
| рамка | `#be4601` (`$primary`) | `x=400..967 y=173..431` | 3195 |
| фон окна | `#eff1f5` (`$surface`) | `x=402..965 y=175..429` | 106182 |
| активная строка | `#c0c5d1` (`$surface-container-high`) | `y=252..307` | 28479 |

Тема переживает смену палитры на лету: `colors-pick.sh palette p-noctalia`
дал рамку `#575ec5` **без перезапуска** процесса.

## Ограничения

- Только своя копия темы; исходные файлы в `/usr/share/ulauncher/themes` не
  трогаются.
- Вокруг `.app` остаётся 20 px прозрачной каймы (margin из `UlauncherWindow.ui`)
  — там видна тень окна. Это не наша правка, в CSS её не убрать (margin
  задан в разметке, а не в стилях).
- Заголовки результатов (`matched_text_hl_colors`) живут в `manifest.json` и
  не перекрашиваются: это не CSS, а hex-строки для подсветки совпадений.
- Нужны `ulauncher`, `python3`, `pgrep`, `pkill`, `setsid` — всё из системы.
- Если Ulauncher не запущен, `apply` соберёт тему и напишет в лог, что она
  применится при следующем старте.
