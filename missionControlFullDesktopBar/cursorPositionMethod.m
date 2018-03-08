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
    
    NSLog(@"Received mouse positioning event!\n");
    fflush(stdout);
    mousePositionedSuccessfully = true;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.001 * NSEC_PER_SEC)), 
                   dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^ () {
        invokeMissionControl();
        
        // This is something of a race condition, but as far as I know there's no way to know exactly when Mission Control's
        // animation will start. But a wait time of 0.001 seconds seems to work very consistently, so 0.003 seconds should
        // work three times as very consistently!
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.003 * NSEC_PER_SEC)), 
                       dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^ () {
            //cleanUpAndFinish();
            postLeftMouseButtonEventWithUserData(kCGEventMouseMoved, cursorStart.x, cursorStart.y, kCursorPositionResetEventTag);
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
        NSLog(@"Received mouse reset event! loc: %.1f %.1f", p.x, p.y);
        NSLog(@".. check loc: %.1f %.1f     check loc2: %.1f %.1f", p2.x, p2.y, p3.x, p3.y);
        
        if (!CGPointEqualToPoint(p, p2)) {
            startEventTap();
            NSLog(@"**** Something went wrong! Reissuing reset mouse event!");
            postLeftMouseButtonEventWithUserData(kCGEventMouseMoved, cursorStart.x, cursorStart.y, kCursorPositionResetEventTag);
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

bool isCursorPositionResetEvent(CGEventRef event)
{
    return (CGEventGetIntegerValueField(event, kCGEventSourceUserData) == kCursorPositionResetEventTag);
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
    
    NSLog(@"Invoking mission control using cursor position method...");
    fflush(stdout);
    
    startEventTapAndResetCursorDelta();
    // For some reason, using the IOHIDPostEvent method of moving the mouse is unreliable here
    postLeftMouseButtonEventWithUserData(kCGEventMouseMoved, 100, 0, kCursorPositionEventTag);
    //moveCursor(100, 0);
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
    
    for(int i = 0; i < 4; ++i) {
        CGPoint p = currentMouseLocation();
        NSLog(@"... after cursor loc: %f %f", p.x, p.y);
        usleep(0.04 * USEC_PER_SEC);
    }
    
    //printf("Sending final cursor movement\n");
    CGPoint cursorDelta = CGPointMake(0,0);//accumulatedCursorMovementFromEventTap();
    // IOHIDPostEvent is also unreliable here
    //postLeftMouseButtonEvent(kCGEventMouseMoved, cursorStart.x + cursorDelta.x, cursorStart.y + cursorDelta.y);
    //moveCursor(cursorStart.x, cursorStart.y);
    //postLeftMouseButtonEvent(
    /*stopEventTap();
    
    for(int i = 0; i < 10; ++i) {
        CGPoint p = currentMouseLocation();
        NSLog(@"... after cursor loc: %f %f", p.x, p.y);
        usleep(0.04 * USEC_PER_SEC);
    }*/
    
    //moveCursor(cursorStart.x + cursorDelta.x, cursorStart.y + cursorDelta.y);
}
