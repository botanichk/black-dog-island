#!/usr/bin/env python3
# Интеллектуальное скрытие острова.
#
# Зачем: остров - dock-окно вверху экрана, он перекрывает содержимое
# развёрнутых окон (браузер, видео). Скрипт следит за активным окном и
# убирает остров, когда активное окно накрывает его прямоугольник.
#
# Поведение:
#   * активное окно перекрывает остров -> от острова остаётся полоска
#     STRIP px на всю ширину (XShape), как у автоскрытой панели XFCE;
#   * активное окно ушло/свернулось/перекрытия нет -> остров возвращается;
#   * остров свёрнут в полоску, но курсор подведён к верхней кромке ->
#     остров показывается и остаётся, пока курсор внутри него;
#   * если активное окно во весь экран (видео, игра), полоска тоже
#     исчезает (пустая форма) и наведение остров не вытаскивает;
#   * открыта любая панель Eww (погода/календарь/wifi) -> остров не прячем,
#     иначе панель останется висеть без острова;
#   * есть файл-флаг autohide-off -> автоскрытие выключено, остров всегда виден.
#
# Почему не wmctrl: xfwm4 игнорирует перемещение/скрытие dock-окна через
# wmctrl (позиция пинится), а обрезка по форме через XShape работает и не
# трогает ни XID, ни геометрию, ни _NET_CLIENT_LIST.
#
# usage: island-autohide.py            запустить в фоне (демон)
#        island-autohide.py start      то же (для run-island.sh)
#        island-autohide.py stop       остановить, вернуть остров
#        island-autohide.py restore    показать остров, если он скрыт
#        island-autohide.py status     состояние (для отладки)
#        island-autohide.py once       один шаг, печать решения, без изменений
#        island-autohide.py watch      цикл с печатью каждого шага (отладка)
#        island-autohide.py off|on     выключить/включить автоскрытие
#        island-autohide.py toggle     переключить автоскрытие
import ctypes
import ctypes.util
import os
import signal
import sys
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
CONF = os.path.join(ROOT, "eww")

CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")), "eww-island")
PIDFILE = os.path.join(CACHE, "autohide.pid")
LOGFILE = os.path.join(CACHE, "autohide.log")
OFFFILE = os.path.join(CACHE, "autohide-off")
DEBUG = bool(os.environ.get("ISLAND_AUTOHIDE_DEBUG"))

TICK = 0.25       # период опроса, с
EDGE = 3          # полоса у верхней кромки, которая показывает остров, px
DWELL = 0.25      # сколько держать курсор в полосе, чтобы остров вышел, с
LEAVE = 0.45      # пауза перед скрытием после ухода курсора, с
STRIP = 2         # высота полоски, остающейся от острова при скрытии, px

IS_VIEWABLE = 2   # map_state в XWindowAttributes: 0=скрыто, 2=на экране

# --- Xlib через ctypes: ни xdotool, ни python3-xlib в системе нет ---
lib = ctypes.CDLL(ctypes.util.find_library("X11") or "libX11.so.6")

Display = ctypes.c_void_p
Window = ctypes.c_ulong
Atom = ctypes.c_ulong

lib.XOpenDisplay.restype = Display
lib.XOpenDisplay.argtypes = [ctypes.c_char_p]
lib.XDefaultRootWindow.restype = Window
lib.XDefaultRootWindow.argtypes = [Display]
lib.XInternAtom.restype = Atom
lib.XInternAtom.argtypes = [Display, ctypes.c_char_p, ctypes.c_int]
lib.XGetWindowProperty.restype = ctypes.c_int
lib.XGetWindowProperty.argtypes = [
    Display, Window, Atom, ctypes.c_long, ctypes.c_long, ctypes.c_int, Atom,
    ctypes.POINTER(Atom), ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_ulong),
    ctypes.POINTER(ctypes.c_ulong), ctypes.POINTER(ctypes.POINTER(ctypes.c_ubyte))]
lib.XFree.argtypes = [ctypes.c_void_p]
lib.XQueryPointer.argtypes = [
    Display, Window, ctypes.POINTER(Window), ctypes.POINTER(Window),
    ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int),
    ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int),
    ctypes.POINTER(ctypes.c_uint)]
lib.XUnmapWindow.argtypes = [Display, Window]
lib.XMapWindow.argtypes = [Display, Window]
lib.XFlush.argtypes = [Display]
lib.XSync.argtypes = [Display, ctypes.c_int]
lib.XGetGeometry.argtypes = [
    Display, Window, ctypes.POINTER(Window), ctypes.POINTER(ctypes.c_int),
    ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_uint),
    ctypes.POINTER(ctypes.c_uint), ctypes.POINTER(ctypes.c_uint),
    ctypes.POINTER(ctypes.c_uint)]
lib.XTranslateCoordinates.argtypes = [
    Display, Window, Window, ctypes.c_int, ctypes.c_int,
    ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int), ctypes.POINTER(Window)]


class XWindowAttributes(ctypes.Structure):
    _fields_ = [
        ("x", ctypes.c_int), ("y", ctypes.c_int),
        ("width", ctypes.c_int), ("height", ctypes.c_int),
        ("border_width", ctypes.c_int), ("depth", ctypes.c_int),
        ("visual", ctypes.c_void_p), ("root", Window),
        ("class_", ctypes.c_int), ("bit_gravity", ctypes.c_int),
        ("win_gravity", ctypes.c_int), ("backing_store", ctypes.c_int),
        ("backing_planes", ctypes.c_ulong), ("backing_pixel", ctypes.c_ulong),
        ("save_under", ctypes.c_int), ("colormap", ctypes.c_ulong),
        ("map_installed", ctypes.c_int), ("map_state", ctypes.c_int),
        ("all_event_masks", ctypes.c_long), ("your_event_mask", ctypes.c_long),
        ("do_not_propagate_mask", ctypes.c_long),
        ("override_redirect", ctypes.c_int), ("screen", ctypes.c_void_p),
    ]


lib.XGetWindowAttributes.argtypes = [Display, Window, ctypes.POINTER(XWindowAttributes)]
lib.XQueryTree.restype = ctypes.c_int
lib.XQueryTree.argtypes = [Display, Window, ctypes.POINTER(Window), ctypes.POINTER(Window),
                           ctypes.POINTER(ctypes.POINTER(Window)), ctypes.POINTER(ctypes.c_uint)]
lib.XFree.restype = None

# Ошибки X (окно успело закрыться между запросами) не должны убивать демон.
ErrorHandler = ctypes.CFUNCTYPE(ctypes.c_int, Display, ctypes.c_void_p)


def _ignore_x_error(_d, _e):
    return 0


lib.XSetErrorHandler.restype = ctypes.c_void_p
lib.XSetErrorHandler.argtypes = [ErrorHandler]
_err_cb = ErrorHandler(_ignore_x_error)
lib.XSetErrorHandler(_err_cb)

# --- XShape (libXext) -------------------------------------------------------
# Прячем остров не окном целиком, а обрезкой по форме: остаётся полоска
# STRIP px на всю ширину, как у автоскрытой панели XFCE. Окно остаётся
# на месте, поэтому XID, геометрия и _NET_CLIENT_LIST не меняются.
class XRectangle(ctypes.Structure):
    _fields_ = [("x", ctypes.c_short), ("y", ctypes.c_short),
                ("width", ctypes.c_ushort), ("height", ctypes.c_ushort)]


xext = ctypes.CDLL(ctypes.util.find_library("Xext") or "libXext.so.6")
xext.XShapeCombineRectangles.argtypes = [
    Display, Window, ctypes.c_int, ctypes.c_int, ctypes.c_int,
    ctypes.POINTER(XRectangle), ctypes.c_int, ctypes.c_int, ctypes.c_int]
xext.XShapeCombineMask.argtypes = [
    Display, Window, ctypes.c_int, ctypes.c_int, ctypes.c_int,
    ctypes.c_ulong, ctypes.c_int]
SHAPE_BOUNDING = 0   # ShapeBounding
SHAPE_SET = 0        # ShapeSet

disp = lib.XOpenDisplay(None)
if not disp:
    sys.exit("нет соединения с X display")
root = lib.XDefaultRootWindow(disp)

_atoms = {}


def atom(name):
    a = _atoms.get(name)
    if a is None:
        a = lib.XInternAtom(disp, name.encode(), 1) or 0
        _atoms[name] = a
    return a


def get_prop(win, name, maxlen=4096):
    """(type, format, bytes) свойства окна; пусто, если его нет."""
    a = atom(name)
    if not a:
        return 0, 0, b""
    atype = Atom()
    fmt = ctypes.c_int()
    count = ctypes.c_ulong()
    after = ctypes.c_ulong()
    buf = ctypes.POINTER(ctypes.c_ubyte)()
    rc = lib.XGetWindowProperty(disp, win, a, 0, maxlen, 0, 0,
                                ctypes.byref(atype), ctypes.byref(fmt),
                                ctypes.byref(count), ctypes.byref(after),
                                ctypes.byref(buf))
    if rc != 0 or not atype.value or not count.value:
        if buf:
            lib.XFree(buf)
        return 0, 0, b""
    # Формат 32 Xlib отдаёт массивом long, а не 4-байтовых значений.
    if fmt.value == 32:
        nbytes = count.value * ctypes.sizeof(ctypes.c_long)
    else:
        nbytes = count.value * fmt.value // 8
    raw = ctypes.string_at(buf, nbytes)
    lib.XFree(buf)
    return atype.value, fmt.value, raw


def prop32(win, name):
    """Список 32-битных значений (Xlib кладёт их в long с выравниванием)."""
    atype, fmt, raw = get_prop(win, name)
    if fmt != 32 or not raw:
        return []
    n = len(raw) // ctypes.sizeof(ctypes.c_long)
    if n <= 0:
        return []
    arr = (ctypes.c_ulong * n).from_buffer_copy(raw[:n * ctypes.sizeof(ctypes.c_long)])
    return [int(v) & 0xFFFFFFFF for v in arr]


def prop_str(win, name):
    atype, fmt, raw = get_prop(win, name)
    if fmt != 8 or not raw:
        return ""
    return raw.split(b"\0", 1)[0].decode("utf-8", "replace")


def window_types(win):
    """Множество атомов _NET_WM_WINDOW_TYPE окна."""
    return set(prop32(win, "_NET_WM_WINDOW_TYPE"))


def has_state(win, name):
    """Есть ли у окна состояние _NET_WM_STATE (например, FULLSCREEN)."""
    return atom(name) in prop32(win, "_NET_WM_STATE")


_ignored = None


def ignored_types():
    """Типы, перекрытие которыми не повод прятать остров: рабочий стол и
    всплывающие элементы (меню, подсказки, уведомления)."""
    global _ignored
    if _ignored is None:
        names = ("DOCK", "DESKTOP", "MENU", "POPUP_MENU", "DROPDOWN_MENU",
                 "TOOLTIP", "NOTIFICATION", "SPLASH")
        _ignored = {atom("_NET_WM_WINDOW_TYPE_" + n) for n in names} - {0}
    return _ignored


def is_mapped(win):
    attrs = XWindowAttributes()
    if not lib.XGetWindowAttributes(disp, win, ctypes.byref(attrs)):
        return False
    return attrs.map_state == IS_VIEWABLE


def client_list():
    return prop32(root, "_NET_CLIENT_LIST")


def active_window():
    ids = prop32(root, "_NET_ACTIVE_WINDOW")
    return ids[0] if ids else 0


def pointer():
    rr = Window()
    cr = Window()
    rx = ctypes.c_int()
    ry = ctypes.c_int()
    wx = ctypes.c_int()
    wy = ctypes.c_int()
    mask = ctypes.c_uint()
    if not lib.XQueryPointer(disp, root, ctypes.byref(rr), ctypes.byref(cr),
                             ctypes.byref(rx), ctypes.byref(ry),
                             ctypes.byref(wx), ctypes.byref(wy),
                             ctypes.byref(mask)):
        return 0, 0, 0
    # Button1..Button5 - биты 8..12. В маске есть и Lock/NumLock (биты 1..),
    # поэтому возвращаем только кнопки, иначе наведение ломается при CapsLock.
    return rx.value, ry.value, mask.value & 0x1F00


def geom(win):
    """Абсолютные x, y, w, h клиентской области (без рамки WM)."""
    if not win:
        return None
    r = Window()
    x = ctypes.c_int()
    y = ctypes.c_int()
    w = ctypes.c_uint()
    h = ctypes.c_uint()
    bw = ctypes.c_uint()
    depth = ctypes.c_uint()
    if not lib.XGetGeometry(disp, win, ctypes.byref(r), ctypes.byref(x),
                            ctypes.byref(y), ctypes.byref(w), ctypes.byref(h),
                            ctypes.byref(bw), ctypes.byref(depth)):
        return None
    ax = ctypes.c_int()
    ay = ctypes.c_int()
    child = Window()
    if not lib.XTranslateCoordinates(disp, win, root, 0, 0,
                                     ctypes.byref(ax), ctypes.byref(ay),
                                     ctypes.byref(child)):
        return None
    return ax.value, ay.value, w.value, h.value


def apply_shape(win, mode):
    """full - окно целиком, strip - полоска STRIP px, hidden - ничего."""
    if mode == "full":
        # снять обрезку: пустая маска возвращает окну обычную форму
        xext.XShapeCombineMask(disp, win, SHAPE_BOUNDING, 0, 0, 0, SHAPE_SET)
    else:
        g = geom(win)
        if not g:
            return
        rect = XRectangle(0, 0, g[2], STRIP if mode == "strip" else 0)
        xext.XShapeCombineRectangles(disp, win, SHAPE_BOUNDING, 0, 0,
                                     ctypes.byref(rect), 1, SHAPE_SET, 0)
    lib.XSync(disp, 0)


def frame_rect(win):
    """Прямоугольник окна вместе с рамкой/заголовком WM (_NET_FRAME_EXTENTS)."""
    g = geom(win)
    if not g:
        return None
    ext = prop32(win, "_NET_FRAME_EXTENTS")
    if len(ext) >= 4:
        left, right, top, bottom = ext[0], ext[1], ext[2], ext[3]
    else:
        left = right = top = bottom = 0
    x, y, w, h = g
    return x - left, y - top, w + left + right, h + top + bottom


def intersects(a, b):
    return (a[0] < b[0] + b[2] and b[0] < a[0] + a[2]
            and a[1] < b[1] + b[3] and b[1] < a[1] + a[3])


# --- Поиск окна острова и панелей по PID демона Eww ---
_pid_cache = {}


def eww_pid():
    needle = ("--config " + CONF + " daemon").encode()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open("/proc/%s/cmdline" % entry, "rb") as f:
                cmd = f.read().replace(b"\0", b" ")
        except OSError:
            continue
        if needle in cmd:
            return int(entry)
    return 0


def client_pid(win):
    if win in _pid_cache:
        return _pid_cache[win]
    ids = prop32(win, "_NET_WM_PID")
    pid = ids[0] if ids else 0
    _pid_cache[win] = pid
    return pid


def find_island(clients, pid):
    dock = atom("_NET_WM_WINDOW_TYPE_DOCK")
    for w in clients:
        if not pid or client_pid(w) != pid:
            continue
        if dock and dock in prop32(w, "_NET_WM_WINDOW_TYPE"):
            return w
    return None


def find_island_deep(pid, win=None, depth=0):
    """Поиск острова по всему дереву: окно может отсутствовать в
    _NET_CLIENT_LIST (например, до первого показа)."""
    if not pid or depth > 4:
        return None
    if win is None:
        win = root
    r = Window()
    p = Window()
    kids = ctypes.POINTER(Window)()
    n = ctypes.c_uint()
    if not lib.XQueryTree(disp, win, ctypes.byref(r), ctypes.byref(p),
                          ctypes.byref(kids), ctypes.byref(n)):
        return None
    try:
        for i in range(n.value):
            w = kids[i]
            if client_pid(w) == pid:
                dock = atom("_NET_WM_WINDOW_TYPE_DOCK")
                if dock and dock in prop32(w, "_NET_WM_WINDOW_TYPE"):
                    return w
            found = find_island_deep(pid, w, depth + 1)
            if found:
                return found
    finally:
        if kids:
            lib.XFree(kids)
    return None


def panels_open(clients, island_xid, pid):
    """Открыта ли панель Eww: любое видимое окно демона, кроме острова."""
    if not pid:
        return False
    for w in clients:
        if w == island_xid:
            continue
        if client_pid(w) == pid and is_mapped(w):
            return True
    return False


# --- Флаг ручного выключения ---
def autohide_off():
    return os.path.exists(OFFFILE)


def log(msg):
    try:
        with open(LOGFILE, "a") as f:
            f.write("%s %s\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), msg))
    except OSError:
        pass


def restore_island():
    """Найти остров и вернуть ему полную форму (в т.ч. после kill -9)."""
    pid = eww_pid()
    if not pid:
        return 0
    w = find_island(client_list(), pid) or find_island_deep(pid) or 0
    if not w:
        return 0
    if not is_mapped(w):
        lib.XMapWindow(disp, w)
        lib.XSync(disp, 0)
        # ждём, пока WM вернёт окно в _NET_CLIENT_LIST (нужно island-geom.sh)
        for _ in range(20):
            if is_mapped(w) and w in client_list():
                break
            time.sleep(0.05)
    apply_shape(w, "full")
    log("остров восстановлен xid=0x%x" % w)
    return w


def read_pid():
    try:
        with open(PIDFILE) as f:
            return int(f.read().strip() or 0)
    except (OSError, ValueError):
        return 0


def alive(pid):
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


class State:
    def __init__(self):
        self.island = 0
        self.mode = "full"   # full | strip | hidden
        self.shape_w = None
        self.pid = 0
        self.hot_since = None
        self.leave_since = None
        self.last_pid = -1e9
        self.last_deep = -1e9


def tick(st, apply=True, verbose=False):
    """Один шаг: решить, должен ли остров быть виден, и применить."""
    now = time.monotonic()
    clients = client_list()
    if not st.pid and now - st.last_pid >= 5:
        st.last_pid = now
        st.pid = eww_pid()
    # чистка кэша PID: окна, которых больше нет в списке
    for w in list(_pid_cache):
        if w not in clients and w != st.island:
            del _pid_cache[w]

    if not st.island or geom(st.island) is None:
        prev = st.island
        st.island = find_island(clients, st.pid)
        if not st.island and now - st.last_deep >= 5:
            # окно могло смениться (перезапуск Eww) или выпасть из
            # _NET_CLIENT_LIST - обновляем PID и ищем по дереву
            st.last_deep = now
            st.pid = eww_pid() or st.pid
            st.island = find_island(clients, st.pid) or find_island_deep(st.pid) or 0
        if not st.island:
            if verbose:
                print("остров не найден (демон Eww не запущен?)")
            return None
        if st.island != prev:
            # новое окно (перезапуск Eww): форма у него ещё полная
            st.mode = "full"
            st.shape_w = None

    rect = geom(st.island)
    if rect is None:
        st.island = 0
        return None

    active = active_window()
    panels = panels_open(clients, st.island, st.pid)
    off = autohide_off()

    covered = False
    fullscreen = False
    if not off and not panels and active and active != st.island:
        if not (client_pid(active) == st.pid and is_mapped(active)):
            skip = bool(window_types(active) & ignored_types())
            arect = frame_rect(active)
            if arect and not skip:
                covered = intersects(arect, rect)
                # fullscreen: наведение остров не вытаскивает (видео, игры),
                # иначе он всплывает поверх плеера при движении к его меню
                fullscreen = covered and has_state(active, "_NET_WM_STATE_FULLSCREEN")

    px, py, buttons = pointer()
    ix, iy, iw, ih = rect
    # Кнопки мыши: при перетаскивании (выделение, вкладки браузера) остров
    # наведением не вытаскиваем, чтобы не перехватить клик.
    in_hot = (ix <= px < ix + iw) and (iy <= py <= iy + EDGE) and not buttons
    in_rect = (ix <= px < ix + iw) and (iy <= py < iy + ih)

    now = time.monotonic()
    shown = st.mode == "full"
    hover = False
    if covered and not shown:
        # свёрнут под окном: показываем по задержке у верхней кромки
        if in_hot and not fullscreen:
            if st.hot_since is None:
                st.hot_since = now
            hover = (now - st.hot_since) >= DWELL
        else:
            st.hot_since = None
    else:
        st.hot_since = None

    if off or panels or not covered:
        want = "full"
        st.leave_since = None
    elif fullscreen:
        # видео/игра: ни полоски, ни показа наведением
        want = "hidden"
        st.leave_since = None
    elif shown:
        if in_rect:
            st.leave_since = None
            want = "full"
        else:
            # пауза после ухода курсора: успевает открыться панель по клику
            if st.leave_since is None:
                st.leave_since = now
            want = "full" if (now - st.leave_since) < LEAVE else "strip"
    else:
        st.leave_since = None
        want = "full" if hover else "strip"

    if apply and (want != st.mode or (want == "strip" and st.shape_w != iw)):
        apply_shape(st.island, want)
        st.mode = want
        st.shape_w = iw if want == "strip" else None
        log(("показан" if want == "full" else
             "полоска" if want == "strip" else "скрыт")
            + " xid=0x%x active=0x%x covered=%s panels=%s off=%s cursor=%d,%d hover=%s"
            % (st.island, active, covered, panels, off, px, py, hover))
    elif not apply and want != st.mode:
        # status/once: только решение, форму не трогаем, но показываем реальный
        # режим, а не умалчиваемый "full"
        st.mode = want
        st.shape_w = iw if want == "strip" else None

    if DEBUG:
        log("шаг mode=%s covered=%s panels=%s off=%s cursor=%d,%d hot=%s dwell=%.2f"
            % (st.mode, covered, panels, off, px, py, in_hot,
               (now - st.hot_since) if st.hot_since else -1.0))

    if verbose:
        print("остров=0x%x %d,%d %dx%d %s | активное=0x%x %r %s | перекрывает=%s "
              "панели=%s выкл=%s курсор=%d,%d"
              % (st.island, ix, iy, iw, ih,
                 "виден" if st.mode == "full" else
                 "полоска" if st.mode == "strip" else "скрыт",
                 active, prop_str(active, "_NET_WM_NAME"),
                 frame_rect(active) if active else None,
                 covered, panels, off, px, py))
        print("решение: " + ("показать" if want == "full" else
                            "свернуть в полоску" if want == "strip" else "скрыть"))
    return want


def run():
    st = State()
    stopping = {"flag": False}

    # Если прошлый запуск оставил остров скрытым (kill -9), вернуть его.
    restore_island()

    def on_signal(_sig, _frm):
        stopping["flag"] = True

    signal.signal(signal.SIGTERM, on_signal)
    signal.signal(signal.SIGINT, on_signal)

    log("старт pid=%d" % os.getpid())
    while not stopping["flag"]:
        try:
            tick(st)
        except Exception as exc:  # демон не должен падать от единичного сбоя
            log("ошибка: %r" % (exc,))
            time.sleep(1.0)
        time.sleep(TICK)

    # при остановке вернуть остров, иначе он останется в полоске/скрытым
    if st.island:
        try:
            apply_shape(st.island, "full")
        except Exception:
            pass
    log("остановлен")
    try:
        os.unlink(PIDFILE)
    except OSError:
        pass


def start():
    pid = read_pid()
    if alive(pid):
        print("автоскрытие уже работает (pid %d)" % pid)
        return 0
    os.makedirs(CACHE, exist_ok=True)
    try:
        if os.path.getsize(LOGFILE) > 256 * 1024:
            os.replace(LOGFILE, LOGFILE + ".old")
    except OSError:
        pass
    if os.fork() > 0:
        return 0
    os.setsid()
    if os.fork() > 0:
        os._exit(0)
    os.chdir("/")
    fd = os.open(os.devnull, os.O_RDONLY)
    os.dup2(fd, 0)
    fd = os.open(LOGFILE, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o644)
    os.dup2(fd, 1)
    os.dup2(fd, 2)
    with open(PIDFILE, "w") as f:
        f.write(str(os.getpid()))
    run()
    os._exit(0)


def stop():
    pid = read_pid()
    if not alive(pid):
        try:
            os.unlink(PIDFILE)
        except OSError:
            pass
        print("автоскрытие не запущено")
        return 0
    os.kill(pid, signal.SIGTERM)
    for _ in range(20):
        if not alive(pid):
            break
        time.sleep(0.1)
    if alive(pid):
        os.kill(pid, signal.SIGKILL)
    try:
        os.unlink(PIDFILE)
    except OSError:
        pass
    print("автоскрытие остановлено")
    return 0


def main(argv):
    cmd = argv[1] if len(argv) > 1 else "start"
    if cmd == "start":
        return start()
    if cmd == "stop":
        return stop()
    if cmd == "restore":
        w = restore_island()
        print("остров показан" if w else "остров не найден")
        return 0 if w else 1
    if cmd == "status":
        pid = read_pid()
        running = alive(pid)
        print("автоскрытие: %s%s" % ("работает (pid %d)" % pid if running else "не запущено",
                                     ", выключено флагом" if autohide_off() else ""))
        st = State()
        tick(st, apply=False, verbose=True)
        return 0
    if cmd == "once":
        st = State()
        tick(st, apply=False, verbose=True)
        return 0
    if cmd == "watch":
        st = State()
        try:
            while True:
                tick(st, apply=True, verbose=True)
                sys.stdout.flush()
                time.sleep(TICK)
        except KeyboardInterrupt:
            return 0
    if cmd == "off":
        os.makedirs(CACHE, exist_ok=True)
        open(OFFFILE, "w").close()
        print("автоскрытие выключено (остров всегда виден)")
        return 0
    if cmd == "on":
        try:
            os.unlink(OFFFILE)
        except OSError:
            pass
        print("автоскрытие включено")
        return 0
    if cmd == "toggle":
        if autohide_off():
            try:
                os.unlink(OFFFILE)
            except OSError:
                pass
            print("автоскрытие включено")
        else:
            os.makedirs(CACHE, exist_ok=True)
            open(OFFFILE, "w").close()
            print("автоскрытие выключено (остров всегда виден)")
        return 0
    sys.stderr.write("usage: island-autohide.py [start|stop|restore|status|once|watch|off|on|toggle]\n")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
