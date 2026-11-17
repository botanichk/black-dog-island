# Задание 11: выбор цвета — палитры Noctalia, свои палитры и цвета с обоев

Правила как в AGENTS.md. Модель не принимает картинки: проверять цифрами.
Один шаг — один коммит, сообщение по-русски. Тег ставит владелец.

Цель: во вкладке хаба можно выбрать цветовую схему острова —
10 встроенных палитр Noctalia (включая **Noctalia**), **свои палитры
пользователя** и сгенерировать палитру из обоев текущего рабочего стола.

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
  (тот проект импортировал их из старой сборки Noctalia).
- 10 палитр, 16 ролей каждая, тёмная и светлая:
  Ayu, Catppuccin, Dracula, Eldritch, Gruvbox, Kanagawa, **Noctalia**,
  Nord, Rosé Pine, Tokyo-Night.
- Роли в v5.4.1 старые: `surfaceVariant`, `outline` (не `surfaceContainer`/`outlineVariant`).
- Результат извлечения уже лежит в `/tmp/noctalia-5.4.1.json`
  (16 ролей × 10 палитр × 2 режима). Его надо перенести в репозиторий.

**Свои палитры — формат уже есть, учить владельца ничему не надо.**
- Noctalia читает пользовательские палитры из `~/.config/noctalia/palettes/*.json`
  (проверено по `src/theme/custom_palettes.cpp`, функция `customPaletteDir()`;
  в документации v5.4.1: `source = "custom"`, `custom_palette = "<имя>"`).
- Формат: `{ "dark": { "mPrimary": "#...", ... }, "light": { ... } }`.
  Ключи с префиксом `m` и без него равнозначны — `readPaletteJson` в
  `theme_service.cpp` сначала ищет `mPrimary`, потом `primary`.
  **Если ветки `light` нет — берётся `dark` для обоих режимов** (проверено там же).
- 16 полей: `primary, onPrimary, secondary, onSecondary, tertiary, onTertiary,
  error, onError, surface, onSurface, surfaceVariant, onSurfaceVariant,
  outline, shadow, hover, onHover`. `terminal` — необязателен для нас.
- В `~/.local/state/noctalia/community-palettes/` уже лежит **114 палитр**
  каталога Noctalia (локально скачано 41 файл). Это чужой каталог, не «свои»:
  **в интерфейс их не тянем** (иначе сетка на 114 карточек). Но формат тот же,
  поэтому любая из них, скопированная в `~/.config/noctalia/palettes/`,
  сразу появится на острове.

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

## Решения владельца

1. Выбор цвета — **7-я вкладка хаба «Цвета»** вместо кнопки темы в нижнем слоте.
   Остров не трогаем, «Главная» не сдвигается.
2. Внутри вкладки — переключатель режима (тёмная/светлая) и список палитр.
3. «С обоев» — обои **текущего рабочего стола**.
4. **Превью показывает только один вариант палитры — тот, что соответствует
   выбранному режиму.** Не 20 карточек, а 10 (плюс свои): нажал «светлая» —
   карточки перекрасились в светлые варианты и применился светлый.
5. **Нужны пользовательские темы.**

## Геометрия (замерено и посчитано)

Окно хаба `619×358` (замер `wmctrl`). Дальше — расчёт по CSS проекта:

```
окно хаба                     619
.panel-frame padding 12+12    -24  -> тело 595
рейл 8+40+4 + margin 6        -58  -> стек 537
.hub-tab padding 14+14        -28  -> контент вкладки 509
```

Вертикаль: `.hub-tab-body` = 358, минус padding вкладки 2×14 → **330 px**
полезной высоты. Рейл: `358 − 10 − 16 = 332`; 7 вкладок по 44 px = 308,
**запас 24 px** — 7-я вкладка встаёт на место кнопки темы без изменения окна.

Раскладка вкладки (числа расчётные, на проверке замерить):

| блок | высота |
|---|---|
| ряд «Цвет острова» + сегменты Тёмная/Светлая | 28 |
| отступ | 10 |
| **прокручиваемая часть** (vexpand), вьюпорт | 246 |
| отступ | 8 |
| ряд «С обоев» (чипы схем + кнопка) | 38 |
| **итого** | **330** |

Внутри прокрутки:
- подпись «Встроенные» 15 + 4;
- сетка 3 колонки × 4 строки: карточка `(509 − 2·6)/3 = 165 px` шириной,
  38 px высотой → `4·38 + 3·6 = 170`;
- подпись «Свои» 15 + 4; сетка 2 колонки (карточка `(509 − 6)/2 = 251 px`),
  по 38 px на строку.

Итог при 10 встроенных и одной строке своих: `19 + 170 + 10 + 19 + 38 = 256`
против 246 — прокрутка на 10 px. Это нормально: `scroll` во вкладке уже есть
(как в Wi-Fi). При большем числе своих палитр вкладка просто прокручивается,
остальные блоки не съезжают.

**Почему 3 колонки для встроенных и 2 для своих.** Замер ширины имён
шрифтом Noto Sans 11 px (`convert -font ... label:`): `Tokyo Night` 63 px,
`Catppuccin` 59 px, `Kanagawa` 55 px. В карточке 165 px под имя остаётся
~112 px — встроенные имена влезают. У своих имена произвольные:
`Catppuccin Frappe Mauve` 136 px, `Rose Pine Moon Alt` 101 px — при 2 колонках
под имя 196 px, влезает всё. Длиннее — обрезается через `:limit-width 32`.

## Что сделать

### 1. Встроенные палитры: `theme/palettes/*.json`

Формат — 1:1 роли Noctalia v5.4.1, без наших переименований:

```json
{
  "name": "Noctalia",
  "label": "Noctalia",
  "roles": {
    "dark":  { "primary": "#fff59b", "onPrimary": "#0e0e43", "...": "" },
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

Данные брать из `/tmp/noctalia-5.4.1.json`. Если файла нет — скачать
`https://raw.githubusercontent.com/noctalia-dev/noctalia/v5.4.1/src/theme/builtin_palettes.cpp`
и разобрать (`.name = "..."`, затем `.dark`/`.light` → `.palette = FixedPalette{...}`,
поля `.primary = hex("#...")`).

`theme/schemes/default.json` и `light.json` **не удалять** — эталон вида
и запасной вариант.

### 2. Свои палитры: `~/.config/noctalia/palettes/*.json`

Ничего не изобретаем: читаем тот же каталог, что и Noctalia, тем же форматом.
Пользователь кладёт туда файл — палитра появляется на острове. Файлы
Noctalia в репозиторий не копируем (это пользовательские данные).

Требования к чтению:
- имя палитры — имя файла без `.json` (`%20` раскодировать в пробел);
- ключи с префиксом `m` и без — принимать оба (`mPrimary` / `primary`);
- нет ветки `light` → брать `dark` для обоих режимов (как делает Noctalia);
- битый/неполный файл — **пропустить с сообщением в stderr**, не ронять
  список (иначе один кривой файл убьёт вкладку);
- id схемы — ASCII-slug из имени (`[a-z0-9-]`), потому что имя попадает
  в `theme/current` и в комментарий `// Scheme:` файла `eww/colors.scss`,
  а тот обязан быть ASCII (иначе SCSS-компилятор вставляет `@charset`,
  и GTK выбрасывает весь stylesheet — проверено в шаге 08).

Отдельного «пустого состояния» не нужно: если своих палитр нет,
блок «Свои» просто не рисуется.

### 3. Конвертер: `theme/palette_lib.py` + `theme/palette2scheme.py`

`palette_lib.py` — общая библиотека (ею пользуются конвертер и список):
разбор палитры (оба формата: наш `roles` и Noctalia `dark`/`light`),
HSL-хелперы, `contrast`, `ensure_contrast`, сборка схемы.

`palette2scheme.py` — печатает схему в нашем формате
(`colors`/`alphas`/`weather_gradients`) на stdout. Роли 1:1, где смысл совпадает:

| Noctalia | наше |
|---|---|
| `surface` | `surface` |
| `surfaceVariant` | `surface_container` |
| `onSurface` | `on_surface` |
| `onSurfaceVariant` | `on_surface_variant` |
| `primary` | `primary` |
| `error` | `error` |
| `outline` | `outline` |

Производные (формулы Noctalia из `src/theme/fixed_palette.cpp` тега v5.4.1,
строки 282–301):

- `surface_high` = `surfaceVariant`, светлота HSL `+0.04` (тёмная) / `−0.04`
  (светлая), ограничение `min 0.40` / `max 0.60`;
- `surface_highest` — то же с `+0.08` / `−0.08` и `min 0.45` / `max 0.55`.

Наши собственные роли (у Noctalia их нет):

- `primary_dim = mix(primary, surface, 0.45)`;
- `on_primary` — из `#ffffff` / `#000000` берём контрастнейший к итоговому `primary`;
- `on_primary_dim` — так же для `primary_dim`;
- `on_media = #ffffff` всегда (текст поверх фотографий);
- `weather_cloud`, `weather_snow` — из `theme/schemes/default.json`
  (цвета иллюстраций погоды, от палитры не зависят);
- `alphas` — из `light.json` для светлого режима и из `default.json` для тёмного
  (там разница только в `state_hover`, `state_press`, `divider`, `text_shadow`);
- `weather_gradients` — из `default.json` без изменений (схемой не перекрашиваются,
  см. `_comment` в файле).

### 4. Подгонка контраста (обязательно)

Замерено на реальных местах интерфейса: `$primary` как **текст** —
день календаря `.cal-today-num`, активная сеть `.wf-net.active .wf-net-name`,
иконка Wi-Fi `.wifi-excellent`; `$primary` как **плашка** под глифом —
`.hub-tab-btn.active .hub-ic`.

10 встроенных, `primary`/`surface` (минимум из трёх мест):

| палитра | тёмная | светлая | вердикт |
|---|---|---|---|
| Ayu | 10.13 | **2.15** | светлая не читается |
| Catppuccin | 8.07 | 4.79 | ок |
| Dracula | 5.90 | 5.28 | ок |
| Eldritch | 10.71 | **2.59** | светлая не читается |
| Gruvbox | 7.14 | **2.73** | светлая не читается |
| Kanagawa | 4.84 | **2.85** | светлая не читается |
| Noctalia | 17.68 | **3.37** | светлая не читается |
| Nord | 5.99 | **3.50** | светлая не читается |
| Rosé Pine | 10.45 | **<3.0** | светлая не читается |
| Tokyo-Night | 6.79 | **<3.0** | светлая не читается |

**8 из 10 светлых не проходят.** Правило: если `primary` даёт к `surface`
меньше 4.5, **уменьшать светлоту в HSL** (оттенок и насыщенность целы),
шаг 1 %, пока не дойдёт до 4.5. После подгонки `on_primary` пересчитать.
Гасить смешением к `on_surface` нельзя: Ayu из оранжевого становится
серо-коричневым (`#FF8F40`→`#996846`), а спуск по светлоте сохраняет цвет
(`#bf4f00`).

Результат (все ≥ 4.5, тёмные не двигаются):

| палитра | было (light) | стало | ΔL |
|---|---|---|---|
| Ayu | `#FF8F40` | `#bf4f00` | −40 % |
| Eldritch | `#fb5bb6` | `#d6057c` | −36 % |
| Gruvbox | `#98971a` | `#727113` | −25 % |
| Kanagawa | `#6f894e` | `#5b7040` | −18 % |
| Noctalia | `#5d65f5` | `#4a53f4` | −6 % |
| Nord | `#5e81ac` | `#4e6f97` | −14 % |
| Rosé Pine | `#d7827e` | `#c54b45` | −22 % |
| Tokyo-Night | `#2e7de9` | `#1560c7` | −21 % |

Проверено на **произвольных** палитрах, а не только на встроенных: прогнаны
все 41 локально скачанных community-палитры Noctalia, оба режима —
**82 из 82** доходят до контраста 4.5. Значит правило работает для «своих»
и для обоев, а не подогнано под 10 имён.

Отдельно:
- `primary_dim` работает и как текст (`.wifi-good`, `.wifi-ok`), и как плашка
  под текстом (`.cal:selected`). Критерий: `≥ 4.5` под текстом и `≥ 3.0`
  к `surface`; двигать смешением к подогнанному `on_surface`. Проверено —
  для всех 20 вариантов цвет находится.
- `error` как фон (`.wf-btn.danger`): текст берётся из `on_primary`, и у
  встроенных палитр это даёт 2.9–4.1. Поэтому чернила для `error` выбирать
  отдельно — контрастнейший из `#ffffff` / `#000000` к `error`.
  (В M3-пути «с обоев» проблемы нет: 6.2–12.4.)
- `outline` менять нельзя: это рамки и разделители (`menu` border,
  `menu separator`), у нас он и сейчас 1.41 в тёмной. Порог 3.0 к нему не применяем.

### 5. Цвета с обоев: `theme/from-wallpaper.sh`

`usage: theme/from-wallpaper.sh [схема] [режим] [--reload]`

1. Взять обои текущего стола:
   ```
   ws=$(xprop -root _NET_CURRENT_DESKTOP | sed 's/.*= *//')
   xfconf-query -c xfce4-desktop -l | grep "workspace${ws}/last-image$"
   ```
   → первое непустое значение.
   Нет обоев у стола → попробовать `workspace0`; нет и там → **код 3**
   и текст «у этого рабочего стола нет обоев в настройках XFCE».
2. `noctalia theme "$WALL" --scheme "${1:-m3-tonal-spot}" --both`,
   stdout пустой → ошибка (код 1), печатать stderr Noctalia.
3. JSON → выбранная ветка → `palette2scheme.py` → `theme/schemes/wallpaper.json`.
4. `theme/apply.sh wallpaper [--reload]`.

Схема одна (`wallpaper`): обои меняются чаще, чем хочется плодить файлы.
Режим берётся из переключателя вкладки.

### 6. Хранилище выбора: `theme/current` и `theme/mode`

- `theme/current` уже есть (одна строка, имя схемы). Значения:
  `default`, `light`, `wallpaper`, `p-<слаг>` (встроенная, напр. `p-noctalia`)
  или `u-<слаг>` (своя).
- Новый файл `theme/mode` — `dark` / `light`. Нужен потому, что одна палитра
  даёт две схемы, а `theme/current` хранит только имя файла.
- Сгенерированные схемы `theme/schemes/p-*.json`, `u-*.json`, `wallpaper.json`
  в git **не кладём** — они выводятся из палитр. Добавить в `.gitignore`.

### 7. `theme/colors-list.sh` — данные для вкладки

Печатает JSON-массив для `(for ...)` в yuck, цвета уже под режим из `theme/mode`:

```json
[{"id":"p-noctalia","label":"Noctalia","c1":"#070722","c2":"#11112d","c3":"#fff59b","cur":1}]
```

- `c1` surface, `c2` surfaceVariant, `c3` primary (после подгонки контраста),
  `cur` = 1 у активной схемы (сверять по `theme/current`).
- Источники: `theme/palettes/*.json` (встроенные, `id = p-<слаг>`)
  и `~/.config/noctalia/palettes/*.json` (свои, `id = u-<слаг>`).
- Дешёвый (python, 10–50 файлов, ~30 мс), опрос раз в 5 с, пока хаб открыт.

### 8. `theme/colors-pick.sh` — одна точка входа для UI

`usage: theme/colors-pick.sh palette <id> | wallpaper <m3-схема> | mode <dark|light> | reset`

- `palette <id>` → конвертер → `theme/schemes/<id>.json` → `apply.sh <id>`
  → записать `theme/current`.
- `wallpaper <m3>` → `from-wallpaper.sh` с режимом из `theme/mode`.
- `mode dark|light` → записать `theme/mode`, **перегенерировать текущую схему
  в другом режиме** (выбор палитры не теряется). Если текущая —
  `default`/`light` (эталон из шага 09), вести себя как раньше: `light` ↔ `default`.
- `reset` → `apply.sh default`, `mode=dark`.
- Все ветки заканчиваются переоткрытием хаба **на вкладке «Цвета»**: `reload`
  закрывает окно и сбрасывает `hub_tab` на 0. Приём уже отработан в
  `theme/switch.sh` (закрыть → дождаться → `panel.sh panel-hub colors`) —
  взять оттуда.

### 9. Интерфейс: 7-я вкладка «Цвета»

**Рейл.** Кнопку `hub-theme-btn` (eww.yuck ~298) заменить на
`(hub-tab-btn :idx 6 :glyph "󰏘")` — глиф палитры U+F03D8, проверено:
есть в MesloLGSDZ Nerd Font (`convert` дал 672 непрозрачных пикселя).
`hub_tab = 6`, `hub-rail-gap` остаётся перед ней — вкладка внизу колонки.

`defpoll theme-now` (yuck:7) после этого не используется — удалить
(или перевести на `theme/mode`, если понадобится индикатор).

`adapters/x11/panel.sh`: в `tab_index()` добавить `colors) echo 6 ;;`.
`theme/switch.sh`: в разборе `idx` → имя вкладки добавить `6) tab=colors ;;`.
(`switch.sh` остаётся как CLI-переключатель, кнопки на него больше нет.)

**Вкладка** — новый `defwidget colors-content`:

```
box.colors-panel (vertical, hexpand, vexpand)
  box.colors-head (horizontal)
    label.colors-title "Цвет острова"
    box.colors-mode (horizontal)      — Тёмная / Светлая, активный .active
  scroll.colors-scroll (vscroll, vexpand)
    label.colors-sec "Встроенные"
    box.colors-grid-3                 — 3 колонки, карточки p-*
    [label.colors-sec "Свои" + box.colors-grid-2]   — только если свои есть
  box.colors-wall (horizontal)
    label «С обоев»
    чипы m3-схем (4 штуки)
    button «Подобрать»
```

**Карточка палитры** (`defwidget palette-card [id label c1 c2 c3 cur]`),
высота 38 px: кнопка с классом `palette-card` / `palette-card active`;
внутри три `box` шириной `hexpand` и высотой 8 px с `:style "background-color: ${c1}"`
и т.д., ниже `label` с `:limit-width 32`.

`:style` в **нашей** сборке Eww перезагружается при каждом изменении
(`widget_definitions.rs:212-217`: `reset_style()` + `load_from_data` при
каждом присваивании) — поэтому превью перекрашивается при смене режима
и не требует 10 новых SVG. `:css` для этого не годится (в нём нет `@import`,
см. комментарий в yuck ~358), но он и не нужен.

Клик по карточке → `theme/colors-pick.sh palette <id>`.
Клик по «Тёмная»/«Светлая» → `theme/colors-pick.sh mode dark|light`.
Клик по «Подобрать» → `theme/colors-pick.sh wallpaper <выбранная m3>`.

**Закон вкладок** (AGENTS.md): `:hexpand true :vexpand true` по всей цепочке
`panel-frame → hub-panel → stack → scroll → box.hub-tab → colors-content`.
Размер окна от вкладки не зависит.

### 10. Документация

- `docs/THEME.md`: раздел «Палитры, свои палитры и обои» — откуда взяты
  10 палитр (тег v5.4.1), почему светлые гасятся по светлоте (таблица выше),
  как положить свою палитру (`~/.config/noctalia/palettes/<Имя>.json`) и
  почему id приводится к ASCII, как позвать `colors-pick.sh`.
- `docs/tasks/00-README.md`: строка про задание 11.
- `docs/SPEC-hub.md` / `docs/ROADMAP.md`: отметить шаг в очереди.

## Проверка (только цифрами)

1. `theme/apply.sh p-noctalia` → `eww logs` без ошибок, повторный прогон
   даёт `git status` чистый (идемпотентность).
2. Пиксели: `p-noctalia` тёмная → тело острова `#070722` = `7,7,34`;
   светлая → `#e6e8fa` = `230,232,250`.
   Команда: `import -window root -crop 1x1+X+Y +repage txt:-`.
3. Плашка активной вкладки = подогнанный `primary` палитры.
4. Все палитры и режимы: посчитать контраст `primary`/`surface` из
   сгенерированных `theme/schemes/*.json` скриптом — минимум `≥ 4.5`.
5. Геометрия: `wmctrl -lG | grep 'Eww - '` — остров `373 0 619 50`,
   хаб `373 50 619 358`; в рейле 7 элементов, низ последнего `≤ 408`.
6. Своя палитра: положить временный файл в `~/.config/noctalia/palettes/`,
   убедиться, что появился в списке и применяется; **убрать файл после
   проверки**. Битый JSON — пропускается, остальные на месте.
7. «С обоев»: `from-wallpaper.sh` на текущем столе → `theme/schemes/wallpaper.json`
   есть, `theme/current` = `wallpaper`.
8. Пустой стол (workspace1): код 3 и текст, тема не испорчена.
   **Не переключать столы, если владелец работает рядом** — спросить заранее.

В отчёт: `владельцу проверить глазами: вид вкладки «Цвета», превью палитр
в тёмном и светлом режиме, читаемость активной карточки, стык хаба с островом
после смены палитры`.

## Открытые вопросы

1. **Свои палитры: откуда берём.** Предлагаю `~/.config/noctalia/palettes/*.json`
   (тот же формат и место, что у Noctalia — владельцу не надо учить новый
   формат, палитры общие с Hyprland-сессией). Альтернатива — своя папка
   `theme/palettes/user/` в репозитории: тогда палитры попадают в git,
   но дублируют Noctalia. Рекомендую первое.
2. **Community-каталог** (114 палитр в `~/.local/state/noctalia/community-palettes/`)
   в интерфейс не тянуть — иначе сетка на 114 карточек и вкладка превратится
   в простыню. Но если хочется, можно отдельной кнопкой «Ещё палитры…».
   Рекомендую не тянуть сейчас.
3. **Сколько m3-схем** для обоев показывать: все 10 или 4 разумных
   (`m3-tonal-spot`, `vibrant`, `soft`, `muted`)? На 10 чипов в ряду
   «С обоев» не хватит 509 px. Рекомендую 4.
4. **Схемы палитр в git или `.gitignore`?** Рекомендую `.gitignore`:
   проект не зависит от установленной Noctalia, но выбор палитры требует
   одного прогона конвертера.
