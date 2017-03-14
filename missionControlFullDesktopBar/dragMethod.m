#import <Cocoa/Cocoa.h>
#import <unistd.h>
#import "CGSPrivate.h"
#import "events.h"
#import "app.h"
#import "invisibleWindow.h"

static bool mouseIsDown = false;
static bool appMouseIsDown = false;
static NSTimer *clickableWindowTimer = nil;

bool screenPositionContainsWindowOfThisApp(int x, int y)
{
    AXUIElementRef application, element;
    CFStringRef role;
    pid_t pid = getpid();
    
    application = AXUIElementCreateApplication(pid);
    
    if (!application) {
        return false;
    }
    
    // Because we're passing in a AXUIElementRef for this application
    // rather than the system-wide UI element, if the specified coordinates
    // contains a window of this app, then AXUIElementCopyElementAtPosition
    // will return an element reference that is a window or an element
    // contained within a window. Otherwise it will return an application
    // element.
    
    AXError error = AXUIElementCopyElementAtPosition(application, x, y, &element);
    
    if (error != kAXErrorSuccess || !element) {
        CFRelease(application);
        return false;
    }
    
    error = AXUIElementCopyAttributeValue(element, kAXRoleAttribute, (CFTypeRef *)&role); 
    
    if (error != kAXErrorSuccess || !role) {
        CFRelease(application);
        CFRelease(element);
        return false;
    }
    
    bool isNotApplication = (CFStringCompare(role, kAXApplicationRole, 0) != kCFCompareEqualTo);
    CFRelease(role);
    CFRelease(application);
    CFRelease(element);
    
    return isNotApplication;
}

void removeClickableWindowTimer()
{
    if (clickableWindowTimer && [clickableWindowTimer isValid]) {
        [clickableWindowTimer invalidate];
        clickableWindowTimer = nil;
    }
}

void checkWindowClickable(CGPoint p, CFTimeInterval startTime)
{
    if (screenPositionContainsWindowOfThisApp(p.x, p.y)) {
        printf("Posting mouse event\n");
        removeClickableWindowTimer();
        
        // Now we click down on the window. The next step occurs when the window receives a mouseDown event
        postLeftMouseButtonEvent(kCGEventLeftMouseDown, p.x, p.y);
        mouseIsDown = true;
    }
    
    if ((CACurrentMediaTime() - startTime) > 0.5) {
        // A safeguard against the window never becoming visible
        printf("Error: Invisible window was never clickable... aborting!\n");
        removeClickableWindowTimer();
        cleanUpAndFinish();
    }

}

void positionInvisibleWindowUnderCursorAndOrderFront(CGPoint flippedP)
{    
    // First step: position our invisible, draggable window directly underneath of the cursor
    flippedP.y += kInvisibleWindowSize;
    [sharedInvisibleWindow() setFrameTopLeftPoint:NSMakePoint(flippedP.x - kInvisibleWindowSize/2,
                                                              flippedP.y - kInvisibleWindowSize/2)];
    [sharedInvisibleWindow() makeKeyAndOrderFront:NSApp];
}

void showMissionControlWithFullDesktopBarUsingDragMethod(bool useInternalMouseDown)
{
    bool alreadyInMissionControl = false;
    
    if (!determineIfInMissionControl(&alreadyInMissionControl)) {
        return;
    }
    
    if (alreadyInMissionControl) {
        printf("Already in mission control\n");
        invokeMissionControl();
        return;
    }
    
    if ([NSEvent pressedMouseButtons] & 0x01) {
        printf("Mouse is already pressed\n");
        invokeMissionControl();
        return;
    }
    
    [sharedInvisibleView() resetTracking];
    
    CGPoint p = currentMouseLocation();
    CGPoint flippedP = currentUnflippedMouseLocation();
    positionInvisibleWindowUnderCursorAndOrderFront(flippedP);
    
    // Because we are in the realm of unholy hacks, for whatever reason sending
    // the window a mouse event directly doesn't trigger a drag event unless
    // the window has received at least one regular mouse event already.
    if (useInternalMouseDown && [sharedInvisibleView() hasReceivedAnyMouseDowns]) {
        printf("Posting internal mouse event\n");
        postInternalMouseEvent(NSEventTypeLeftMouseDown, sharedInvisibleWindow());
        appMouseIsDown = true;
        
    } else {
        printf("Waiting for window to be clickable\n");
        
        // This should hopefully ensure the window becomes visible and appears on top of everything:
        CGSSetWindowLevel(CGSMainConnectionID(),
                          (CGSWindowID)sharedInvisibleWindow().windowNumber, NSPopUpMenuWindowLevel);
        CGSOrderWindow(CGSMainConnectionID(),
                       (CGSWindowID)sharedInvisibleWindow().windowNumber,
                       kCGSOrderAbove, 0);
        
        removeClickableWindowTimer();
        CFTimeInterval startTime = CACurrentMediaTime();
        
        // Second step: wait until the window is properly under the cursor and can be clicked
        clickableWindowTimer = [NSTimer scheduledTimerWithTimeInterval:0.001 repeats:YES block:^(NSTimer *timer) {
            checkWindowClickable(p, startTime);
        }];
    }
}

void dragMethodCleanUp()
{
    if (mouseIsDown) {
        CGPoint p = currentMouseLocation();
        postLeftMouseButtonEvent(kCGEventLeftMouseUp, p.x, p.y);
        mouseIsDown = false;
    }
    
    if (appMouseIsDown) {
        postInternalMouseEvent(NSEventTypeLeftMouseUp, sharedInvisibleWindow());
        appMouseIsDown = false;
    }
    
    removeClickableWindowTimer();
    [sharedInvisibleWindow() orderOut:nil];
}

void dragMethodShutDown()
{
    // Nothing to do here presently
}
