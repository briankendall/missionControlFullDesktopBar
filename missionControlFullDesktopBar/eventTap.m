#import <Cocoa/Cocoa.h>
#import "eventTap.h"
#import "app.h"
#import "events.h"
#import "wiggleMethod.h"
#import "cursorPositionMethod.h"

CGEventRef mouseMovementEventTapFunction(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *data);

static CFMachPortRef eventTapMachPortRef = NULL;
static CFRunLoopSourceRef eventTapRunLoopSourceRef = NULL;
static CGPoint cursorDelta = {0, 0};

bool createEventTap()
{
    CGEventMask eventMask = (CGEventMaskBit(kCGEventLeftMouseDragged) | CGEventMaskBit(kCGEventRightMouseDragged) |
                             CGEventMaskBit(kCGEventOtherMouseDragged) | CGEventMaskBit(kCGEventMouseMoved));
    
    eventTapMachPortRef = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionListenOnly,
                                           eventMask, (CGEventTapCallBack)mouseMovementEventTapFunction, NULL);
    
    if (!eventTapMachPortRef) {
        NSLog(@"Error: could not create event tap");
        return false;
    }
    
    eventTapRunLoopSourceRef = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTapMachPortRef, 0);
    
    if (!eventTapRunLoopSourceRef) {
        NSLog(@"Error: could not create event tap run loop source");
        return false;
    }
    
    CFRunLoopAddSource(CFRunLoopGetCurrent(), eventTapRunLoopSourceRef, kCFRunLoopDefaultMode);
    
    return true;
}

bool startEventTap()
{
    if (eventTapMachPortRef && eventTapRunLoopSourceRef) {
        CGEventTapEnable(eventTapMachPortRef, true);
        return true;
    } else {
        return createEventTap();
    }
}

bool startEventTapAndResetCursorDelta()
{
    cursorDelta = CGPointMake(0, 0);
    return startEventTap();
}

void stopEventTap()
{
    if (eventTapMachPortRef) {
        CGEventTapEnable(eventTapMachPortRef, false);
    }
}

void destroyEventTap()
{
    if (eventTapRunLoopSourceRef) {
        CFRelease(eventTapRunLoopSourceRef);
        eventTapRunLoopSourceRef = NULL;
    }
    
    if (eventTapMachPortRef) {
        CFRelease(eventTapMachPortRef);
        eventTapMachPortRef = NULL;
    }
}

void accumulateNaturalMouseMovement(CGEventRef event)
{
    // Because we're using IOHIDPostEvent to create mouse events, these artificial
    // mouse events will appear to come from the same source as the actual mouse.
    // This has the advantage that there won't be (or at least it doesn't seem like
    // there will be) any discrepencies in the deltas reported by these events. I
    // tried using CGEventPost instead, but it resulted in both the natural and
    // artificial mouse events having incorrect deltas, making it impossible to
    // take how the user was moving their physical mouse. Using IOHIDPostEvent does
    // seem to work around that issue.
    int64_t dx = CGEventGetIntegerValueField(event, kCGMouseEventDeltaX);
    int64_t dy = CGEventGetIntegerValueField(event, kCGMouseEventDeltaY);
    cursorDelta.x += dx;
    cursorDelta.y += dy;
    
    CGPoint location = CGEventGetLocation(event);
    printf("Received regular movement to: (%f , %f),   reported delta: (%lld,%lld)\n", location.x, location.y, dx, dy);
}

CGEventRef mouseMovementEventTapFunction(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *data)
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
    
    if (isWiggleEvent(event)) {
        processWiggleEventAndPostNext(event);
    } else if (isCursorPositionEvent(event)) {
        handleCursorPositionEventAndPostNext();
    } else {
        accumulateNaturalMouseMovement(event);
    }
    
    return event;
}

CGPoint accumulatedCursorMovementFromEventTap()
{
    return cursorDelta;
}
