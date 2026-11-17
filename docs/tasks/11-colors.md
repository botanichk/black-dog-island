# Задание 11: выбор цвета — палитры Noctalia и цвета с обоев

Правила как в AGENTS.md. Модель не принимает картинки: проверять цифрами.
Один шаг — один коммит, сообщение по-русски. Тег ставит владелец.

Цель: во вкладке хаба можно выбрать цветовую схему острова —
10 встроенных палитр Noctalia (включая **Noctalia**) в тёмном и светлом
режиме, плюс сгенерировать палитру из обоев текущего рабочего стола.

## Разведка (сделана)

Всё ниже проверено на этой машине, не по документации.

**Noctalia установлена и работает без демона.**
- Пакет `noctalia 5.4.1-1` из extra, бинарник `/usr/bin/noctalia`.
- `ldd` — «все на месте», новых зависимостей не нужно. Ставить ничего не надо.
- `noctalia msg ...` не работает (мы на X11, демона нет: `error: noctalia is not running`),
  но **`noctalia theme <картинка>` работает отдельным вызовом**, без Wayland и без демона.
  Это и есть путь «цвета с обоев».

**Встроенные палитры.**
- В бинарнике их нет строками (проверено: `strings`, поиск по байтам `#fff59b`
  и `ff f5 9b` — ноль совпадений). Они лежат в исходниках:
  `src/theme/builtin_palettes.cpp`.
- Взято из тега **`v5.4.1`** (установленная версия), а не из `main`:
  на `main` палитра Noctalia другая (`#f7e9a8` / `#15162e`), в `v5.4.1` —
  `#fff59b` / `#070722`, что совпадает с `/home/user/radiofm/themes/noctalia-noctalia_default.json`
  (тот проект импортировал их из `Assets/ColorScheme` старой сборки).
- 10 палитр, 16 ролей каждая, тёмная и светлая:
  Ayu, Catppuccin, Dracula, Eldritch, Gruvbox, Kanagawa, **Noctalia**,
  Nord, Rosé Pine, Tokyo-Night.
- Роли в v5.4.1 старые: `surfaceVariant`, `outline` (не `surfaceContainer`/`outlineVariant`).
- Результат извлечения уже лежит в `/tmp/noctalia-5.4.1.json`
  (16 ролей × 10 палитр × 2 режима). Его надо перенести в репозиторий.

**Цвета с обоев.**
- `noctalia theme <img> --scheme <s> --both` печатает JSON с ветками `dark`/`light`,
  по 74 токена в каждой. ~288 мс на запуск (3 замера).
- Работает для JPEG и PNG (проверено на `буря.jpeg` и `Парусник....png`).
- При ошибке: код возврата 1, сообщение в stderr (`failed to load image: cannot open file`),
  **stdout пустой**. Ловить надёжно по пустому stdout.
- Допустимые схемы (из текста ошибки):
  `m3-tonal-spot, m3-content, m3-fruit-salad, m3-rainbow, m3-monochrome,
  vibrant, faithful, soft, dysfunctional, muted`.
  (`m3-fidelity`, `m3-neutral`, `m3-vibrant`, `m3-expressive` — **не существуют**.)

**Обои XFCE.** Путь берётся из `xfconf-query -c xfce4-desktop`:
`/backdrop/screen0/<монитор>/workspace<N>/last-image`. Сейчас заполнены
только workspace0 (`буря.jpeg`) и workspace2 (`Парусник...png`), у остальных
пусто. Монитор в ключе — `monitorLVDS-1`, но имя не гарантировано,
поэтому монитор не хардкодить: перебирать все ключи `last-image` и брать
первый, у которого `workspace<N>` совпадает с текущим столом и значение непустое.
Текущий стол — `xprop -root _NET_CURRENT_DESKTOP`.

**Геометрия.** Кнопка темы в рейле хаба занимает тот же слот 44 px, что и
вкладка. Замена её на 7-ю вкладку не меняет ни высоту рейла, ни окно хаба.
Замерено: элементы рейла y = 65…375 (центры 65/81/98/125/169/213/257/301,
кнопка темы 369), низ окна хаба 408.

## Решения владельца

1. Выбор цвета — **7-я вкладка хаба «Цвета»** вместо кнопки темы в нижнем слоте.
   Остров не трогаем, «Главная» не сдвигается.
2. Внутри вкладки — переключатель режима (тёмная/светлая) и 10 палитр.
3. «С обоев» — обои **текущего рабочего стола**.

## Что сделать

### 1. Палитры в репозиторий: `theme/palettes/*.json`

Новая папка (схемы `theme/schemes/` остаются как есть: `default` и `light`
не удалять, они — эталон вида и запасной вариант).

Формат — 1:1 роли Noctalia v5.4.1, без наших переименований:

```json
{
  "name": "Noctalia",
  "label": "Noctalia",
  "roles": {
    "dark":  { "primary": "#fff59b", "onPrimary": "#0e0e43", "secondary": "#a9aefe", "...": "" },
    "light": { "primary": "#5d65f5", "...": "" }
  }
}
```

16 ролей: `primary, onPrimary, secondary, onSecondary, tertiary, onTertiary,
error, onError, surface, onSurface, surfaceVariant, onSurfaceVariant,
outline, shadow, hover, onHover`.

Файлы: `ayu.json`, `catppuccin.json`, `dracula.json`, `eldritch.json`,
`gruvbox.json`, `kanagawa.json`, `noctalia.json`, `nord.json`,
`rosepine.json`, `tokyo-night.json`. `label` — человекочитаемое
(«Rosé Pine», «Tokyo Night»), `name` — как в Noctalia.

Данные брать из `/tmp/noctalia-5.4.1.json` (он получен разбором
`builtin_palettes.cpp` из тега v5.4.1). Если файла нет — заново скачать
`https://raw.githubusercontent.com/noctalia-dev/noctalia/v5.4.1/src/theme/builtin_palettes.cpp`
и разобрать (структура: `.name = "..."`, затем `.dark`/`.light` →
`.palette = FixedPalette{ ... }`, поля `.primary = hex("#...")`).

### 2. Конвертер: `theme/from-palette.py`

Отдельный скрипт (python3, уже стоит). Читает палитру или JSON от
`noctalia theme`, пишет схему в нашем формате (`colors`/`alphas`/
`weather_gradients`) — ровно то, что ждёт `theme/apply.sh`.

Роли 1:1, где смысл совпадает:
`surface ← surface`, `surface_container ← surfaceVariant`,
`on_surface ← onSurface`, `on_surface_variant ← onSurfaceVariant`,
`primary ← primary`, `error ← error`.

Производные роли (формулы Noctalia, взяты из `src/theme/fixed_palette.cpp`
тега v5.4.1, строки 282–301):

- `surface_high = surfaceVariant`, светлота HSL `+0.04` (тёмная) / `−0.04` (светлая),
  ограничение `min 0.40` / `max 0.60`;
- `surface_highest` — то же с `+0.08`/`−0.08` и `min 0.45`/`max 0.55`;
- `outline ← outline` как есть.

Наши собственные роли (у Noctalia их нет):

- `primary_dim = mix(primary, surface, 0.45)`;
- `on_primary` — из двух (#ffffff / #000000) берём тот, что контрастнее к
  итоговому `primary`;
- `on_primary_dim` — так же для `primary_dim`;
- `on_media = #ffffff` всегда (текст поверх фотографий);
- `weather_cloud`, `weather_snow` — брать из `theme/schemes/default.json`
  (это цвета иллюстраций погоды, от палитры не зависят);
- `alphas` — копировать из `light.json` для светлого режима и из
  `default.json` для тёмного (там разница только в `state_hover`,
  `state_press`, `divider`, `text_shadow`);
- `weather_gradients` — копировать из `default.json` без изменений
  (они не перекрашиваются схемой, см. комментарий `_comment` в файле).

### 3. Подгонка контраста (обязательно, иначе 8 из 10 светлых палитр нечитаемы)

Замерено на реальных местах интерфейса (`$primary` как текст:
день календаря `.cal-today-num`, активная сеть `.wf-net.active .wf-net-name`,
иконка Wi-Fi `.wifi-excellent`; `$primary` как плашка под глифом
`.hub-tab-btn.active .hub-ic`):

| палитра | режим | primary как текст | глиф на плашке | вердикт |
|---|---|---|---|---|
| Ayu | light | 2.15 | 2.15 | мало |
| Eldritch | light | 2.59 | 5.62 | мало |
| Gruvbox | light | 2.73 | 2.73 | мало |
| Kanagawa | light | 3.26 | 3.26 | мало (сеть 2.85) |
| Noctalia | light | 3.72 | 3.37 | мало |
| Nord | light | 3.50 | 3.50 | мало |
| Rosé Pine | light | — | — | мало |
| Tokyo-Night | light | — | — | мало |
| все 10 тёмных | dark | ≥ 4.8 | ≥ 4.8 | ок |

Правило: если `primary` даёт к `surface` меньше 4.5, **уменьшать светлоту
в HSL** (оттенок и насыщенность целы), шаг 1 %, пока не дойдёт до 4.5.
После подгонки `on_primary` пересчитать (взять контрастнейший из
#ffffff/#000000).

Результат подгонки (проверено, все ≥ 4.5):

| палитра | было (light) | стало | L |
|---|---|---|---|
| Ayu | `#FF8F40` | `#bf4f00` | −40 % |
| Eldritch | `#fb5bb6` | `#d6057c` | −36 % |
| Gruvbox | `#98971a` | `#727113` | −25 % |
| Kanagawa | `#6f894e` | `#5b7040` | −18 % |
| Noctalia | `#5d65f5` | `#4a53f4` | −6 % |
| Nord | `#5e81ac` | `#4e6f97` | −14 % |
| Rosé Pine | `#d7827e` | `#c54b45` | −22 % |
| Tokyo-Night | `#2e7de9` | `#1560c7` | −21 % |

Тёмные палитры не трогаются (сдвиг 0 %).

Дополнительно проверить и подогнать `primary_dim`: он работает и как текст
(`.wifi-good`, `.wifi-ok`), и как плашка под текстом (`.cal:selected`).
Проверено: для всех 20 вариантов цвет находится; критерий — `≥ 4.5` под
текстом и `≥ 3.0` к `surface`, двигать смешением к подогнанному `on_surface`.

`error` как фон (`.wf-btn.danger`): текст берётся из `on_primary`, и у
палитр Noctalia это может дать 2.9–4.1. Поэтому для `error` выбрать
чернила отдельно: контрастнейший из #ffffff/#000000 к `error`, а не
переиспользовать `on_primary`. (В M3-пути «с обоев» проблемы нет:
там `error` даёт 6.2–12.4 с лучшими чернилами.)

### 4. Цвета с обоев: `theme/from-wallpaper.sh`

`usage: theme/from-wallpaper.sh [схема] [--reload]`

1. Взять обои текущего стола:
   ```
   ws=$(xprop -root _NET_CURRENT_DESKTOP | sed 's/.*= *//')
   xfconf-query -c xfce4-desktop -l | grep "workspace${ws}/last-image$"
   ```
   → первое непустое значение.
   Если обоев нет (стол пустой) — **не падать**: попробовать `workspace0`,
   если и там пусто — выйти с кодом 3 и текстом
   «у этого рабочего стола нет обоев в настройках XFCE».
2. `noctalia theme "$WALL" --scheme "${1:-m3-tonal-spot}" --both`,
   stdout пустой → ошибка (код 1), печатать stderr `noctalia`.
3. Отдать JSON конвертеру (п. 2), получить схему,
   записать `theme/schemes/wallpaper.json`.
4. `theme/apply.sh wallpaper [--reload]`.

Схема одна (`wallpaper`), потому что обои меняются чаще, чем хочется
плодить файлы. Режим (тёмная/светлая) берётся из переключателя вкладки.

### 5. Хранилище выбора: `theme/current` и `theme/mode`

- `theme/current` уже есть (одна строка, имя схемы). Значения:
  `default`, `light`, `wallpaper` или `p-<палитра>` (например `p-noctalia`).
- Новый файл `theme/mode` — `dark`/`light`. Нужен, потому что одна и та же
  палитра даёт две схемы, а `theme/current` хранит только имя файла.
- Схемы палитр генерируются в `theme/schemes/p-<имя>.json` конвертером
  (в git не кладём — они выводятся из `theme/palettes/`; добавить
  `theme/schemes/p-*.json` и `theme/schemes/wallpaper.json` в `.gitignore`).

### 6. `theme/colors-pick.sh` — одна точка входа для UI

`usage: theme/colors-pick.sh palette <имя> <dark|light> | wallpaper <dark|light> | mode <dark|light> | reset`

- `palette` → `from-palette.py theme/palettes/<имя>.json --mode light` →
  `theme/schemes/p-<имя>.json` → `apply.sh p-<имя>` → записать `mode`.
- `wallpaper` → `from-wallpaper.sh` с нужным режимом.
- `mode` → перегенерировать текущую схему в другом режиме
  (без потери выбора палитры).
- `reset` → `apply.sh default`, `mode=dark`.
- Все ветки заканчиваются переоткрытием хаба на вкладке «Цвета» —
  иначе `reload` закроет окно и сбросит `hub_tab` (проверено в шаге 09;
  в `switch.sh` это уже сделано, взять оттуда тот же приём).

### 7. Интерфейс: 7-я вкладка «Цвета»

**Рейл.** Кнопку `hub-theme-btn` (eww.yuck, ~298) заменить на
`(hub-tab-btn :idx 6 :glyph "󰏘")`.
`hub_tab = 6`. `hub-rail-gap` остаётся как есть — вкладка уже стоит
после растяжки, внизу.

`adapters/x11/panel.sh`: в `tab_index()` добавить `colors) echo 6 ;;`.
`theme/switch.sh`: в разборе `idx` → имя вкладки добавить `6) tab=colors ;;`
(иначе после переключения хаба откроется не та вкладка).

**Вкладка** — новый `defwidget colors-content` в `eww.yuck`:

```
box.colors-panel (vertical, hexpand, vexpand)
  label.colors-title "Цвет острова"
  box.colors-mode (horizontal)          — два сегмента: Тёмная / Светлая
  label.colors-sec "Палитры"
  box.colors-grid (vertical)
    for p in ...  — по 2 карточки в строке (5 строк)
  label.colors-sec "С обоев"
  button.colors-wall — имя обоев + кнопка «Подобрать цвет»
```

Карточка палитры (`defwidget palette-card [name label]`):
- превью из четырёх цветов палитры (surface, surfaceVariant, primary, secondary)
  как четыре `box` с `:css "background-color: ..."` **или** готовые SVG;
- подпись `label`.

Клик → `theme/colors-pick.sh palette <name> <режим>`.
Активная карточка получает класс `active` (плашка `$primary`, как у
вкладок) — состояние читается из `defpoll colors-now :interval "3s"
"cat theme/current theme/mode"`.

Режим (тёмная/светлая) — два сегмента, активный с классом `active`.

**Важно про `:css`.** Он компилируется как есть, но **не обновляется**
после первой отрисовки; `@import` внутри него невозможен (см. комментарий
в eww.yuck ~358). Для превью палитр это допустимо: цвета палитры не
зависят от активной схемы — их можно подставить литералами из
`theme/palettes/*.json` прямо на этапе сборки. Но тогда `eww.yuck` должен
генерироваться… **проще: превью рисовать SVG**, как уже делают иконки:
`theme/apply.sh` рендерит `theme/templates/palettes/<имя>.svg` с четырьмя
цветными прямоугольниками. Тогда превью меняется вместе со схемой и не
требует `:css`. Если владелец согласится на вариант «превью не
перекрашивается» — можно `:css`, это дешевле. **Решение вынести в
открытые вопросы.**

**Размер окна.** Вкладка обязана заполнять область справа от рейла по
ширине и высоте (`:hexpand true :vexpand true` по всей цепочке
`panel-frame → hub-panel → stack → scroll → box.hub-tab → colors-content`),
как требует закон вкладок из AGENTS.md. Ширина хаба 619 px, под рейл
уходит ~48 px → на сетку остаётся ~560 px.

### 8. Документация

- `docs/THEME.md`: добавить раздел «Палитры и обои» — откуда взяты
  10 палитр (тег v5.4.1), почему светлые подгоняются по контрасту
  (таблица выше), как позвать `colors-pick.sh`.
- `docs/tasks/00-README.md`: строка про задание 11.
- `docs/SPEC-hub.md` / `docs/ROADMAP.md`: отметить шаг, если там есть очередь.

## Проверка (только цифрами)

1. `theme/apply.sh p-noctalia` → `eww logs` без ошибок, `git status` чистый
   после повторного прогона (идемпотентность).
2. Пиксели: при `p-noctalia` (тёмная) тело острова = `#070722` → `7,7,34`;
   при светлой = `#e6e8fa` → `230,232,250`.
   Команда: `import -window root -crop 1x1+X+Y +repage txt:-`.
3. Плашка активной вкладки = `primary` подогнанной палитры.
4. Все 20 вариантов: посчитать контраст `primary`/`surface` из
   сгенерированных `theme/schemes/p-*.json` — скриптом, не глазами;
   минимум ≥ 4.5.
5. Геометрия: `wmctrl -lG | grep 'Eww - '` — остров по-прежнему
   `373 0 619 50`, хаб `373 50 619 358`, вкладок в рейле 7, низ последней
   ≤ 408.
6. «С обоев»: запустить `from-wallpaper.sh` на текущем столе, проверить
   что `theme/schemes/wallpaper.json` появился и `theme/current` = `wallpaper`.
7. Пустой стол: переключиться на workspace1 (там обоев нет) — скрипт
   должен вернуть код 3 и текст, а не молча испортить тему.
   **Не переключать столы во время проверки, если владелец работает
   рядом** — спросить разрешение заранее.

В отчёт: `владельцу проверить глазами: вид вкладки «Цвета», превью палитр,
читаемость активной карточки, стык хаба с островом после смены палитры`.

## Открытые вопросы

1. **Превью палитр**: SVG из шаблонов (перекрашивается, дороже,
   ~10 новых SVG) или `:css` с литералами (дешевле, но превью не
   обновляется после первой отрисовки и не следует активной схеме)?
   Рекомендую SVG — иначе карточки будут спорить с активной темой.
2. **Где живут сгенерированные схемы**: в git (`theme/schemes/p-*.json`,
   чтобы вид воспроизводился без `noctalia`) или в `.gitignore`
   (генерируются на месте)? Рекомендую `.gitignore` — тогда проект
   не зависит от установленной Noctalia, но выбор палитры требует
   одного запуска конвертера.
3. **Список m3-схем для обоев**: показывать все 10
   (`m3-tonal-spot`, `m3-content`, `m3-fruit-salad`, `m3-rainbow`,
   `m3-monochrome`, `vibrant`, `faithful`, `soft`, `dysfunctional`, `muted`)
   или только 3–4 разумных? Рекомендую 4: `m3-tonal-spot`, `vibrant`,
   `soft`, `muted`.
