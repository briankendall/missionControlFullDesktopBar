#import <Cocoa/Cocoa.h>
#import "cursorPositionMethod.h"
#import "app.h"
#import "events.h"
#import "eventTap.h"

#define kCursorPositionEventTag 0x4201337
#define kCursorPositionResetEventTag 0x4206969

static CGPoint cursorStart;
static bool cursorMethodInProgress = false;
static bool mousePositionedSuccessfully = false;

typedef int CGSConnectionID;
CG_EXTERN CGSConnectionID CGSMainConnectionID(void);
CG_EXTERN CGError CGSGetCurrentCursorLocation(CGSConnectionID cid, CGPoint *outPos);

void handleCursorPositionEventAndPostNext()
{
    if (mousePositionedSuccessfully) {
        return;
    }
    
    printf("Received mouse positioning event!\n");
    fflush(stdout);
    mousePositionedSuccessfully = true;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.003 * NSEC_PER_SEC)), 
                   dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^ () {
        invokeMissionControl();
        
        // This is something of a race condition, but as far as I know there's no way to know exactly when Mission Control's
        // animation will start.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.01 * NSEC_PER_SEC)), 
                       dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^ () {
            //postLeftMouseButtonEventWithUserData(kCGEventMouseMoved, cursorStart.x, cursorStart.y, kCursorPositionResetEventTag);
            moveCursor(cursorStart.x, cursorStart.y);
            cleanUpAndFinish();
        });
    });
}

void handleCursorPositionResetEvent(CGEventRef event)
{
    stopEventTap();
    CGPoint p = CGEventGetLocation(event);
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.001 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^ () {
        CGPoint p2 = currentMouseLocation();
        CGPoint p3;
        CGSGetCurrentCursorLocation(CGSMainConnectionID(), &p3);
        printf("Received mouse reset event! loc: %.1f %.1f", p.x, p.y);
        printf(".. check loc: %.1f %.1f     check loc2: %.1f %.1f", p2.x, p2.y, p3.x, p3.y);
        
        if (!CGPointEqualToPoint(p, p2)) {
            startEventTap();
            printf("**** Something went wrong! Reissuing reset mouse event!");
            moveCursor(cursorStart.x, cursorStart.y);
        } else {
            cleanUpAndFinish();
        }
    });
}

bool isCursorPositionEvent(CGEventRef event)
{
    return ((CGEventGetIntegerValueField(event, kCGEventSourceUnixProcessID) == getpid() ||
             CGEventGetIntegerValueField(event, kCGEventSourceUserData) == kCursorPositionEventTag)
            && CGEventGetLocation(event).x > 95 && CGEventGetLocation(event).x < 105);
}

void showMissionControlWithFullDesktopBarUsingCursorPositionMethod()
{
    cursorMethodInProgress = true;
    mousePositionedSuccessfully = false;
    cursorStart = currentMouseLocation();
    
    printf("Invoking mission control using cursor position method...");
    fflush(stdout);
    
    startEventTapAndResetCursorDelta();
    // I honestly can't tell which method is more reliable... CGEventPost or IOHIDPostEvent. Both
    // have issues. Right now I've settled on IOHIDPostEvent.
    //postLeftMouseButtonEventWithUserData(kCGEventMouseMoved, 100, 0, kCursorPositionEventTag);
    moveCursor(100, 0);
    ensureAppStopsAfterDuration(100);
}

void cursorPositionMethodCleanUp()
{
    if (!cursorMethodInProgress) {
        return;
    }
    
    cursorMethodInProgress = false;
    
    if (!mousePositionedSuccessfully) {
        NSLog(@"Error: cursor method failed to position cursor. Am invoking mission control anyway...");
        invokeMissionControl();
    }
}
