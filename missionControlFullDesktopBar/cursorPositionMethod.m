#import <Cocoa/Cocoa.h>
#import "cursorPositionMethod.h"
#import "app.h"
#import "events.h"
#import "eventTap.h"

#define kCursorPositionEventTag 0x4201337

static CGPoint cursorStart;
static bool cursorMethodInProgress = false;
static bool mousePositionedSuccessfully = false;

void handleCursorPositionEventAndPostNext()
{
    if (mousePositionedSuccessfully) {
        return;
    }
    
    printf("Received mouse positioning event!\n");
    fflush(stdout);
    mousePositionedSuccessfully = true;
    invokeMissionControl();
        
    // This is something of a race condition, but as far as I know there's no way to know exactly when Mission Control's
    // animation will start. But a wait time of 0.001 seconds seems to work very consistently, so 0.003 seconds should
    // work three times as very consistently!
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.003 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^ () {
        cleanUpAndFinish();
    });
}

bool isCursorPositionEvent(CGEventRef event, CGEventTapProxy proxy)
{
    return ((CGEventGetIntegerValueField(event, kCGEventSourceUnixProcessID) == getpid() ||
             CGEventGetIntegerValueField(event, kCGEventSourceUserData) == kCursorPositionEventTag)
            && CGEventGetLocation(event).x > 95 && CGEventGetLocation(event).x < 105);
}

void handleNonCursorPositionEvent()
{
    if (cursorMethodInProgress) {
        // It's a little shady posting an event while we're potentially in the middle of an
        // event tap callback, however this seems to be the best way to make sure the cursor
        // stays where we want at the exact moment that mission control activates. It's not
        // perfect, but it works better than trying to use a regular repeating timer to
        // position the cursor, using the IOHIDEventPost interface for positioning the cursor,
        // or using CGEventTapPostEvent to post another event from within the event tap the
        // officially supported way.
        postLeftMouseButtonEventWithUserData(kCGEventMouseMoved, 100, 0, kCursorPositionEventTag);
    }
}

void showMissionControlWithFullDesktopBarUsingCursorPositionMethod()
{
    cursorMethodInProgress = true;
    mousePositionedSuccessfully = false;
    cursorStart = currentMouseLocation();
    
    printf("Invoking mission control using cursor position method...\n");
    fflush(stdout);
    
    startEventTap();
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
    
    printf("Sending final cursor movement\n");
    CGPoint cursorDelta = accumulatedCursorMovementFromEventTap();
    moveCursor(cursorStart.x + cursorDelta.x, cursorStart.y + cursorDelta.y);
}
