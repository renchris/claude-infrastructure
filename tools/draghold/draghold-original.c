// Press, move partway, HOLD (so the screen can be photographed mid-drag), then release.
// kitty draws a drag overlay/thumbnail while a window drag is in progress
// (set_window_drag_overlay, change_drag_thumbnail), so a capture taken while the button is
// still down separates "the drag never started" from "the drag started and the drop failed".
#include <ApplicationServices/ApplicationServices.h>
#include <stdlib.h>
#include <unistd.h>
static void post(CGEventType t, CGPoint p) {
    CGEventRef e = CGEventCreateMouseEvent(NULL, t, p, kCGMouseButtonLeft);
    CGEventPost(kCGHIDEventTap, e); CFRelease(e); usleep(12000);
}
int main(int argc, char **argv) {
    if (argc < 6) { fprintf(stderr, "usage: draghold x1 y1 x2 y2 hold_ms [steps]\n"); return 2; }
    double x1=atof(argv[1]), y1=atof(argv[2]), x2=atof(argv[3]), y2=atof(argv[4]);
    int hold=atoi(argv[5]), steps = argc>6 ? atoi(argv[6]) : 40;
    CGWarpMouseCursorPosition(CGPointMake(x1,y1));
    post(kCGEventMouseMoved, CGPointMake(x1,y1));
    usleep(250000);
    post(kCGEventLeftMouseDown, CGPointMake(x1,y1));
    usleep(120000);
    for (int i=1;i<=steps;i++){
        double f=(double)i/steps;
        post(kCGEventLeftMouseDragged, CGPointMake(x1+(x2-x1)*f, y1+(y2-y1)*f));
    }
    fprintf(stderr, "held at target, %d ms\n", hold);
    usleep(hold*1000);
    post(kCGEventLeftMouseUp, CGPointMake(x2,y2));
    return 0;
}
