/* Текущая группа XKB: номер группы в stdout.
 * watch — печатать номер при каждом переключении, next — переключить на следующую.
 * Нужен потому, что xkb-switch / xkblayout-state в системе нет. */
#include <stdio.h>
#include <string.h>
#include <X11/Xlib.h>
#include <X11/XKBlib.h>

static unsigned group_count(Display *d) {
    XkbDescPtr xkb = XkbGetMap(d, 0, XkbUseCoreKbd);
    if (!xkb) return 1;
    unsigned n = 1;
    if (XkbGetControls(d, XkbAllControlsMask, xkb) == Success && xkb->ctrls) {
        n = xkb->ctrls->num_groups;
    }
    XkbFreeKeyboard(xkb, 0, True);
    return n > 0 ? n : 1;
}

int main(int argc, char **argv) {
    Display *d = XOpenDisplay(NULL);
    if (!d) return 1;

    int op, ev, err;
    if (!XkbQueryExtension(d, &op, &ev, &err, NULL, NULL)) return 1;

    XkbStateRec st;
    if (XkbGetState(d, XkbUseCoreKbd, &st) != Success) return 1;

    if (argc > 1 && strcmp(argv[1], "next") == 0) {
        XkbLockGroup(d, XkbUseCoreKbd, (st.group + 1) % group_count(d));
        XFlush(d);
        return 0;
    }

    if (argc > 1 && strcmp(argv[1], "watch") == 0) {
        XkbSelectEvents(d, XkbUseCoreKbd, XkbStateNotifyMask, XkbStateNotifyMask);
        printf("%d\n", st.group);
        fflush(stdout);
        for (;;) {
            XEvent e;
            XNextEvent(d, &e);
            XkbEvent *xe = (XkbEvent *)&e;
            if (xe->any.xkb_type == XkbStateNotify) {
                printf("%d\n", xe->state.group);
                fflush(stdout);
            }
        }
    }

    printf("%d\n", st.group);
    return 0;
}
