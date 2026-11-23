#!/usr/bin/env python3
"""xfconf-xml.py - записать ключ xfconf прямо в XML, без запущенного xfconfd.

usage:
    xfconf-xml.py <канал> <путь> [<значение>] [<тип>]
    xfconf-xml.py xfce4-session /sessions/Failsafe/Client2_Command xfce4-panel string

Зачем: `uninstall` обязан работать, когда сеанса XFCE нет вовсе - владелец
вошёл в Hyprland или в TTY, xfconfd не запущен, а панель надо вернуть.
`xfconf-query` в этом случае либо висит на D-Bus, либо пишет в пустую шину и
теряет значение.

Формат файла - свой у xfconf: вложенные <property name="..." type="..."
value="..."/>. Путь вида /a/b/c ищется как вложенность имён. Ключа нет -
создаётся (включая промежуточные уровни).

Пустое значение удаляет ключ: вернуть настройку туда, где её не было, значит
удалить её.

Тип берётся из аргумента (его пишет журнал: `xfconf-query -v` печатает только
значение, типа не даёт). Без аргумента угадывается по значению: true/false -
bool, целое - int, остальное - string. Угадывать нельзя там, где старое
значение - строка "true": тогда вернулся бы bool, и XFCE не прочитал бы
команду клиента сессии.

Пишем в формате самого xfconf (`version="1.1"`, `/>` без пробела, перевод
строки в конце): иначе файл переписывался бы целиком при каждом откате, и
`restore-backup` не давал бы тех же хэшей, что до установки.

Код 0 - записано, 1 - файл не разобрался, 2 - неверные аргументы.
"""

import os
import sys
import tempfile
import xml.etree.ElementTree as ET


def die(code, msg):
    print(msg, file=sys.stderr)
    raise SystemExit(code)


def main():
    if len(sys.argv) not in (3, 4, 5):
        die(2, "usage: xfconf-xml.py <канал> <путь> [<значение>] [<тип>]")
    channel = sys.argv[1]
    path = sys.argv[2]
    value = sys.argv[3] if len(sys.argv) >= 4 else ""
    ptype = sys.argv[4] if len(sys.argv) == 5 else ""

    if not path.startswith("/"):
        die(2, "путь должен начинаться с /")

    conf = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    xfile = os.path.join(conf, "xfce4", "xfconf", "xfce-perchannel-xml",
                         channel + ".xml")
    if not os.path.isfile(xfile):
        die(1, "нет файла %s" % xfile)

    try:
        tree = ET.parse(xfile)
    except ET.ParseError as exc:
        die(1, "%s: не разобрался (%s)" % (xfile, exc))

    root = tree.getroot()
    names = [p for p in path.split("/") if p]

    parent = root
    for name in names[:-1]:
        found = None
        for child in parent.findall("property"):
            if child.get("name") == name:
                found = child
                break
        if found is None:
            found = ET.SubElement(parent, "property",
                                  {"name": name, "type": "empty"})
        parent = found

    last = names[-1]
    node = None
    for child in parent.findall("property"):
        if child.get("name") == last:
            node = child
            break

    if value == "":
        # Пустое значение = ключа быть не должно.
        if node is not None:
            parent.remove(node)
    else:
        if ptype in ("string", "bool", "int", "uint", "double"):
            pass
        elif value in ("true", "false"):
            ptype = "bool"
        elif value.lstrip("-").isdigit():
            ptype = "int"
        else:
            ptype = "string"
        if node is None:
            node = ET.SubElement(parent, "property")
        node.set("name", last)
        node.set("type", ptype)
        node.set("value", value)

    ET.indent(tree, space="  ")
    body = ET.tostring(root, encoding="unicode").replace(" />", "/>")
    text = ('<?xml version="1.1" encoding="UTF-8"?>\n\n' + body + "\n")

    # Через временный файл: оборванная запись оставила бы пустой XML, и
    # следующий вход в XFCE начал бы с нуля.
    d = os.path.dirname(xfile)
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".bdi-xfconf-")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(text)
        os.chmod(tmp, os.stat(xfile).st_mode & 0o7777)
        os.replace(tmp, xfile)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
