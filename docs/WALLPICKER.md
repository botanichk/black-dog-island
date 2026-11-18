# Выбор обоев шестиугольниками (hypr-wallpicker)

Отдельная программа на C + Raylib: сетка шестиугольников с миниатюрами.
Клик по миниатюре ставит обои и передаёт путь нашему хуку. Заменила
`xfdesktop-settings` как основной способ менять обои; родной настройщик
остался запасным вариантом.

- программа: <https://github.com/Unixcraft-Studios/hypr-wallpicker>
- у нас лежит в `~/src/hypr-wallpicker` (вне репозитория острова)
- бинарник запускается оттуда же, в систему **не ставится**, sudo не нужен

## Как это устроено

```
кнопка на острове (eww/eww.yuck, класс "wall")
  -> adapters/x11/wallpaper.sh      основной путь + запасной
  -> adapters/wallpicker/run.sh     одна копия окна, -c 3, fullscreen
  -> wallpicker (raylib)            сетка шестиугольников, клик мышью
  -> ~/.config/hypr-wallpicker/apply-wallpaper.sh   (ссылка на наш хук)
  -> adapters/wallpicker/apply.sh   xfconf + пересчёт палитры
  -> theme/desktop.sh               правило выбора стола, одно на всех
```

Контракт хука (из `src/apply.c`, не из README): `/bin/sh <хук> <полный путь>
<rel_x> <rel_y>`, запуск в `fork()`, окно выбора не ждёт. `rel_y` считается от
низа окна.

## Сборка

Нужен только `cmake`, `gcc`, `make` и заголовки X11 — всё уже стоит,
установка пакетов не требуется. raylib 6.2 лежит подмодулем и линкуется
статически, системный `raylib` из репозитория **не нужен**.

```sh
git clone https://github.com/Unixcraft-Studios/hypr-wallpicker ~/src/hypr-wallpicker
cd ~/src/hypr-wallpicker
git submodule update --init --depth 1     # vendor/raylib, 98 МБ
make                                       # ~80 с на 4 ядрах
```

Бинарник: `~/src/hypr-wallpicker/wallpicker` (1.3 МБ). `sudo make install` не
делаем: иначе в `/usr/local/bin` появится копия, которая не обновляется
вместе с репозиторием.

Проверено на этой машине: GCC 16.2.1, CMake 4.4.5, OpenGL 4.2 (Mesa Intel HD
4000) — raylib собирается с `GRAPHICS_API_OPENGL_33`, 3.3 хватает.

## Установка хука

```sh
adapters/wallpicker/install.sh      # создаёт ссылку, идемпотентно
adapters/wallpicker/install.sh --remove
```

Ставит `~/.config/hypr-wallpicker/apply-wallpaper.sh` ссылкой на
`adapters/wallpicker/apply.sh`. Ссылка, а не копия: правка хука в проекте
действует сразу. Если по этому пути уже лежит чужой файл, скрипт не затирает
его молча, а просит убрать.

## Что делает хук

1. `xfconf-query` пишет `last-image` для действующего стола. Правило стола —
   в `theme/desktop.sh`: при `/backdrop/single-workspace-mode=true` это стол
   `/backdrop/single-workspace-number` (сейчас 2), иначе текущий
   (`_NET_CURRENT_DESKTOP`). Монитор в ключе не хардкодится: префикс берётся
   из существующих ключей, при пустом профиле — из `xrandr`.
2. Если активна схема «с обоев» (`theme/current = wallpaper`), пересчитывает
   палитру новыми обоями через `theme/from-wallpaper.sh` и перезагружает
   остров. **Обычную палитру не трогает**: если выбрана конкретная палитра,
   смена картинки её не отменяет.
3. Всё пишет в `~/.cache/eww-island/wallpicker.log`, не в stdout (stdout
   принадлежит программе выбора).

Путь не разбирается на слова: он всегда в кавычках, поэтому пробелы,
кириллица, `$()`, `;` в имени файла безопасны (проверено).

## Как проверить

```sh
# окно: открывается на весь экран, остров прячется и возвращается
adapters/wallpicker/run.sh
wmctrl -lG | grep -E 'wallpicker|Eww - '
# Esc закрывает; после закрытия остров снова 373 0 619x50

# хук без клика, на тестовом файле
cp ~/Изображения/буря.jpeg "/tmp/тест обои (1).jpg"
/bin/sh ~/.config/hypr-wallpicker/apply-wallpaper.sh "/tmp/тест обои (1).jpg" 0.5 0.5
xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitorLVDS-1/workspace2/last-image
theme/from-wallpaper.sh --name
tail ~/.cache/eww-island/wallpicker.log
```

## Как вернуться на xfdesktop-settings

```sh
adapters/wallpicker/install.sh --remove    # убрать хук
```

и в `eww/eww.yuck` вернуть `:onclick` кнопки `wall` на путь
`$HOME/eww-island/adapters/x11/wallpaper.sh` без ветки wallpicker — проще
всего временно переименовать `~/src/hypr-wallpicker/wallpicker`: тогда кнопка
сама уйдёт на запасной путь `xfdesktop-settings` (проверено).

## Ограничения, которые стоит знать

- Форматы: только `.png`, `.jpg`, `.jpeg`, без рекурсии по папкам. Файл с
  расширением `.jpeg`, внутри которого WebP, программа не откроет
  (`WARNING: IMAGE: Failed to load image data` в логе) — у владельца такой
  один: `~/Изображения/железный.jpeg`.
- Сетка при умолчании (`-c 5`) шире экрана: 5 колонок по 361 px = 1973 px
  против 1366. Поэтому `run.sh` всегда зовёт `-c 3` (1250 px). Больше колонок
  на 1366x768 не влезает.
- Миниатюры кэшируются в `~/.cache/wallpicker/thumbnails-v2` (31 файл ≈ 10 МБ
  на 32 обои). Первый запуск строит кэш и показывает «Loading».
- Программа не умеет `--help`; флаги: `-c/--cols`, `-s/--spacing`,
  `-a/--angle`, позиционный аргумент — папка.
- На XFCE апстримом не проверялась (только i3). У нас проверено вживую:
  окно открывается, fullscreen работает, хук вызывается.
