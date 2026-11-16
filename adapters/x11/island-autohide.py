#!/usr/bin/env python3
# Скрытие острова в полноэкранных окнах (игры, фильмы).
#
# Зачем: остров - dock-окно с резервом 50 px сверху. Обычные и развёрнутые
# окна начинаются ниже острова и его не перекрывают, поэтому старое правило
# "прятать при перекрытии" больше не срабатывает. Прятать остров нужно только
# в полноэкранных окнах: они резерв игнорируют и рисуют под островом.
#
# Поведение:
#   * активное окно в состоянии _NET_WM_STATE_FULLSCREEN -> остров закрывается
#     (eww close island); резерв 50 px снимается вместе с окном, полноэкранным
#     окнам он не нужен - они его игнорируют;
#   * полноэкранное окно закрыто или потеряло активность -> остров открывается
#     заново и центрируется по экрану (та же схема, что scripts/run-island.sh);
#   * обычные/развёрнутые окна остров не трогают никогда;
#   * открыта любая панель Eww (хаб и т.п.) -> не прячем;
#   * файл-флаг autohide-off -> автоскрытие выключено, остров всегда виден;
#   * состояние "скрыт" хранится в файле autohide-hidden: после kill -9
#     следующий запуск вернёт остров.
#
# События: xprop -spy -root _NET_ACTIVE_WINDOW (смена активного окна) и
# xprop -spy -id <активное окно> _NET_WM_STATE (F11 в том же окне).
# У _NET_WM_STATE нет корневого свойства, поэтому шпион переподключается при
# каждой смене активного окна. Раз в TICK секунд - контрольный опрос, чтобы
# не зависеть от пропущенных событий.
#
# usage: island-autohide.py            запустить в фоне (демон)
#        island-autohide.py start      то же (для run-island.sh)
#        island-autohide.py stop       остановить, вернуть остров
#        island-autohide.py restore    снять флаг скрытия (остров вернёт демон)
#        island-autohide.py status     состояние (для отладки)
#        island-autohide.py once       один шаг, печать решения, без изменений
#        island-autohide.py watch      цикл с печатью каждого шага (отладка)
#        island-autohide.py off|on     выключить/включить автоскрытие
#        island-autohide.py toggle     переключить автоскрытие
import ctypes
import ctypes.util
import os
import select
import signal
import subprocess
import sys
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
CONF = os.path.join(ROOT, "eww")
EWW = os.path.join(ROOT, "build", "target", "release", "eww")

CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")), "eww-island")
PIDFILE = os.path.join(CACHE, "autohide.pid")
LOGFILE = os.path.join(CACHE, "autohide.log")
OFFFILE = os.path.join(CACHE, "autohide-off")
HIDDENFILE = os.path.join(CACHE, "autohide-hidden")
DEBUG = bool(os.environ.get("ISLAND_AUTOHIDE_DEBUG"))

TICK = 0.5        # контрольный опрос состояния, с
SETTLE = 0.15     # пауза после события: WM успевает доставить смену состояния, с

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
lib.XDefaultScreen.restype = ctypes.c_int
lib.XDefaultScreen.argtypes = [Display]
lib.XDisplayWidth.restype = ctypes.c_int
lib.XDisplayWidth.argtypes = [Display, ctypes.c_int]
lib.XInternAtom.restype = Atom
lib.XInternAtom.argtypes = [Display, ctypes.c_char_p, ctypes.c_int]
lib.XGetWindowProperty.restype = ctypes.c_int
lib.XGetWindowProperty.argtypes = [
    Display, Window, Atom, ctypes.c_long, ctypes.c_long, ctypes.c_int, Atom,
    ctypes.POINTER(Atom), ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_ulong),
    ctypes.POINTER(ctypes.c_ulong), ctypes.POINTER(ctypes.POINTER(ctypes.c_ubyte))]
lib.XFree.argtypes = [ctypes.c_void_p]
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


def has_state(win, name):
    """Есть ли у окна состояние _NET_WM_STATE (например, FULLSCREEN)."""
    return atom(name) in prop32(win, "_NET_WM_STATE")


def is_fullscreen(win):
    return bool(win) and has_state(win, "_NET_WM_STATE_FULLSCREEN")


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


def screen_w():
    return lib.XDisplayWidth(disp, lib.XDefaultScreen(disp))


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


# --- Флаги ручного выключения и "остров скрыт" ---
def autohide_off():
    return os.path.exists(OFFFILE)


def is_hidden_flag():
    return os.path.exists(HIDDENFILE)


def set_hidden_flag(value):
    try:
        if value:
            os.makedirs(CACHE, exist_ok=True)
            open(HIDDENFILE, "w").close()
        elif os.path.exists(HIDDENFILE):
            os.unlink(HIDDENFILE)
    except OSError:
        pass


def log(msg):
    try:
        with open(LOGFILE, "a") as f:
            f.write("%s %s\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), msg))
    except OSError:
        pass


# --- Закрытие/открытие острова через eww ---
def run_eww(*args):
    cmd = [EWW, "--config", CONF, "--no-daemonize"] + list(args)
    try:
        return subprocess.run(cmd, stdout=subprocess.DEVNULL,
                              stderr=subprocess.PIPE, timeout=10).returncode
    except (OSError, subprocess.TimeoutExpired):
        return -1


def wait_island(pid, timeout):
    """Ждать появления видимого окна острова; 0, если не дождались."""
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        w = find_island(client_list(), pid) or find_island_deep(pid) or 0
        if w and is_mapped(w):
            return w
        time.sleep(0.05)
    return 0


def hide_island(st, active):
    st.pid = st.pid or eww_pid()
    w = find_island(client_list(), st.pid) or find_island_deep(st.pid) or 0
    if not w:
        # окно уже закрыто (перезапуск Eww или повторный вызов)
        set_hidden_flag(True)
        st.hidden = True
        return
    rc = run_eww("close", "island")
    # ждём, пока окно действительно исчезнет
    end = time.monotonic() + 1.0
    while time.monotonic() < end and find_island(client_list(), st.pid) == w:
        time.sleep(0.05)
    if find_island(client_list(), st.pid) == w:
        log("ошибка: остров не закрылся (eww=%d) active=0x%x" % (rc, active))
        return
    set_hidden_flag(True)
    st.hidden = True
    log("скрыт active=0x%x (eww=%d)" % (active, rc))


def show_island(st):
    pid = eww_pid()
    if not pid:
        # демон не запущен: окно откроет scripts/run-island.sh
        set_hidden_flag(False)
        st.hidden = False
        log("демон Eww не запущен, остров откроет run-island.sh")
        return
    st.pid = pid
    rc = run_eww("open", "island", "--pos", "0x0")
    w = wait_island(pid, 3.0)
    if not w:
        st.retry_after = time.monotonic() + 2.0
        log("ошибка: остров не открылся (eww=%d), повтор через 2 с" % rc)
        return
    # Eww отдаёт размер по факту раскладки: даём ~200 мс устаканиться
    time.sleep(0.3)
    g = geom(w)
    if not g:
        st.retry_after = time.monotonic() + 2.0
        log("ошибка: геометрия острова не прочиталась")
        return
    want_x = max(0, (screen_w() - g[2]) // 2)
    if g[0] != want_x:
        run_eww("open", "island", "--pos", "%dx0" % want_x)
        # Eww пересоздаёт окно при смене позиции: XID меняется, поэтому
        # окно переискиваем на каждом шаге, а не держим старый id.
        end = time.monotonic() + 2.0
        while time.monotonic() < end:
            time.sleep(0.1)
            g2 = geom(find_island(client_list(), pid) or w)
            if g2:
                g = g2
            if g[0] == want_x:
                break
        if g[0] != want_x:
            log("предупреждение: остров не отцентрирован (x=%d, нужно %d)"
                % (g[0], want_x))
    set_hidden_flag(False)
    st.hidden = False
    st.retry_after = 0.0
    log("показан x=%d y=%d w=%d h=%d (центр %d)" % (g[0], g[1], g[2], g[3], want_x))


class State:
    def __init__(self):
        self.hidden = is_hidden_flag()
        self.active = 0
        self.fullscreen = False
        self.spied = 0       # окно, за _NET_WM_STATE которого следим
        self.retry_after = 0.0
        self.pid = 0
        self.last_pid = -1e9


def evaluate(st, apply=True, verbose=False):
    """Один шаг: спрятать/показать остров по состоянию активного окна."""
    now = time.monotonic()
    if not st.pid or now - st.last_pid >= 5:
        st.last_pid = now
        st.pid = eww_pid() or st.pid

    clients = client_list()
    # чистка кэша PID: окна, которых больше нет в списке
    for w in list(_pid_cache):
        if w not in clients:
            del _pid_cache[w]

    island = find_island(clients, st.pid) or 0
    if st.hidden and island and is_mapped(island):
        # остров вернули извне (run-island.sh, ручной eww open)
        set_hidden_flag(False)
        st.hidden = False
        log("остров открыт извне, флаг скрытия снят xid=0x%x" % island)

    active = active_window()
    st.active = active
    fs = is_fullscreen(active)
    st.fullscreen = fs
    panels = panels_open(clients, island, st.pid)
    off = autohide_off()

    want_hidden = fs and not off and not panels

    if verbose:
        print("остров=0x%x %s | активное=0x%x %r полноэкранное=%s "
              "панели=%s выкл=%s скрыт=%s"
              % (island, geom(island) if island else "нет",
                 active, prop_str(active, "_NET_WM_NAME"), fs,
                 panels, off, st.hidden))
        print("решение: " + ("скрыть" if want_hidden else "показать"))

    if not apply:
        return want_hidden

    if want_hidden and not st.hidden and now >= st.retry_after:
        hide_island(st, active)
    elif not want_hidden and st.hidden and now >= st.retry_after:
        show_island(st)
    return want_hidden


# --- События через xprop -spy ---
def spawn_root_spy():
    try:
        return subprocess.Popen(["xprop", "-spy", "-root", "_NET_ACTIVE_WINDOW"],
                                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                text=True, bufsize=1)
    except OSError:
        return None


def spawn_win_spy(win):
    if not win:
        return None
    try:
        return subprocess.Popen(["xprop", "-spy", "-id", hex(win), "_NET_WM_STATE"],
                                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                text=True, bufsize=1)
    except OSError:
        return None


def drain(f):
    """Прочитать доступные строки шпиона; True, если поток закрылся."""
    while True:
        try:
            r, _, _ = select.select([f], [], [], 0)
        except (OSError, ValueError):
            return True
        if not r:
            return False
        try:
            line = f.readline()
        except (OSError, ValueError):
            return True
        if not line:
            return True
        if DEBUG:
            log("событие: %s" % line.strip())


def run():
    st = State()
    stopping = {"flag": False}

    def on_signal(_sig, _frm):
        stopping["flag"] = True

    signal.signal(signal.SIGTERM, on_signal)
    signal.signal(signal.SIGINT, on_signal)

    log("старт pid=%d (скрыт по флагу: %s)" % (os.getpid(), st.hidden))

    root_spy = spawn_root_spy()
    win_spy = None
    pending = 0.0
    last_eval = 0.0
    while not stopping["flag"]:
        fds = []
        if root_spy and root_spy.stdout:
            fds.append(root_spy.stdout)
        if win_spy and win_spy.stdout:
            fds.append(win_spy.stdout)
        try:
            ready, _, _ = select.select(fds, [], [], 0.1)
        except (OSError, ValueError):
            ready = []
        event = False
        for f in ready:
            if drain(f):
                event = True
        if root_spy and root_spy.poll() is not None:
            root_spy = spawn_root_spy()
            event = True
        if win_spy and win_spy.poll() is not None:
            win_spy = None
            event = True

        now = time.monotonic()
        if event:
            pending = now
        do_eval = False
        if pending and now - pending >= SETTLE:
            pending = 0.0
            last_eval = now
            do_eval = True
        elif now - last_eval >= TICK:
            last_eval = now
            do_eval = True
        if do_eval:
            try:
                evaluate(st)
            except Exception as exc:  # демон не должен падать от единичного сбоя
                log("ошибка: %r" % (exc,))
                time.sleep(1.0)
            # шпион _NET_WM_STATE переезжает на новое активное окно
            if st.active != st.spied:
                if win_spy:
                    try:
                        win_spy.terminate()
                    except OSError:
                        pass
                    win_spy = None
                st.spied = st.active
                win_spy = spawn_win_spy(st.active)
        time.sleep(0.02)

    # при остановке вернуть остров, иначе он останется закрытым
    if st.hidden:
        try:
            show_island(st)
        except Exception:
            pass
    for p in (root_spy, win_spy):
        if p:
            try:
                p.terminate()
            except OSError:
                pass
    log("остановлен")
    try:
        os.unlink(PIDFILE)
    except OSError:
        pass


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
        # Флаг скрытия снимаем: запущенный демон откроет остров сам при
        # следующем шаге, а run-island.sh откроет его, если демона нет.
        had = is_hidden_flag()
        set_hidden_flag(False)
        print("флаг скрытия снят" if had else "остров не был скрыт")
        return 0
    if cmd == "status":
        pid = read_pid()
        running = alive(pid)
        print("автоскрытие: %s%s"
              % ("работает (pid %d)" % pid if running else "не запущено",
                 ", выключено флагом" if autohide_off() else ""))
        st = State()
        evaluate(st, apply=False, verbose=True)
        return 0
    if cmd == "once":
        st = State()
        evaluate(st, apply=False, verbose=True)
        return 0
    if cmd == "watch":
        st = State()
        try:
            while True:
                evaluate(st, apply=True, verbose=True)
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
