// Позиция курсора на экране: pointer.sh -> "X Y"
// Нужен, чтобы выпадающая панель открылась точно под кнопкой,
// по которой кликнули, независимо от раскладки острова.
#include <X11/Xlib.h>
#include <stdio.h>

int main(void) {
    Display *d = XOpenDisplay(NULL);
    if (!d) {
        fprintf(stderr, "no display\n");
        return 1;
    }
    Window root = DefaultRootWindow(d);
    Window dummy;
    int x, y, wx, wy;
    unsigned int mask;
    if (!XQueryPointer(d, root, &dummy, &dummy, &x, &y, &wx, &wy, &mask)) {
        fprintf(stderr, "cannot query pointer\n");
        XCloseDisplay(d);
        return 1;
    }
    printf("%d %d\n", x, y);
    XCloseDisplay(d);
    return 0;
}
