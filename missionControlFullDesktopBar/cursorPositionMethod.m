#import <Cocoa/Cocoa.h>
#import "cursorPositionMethod.h"
#import "app.h"
#import "events.h"
#import "eventTap.h"

#define kCursorPositionEventTag 0x4201337

//static CFMachPortRef eventTapMachPortRef = NULL;
static CGPoint cursorStart;
static bool cursorMethodInProgress = false;
static bool mousePositionedSuccessfully = false;
/*
static CGEventRef mouseMovementEventTapFunction(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *data)
{
    // Event taps can occasionally be disabled if they block for too long.  This will probably never happen, but
    // just in case it does, we want to do this:
    if (type == kCGEventTapDisabledByTimeout) {
        CGEventTapEnable(eventTapMachPortRef, true);
        return event;
    }
    
    if (type == kCGEventTapDisabledByUserInput) {
        // We intentionall disabled the event tap
        return event;
    }
    
    pid_t pid = (pid_t)CGEventGetIntegerValueField(event, kCGEventSourceUnixProcessID);
    CGPoint p = CGEventGetLocation(event);
    int x = round(p.x);
    int y = round(p.y);
    
    printf("Received mouse event, pid: %d, p: %d %d\n", pid, x, y);
    fflush(stdout);
    
    if (CGEventGetIntegerValueField(event, kCGEventSourceUnixProcessID) == getpid() || (x == 100 && y == 0)) {
        printf("Bing! mouseStart: %f %f\n", mouseStart.x, mouseStart.y);
        fflush(stdout);
        CGEventTapEnable(eventTapMachPortRef, false);
        
        extern int CoreDockSendNotification(CFStringRef);
        CoreDockSendNotification(CFSTR("com.apple.expose.awake"));
        
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.001 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^ () {
            printf("Posting next mouse event!\n");
            fflush(stdout);
            //CGEventRef event2 = CGEventCreateMouseEvent(NULL, kCGEventMouseMoved, mouseStart, kCGMouseButtonLeft);
            //CGEventPost(kCGHIDEventTap, event2);
            //CGEventTapPostEvent(proxy, event2);
            //CFRelease(event2);
            // For whatever reason, this event is not always successfully posted unless we use the IOHIDPostEvent API!
            moveCursor(mouseStart.x, mouseStart.y);
            
            CFRunLoopStop(CFRunLoopGetCurrent());
        });
        
    }
    
    return event;
}
*/
// 

void handleCursorPositionEventAndPostNext()
{
    if (mousePositionedSuccessfully) {
        return;
    }
    
    printf("Received mouse positioning event!\n");
    fflush(stdout);
    mousePositionedSuccessfully = true;
    
    //CGEventTapEnable(eventTapMachPortRef, false);
    
    //dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^ () {
        //extern int CoreDockSendNotification(CFStringRef);
        //CoreDockSendNotification(CFSTR("com.apple.expose.awake"));
        invokeMissionControl();
        
        // This is something of a race condition, but as far as I know there's no way to know exactly when Mission Control's
        // animation will start. But a wait time of 0.001 seconds seems to work very consistently, so 0.003 seconds should
        // work three times as very consistently!
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.003 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^ () {
            //CGEventRef event2 = CGEventCreateMouseEvent(NULL, kCGEventMouseMoved, cursorStart, kCGMouseButtonLeft);
            //CGEventPost(kCGHIDEventTap, event2);
            //CGEventTapPostEvent(proxy, event2);
            //CFRelease(event2);
            // For whatever reason, this event is not always successfully posted unless we use the IOHIDPostEvent API!
            //moveCursor(cursorStart.x, cursorStart.y);
            
            //CFRunLoopStop(CFRunLoopGetCurrent());
            
            printf("Done! %lf\n", CACurrentMediaTime());
            cleanUpAndFinish();
        });
    //});
}

bool isCursorPositionEvent(CGEventRef event, CGEventTapProxy proxy)
{
    //printf("event pid: %llu\n", CGEventGetIntegerValueField(event, kCGEventSourceUnixProcessID));
    //printf("proc pid: %u\n", getpid());
    //printf("event x: %f\n", CGEventGetLocation(event).x);
    //fflush(stdout);
    
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
    
    printf("Start! %lf\n", CACurrentMediaTime());
    printf("Invoking mission control using cursor position method...\n");
    fflush(stdout);
    
    startEventTap();
    /*
    eventTapMachPortRef = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionListenOnly,
                                           CGEventMaskBit(kCGEventMouseMoved), (CGEventTapCallBack)mouseMovementEventTapFunction, NULL);
    
    if (!eventTapMachPortRef) {
        NSLog(@"Error: could not create event tap");
        return;
    }
    
    CFRunLoopSourceRef eventTapRunLoopSourceRef = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTapMachPortRef, 0);
    
    if (!eventTapRunLoopSourceRef) {
        NSLog(@"Error: could not create event tap run loop source");
        return;
    }
    
    CFRunLoopAddSource(CFRunLoopGetCurrent(), eventTapRunLoopSourceRef, kCFRunLoopDefaultMode);
    */
    
    // For whatever reason, our event tap may not catch this mouse event unless we post it using the Quartz event services API
    //postLeftMouseButtonEventWithUserData(kCGEventMouseMoved, 100, 0, kCursorPositionEventTag);
    
    moveCursor(100, 0);
    //createMousePositionTimer();
    ensureAppStopsAfterDuration(100);
    
    //CGEventRef event = CGEventCreateMouseEvent(NULL, kCGEventMouseMoved, CGPointMake(100, 0), kCGMouseButtonLeft);
    //CGEventPost(kCGHIDEventTap, event);
    //CFRelease(event);
    //moveCursor(100, 0);
    
    //extern int CoreDockSendNotification(CFStringRef);
    //CoreDockSendNotification(CFSTR("com.apple.expose.awake"));
    
    //usleep(0.002 * USEC_PER_SEC);
    
    //event = CGEventCreateMouseEvent(NULL, kCGEventMouseMoved, p, kCGMouseButtonLeft);
    //CGEventPost(kCGHIDEventTap, event);
    //CFRelease(event);
    /*
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^ () {
        printf("Failed!\n");
        CFRunLoopStop(CFRunLoopGetCurrent());
    });
    
    CFRunLoopRun();
    
    printf("Done! %lf\n", CACurrentMediaTime());
    fflush(stdout);
     */
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
    //CGWarpMouseCursorPosition(CGPointMake(cursorStart.x + cursorDelta.x, cursorStart.y + cursorDelta.y));
}
