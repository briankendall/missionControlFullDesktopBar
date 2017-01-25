#import <Cocoa/Cocoa.h>

#define kWiggleMovementEventMarker 0xDADABABACACA
#define kFinalMovementEventMarker 0xCACABABADADA

#define kWiggleDurationMS 200
#define kWiggleRate 30

CFMachPortRef eventTapMachPortRef;
CGPoint cursorStart;
CGPoint cursorDelta = {0, 0};
int timerCount = 0;

CGPoint currentMouseLocation()
{
    CGEventRef event = CGEventCreate(NULL);
    
    if (!event) {
        fprintf(stderr, "Error: could not create event\n");
        return CGPointMake(0,0);
    }
    
    CGPoint loc = CGEventGetLocation(event);
    CFRelease(event);
    return loc;
}

void moveCursor(double x, double y, int64_t eventMaker)
{
    CGEventRef event = CGEventCreateMouseEvent(NULL, kCGEventMouseMoved, CGPointMake(x, y), 0);
    
    if (!event) {
        fprintf(stderr, "Error: could not create mouse event\n");
        return;
    }
    
    CGEventSetIntegerValueField(event, kCGEventSourceUserData, eventMaker);
    CGPoint prevMouseLocation = currentMouseLocation();
    // Mouse location can be a decimal value, so for this calculation to work correctly we have to round to the nearest integer:
    CGEventSetIntegerValueField(event, kCGMouseEventDeltaX, x-round(prevMouseLocation.x));
    CGEventSetIntegerValueField(event, kCGMouseEventDeltaY, y-round(prevMouseLocation.y));
    CGEventPost(kCGSessionEventTap, event);
    CFRelease(event);
}

void moveCursorTimerCallback()
{
    ++timerCount;
    
    if (timerCount < (kWiggleDurationMS*kWiggleRate/1000)) {
        moveCursor(timerCount%2, 0, kWiggleMovementEventMarker);
    }
    
    if (timerCount == (kWiggleDurationMS*kWiggleRate/1000)) {
        moveCursor(cursorStart.x + cursorDelta.x, cursorStart.y + cursorDelta.y, kFinalMovementEventMarker);
    }
    
    if (timerCount > (kWiggleDurationMS*kWiggleRate/1000*2)) {
        printf("NB: failsafe\n");
        CFRunLoopStop(CFRunLoopGetCurrent());
    }
}

CGEventRef eventTapFunction(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *data)
{
    static int64_t accumulatedFakeDeltaX = 0, accumulatedFakeDeltaY = 0;
    
    // Event taps can occasionally be disabled if they block for too long.  This will probably never happen, but
    // just in case it does, we want to do this:
    if (type == kCGEventTapDisabledByTimeout) {
        CGEventTapEnable(eventTapMachPortRef, true);
        return event;
    }
    
    int64_t eventUserData = CGEventGetIntegerValueField(event, kCGEventSourceUserData);
    CGPoint *cursorDelta = (CGPoint *)data;
    
    int64_t dx = CGEventGetIntegerValueField(event, kCGMouseEventDeltaX);
    int64_t dy = CGEventGetIntegerValueField(event, kCGMouseEventDeltaY);
    
    if (eventUserData == kWiggleMovementEventMarker) {
        //NSLog(@"Fake movement delta: %lld %lld", dx, dy);
        accumulatedFakeDeltaX += dx;
        accumulatedFakeDeltaY += dy;
        
    } else if (eventUserData == kFinalMovementEventMarker) {
        //CGPoint loc = CGEventGetLocation(event);
        //NSLog(@"Final movement to: %f %f", loc.x, loc.y);
        CFRunLoopStop(CFRunLoopGetCurrent());
        
    } else {
        //NSLog(@"Real movement delta: %lld %lld ... total delta is now: %f %f", dx, dy, cursorDelta->x, cursorDelta->y);
        cursorDelta->x += (dx - accumulatedFakeDeltaX);
        cursorDelta->y += (dy - accumulatedFakeDeltaY);
        accumulatedFakeDeltaX = accumulatedFakeDeltaY = 0;
    }
    
    return event;
}

void invokeMissionControl()
{
    NSString *path = [[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier:@"com.apple.exposelauncher"];
    NSBundle *bundle = [NSBundle bundleWithPath:path];
    NSString *executablePath = [bundle executablePath];
    [NSTask launchedTaskWithLaunchPath:executablePath arguments:@[]];
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        cursorStart = currentMouseLocation();
        //NSLog(@"Original position: %f %f", cursorStart.x, cursorStart.y);
        
        CGEventMask eventMask = (CGEventMaskBit(kCGEventLeftMouseDragged) | CGEventMaskBit(kCGEventRightMouseDragged) |
                                 CGEventMaskBit(kCGEventOtherMouseDragged) | CGEventMaskBit(kCGEventMouseMoved));
        CFMachPortRef eventTapMachPortRef = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionListenOnly,
                                                             eventMask, (CGEventTapCallBack)eventTapFunction, &cursorDelta);
        
        if (!eventTapMachPortRef) {
            fprintf(stderr, "Error: could not create event tap\n");
            return 1;
        }
        
        CFRunLoopSourceRef eventTapRunLoopSourceRef = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTapMachPortRef, 0);
        
        if (!eventTapRunLoopSourceRef) {
            fprintf(stderr, "Error: could not create event tap run loop source\n");
            return 1;
        }
        
        CFRunLoopAddSource(CFRunLoopGetCurrent(), eventTapRunLoopSourceRef, kCFRunLoopDefaultMode);
        
        [NSTimer scheduledTimerWithTimeInterval:(1.0/kWiggleRate)
                                         target:[NSBlockOperation blockOperationWithBlock:^{ moveCursorTimerCallback(); }]
                                       selector:@selector(main)
                                       userInfo:nil
                                        repeats:YES];
        
        invokeMissionControl();
        CFRunLoopRun();
        
        CFRelease(eventTapRunLoopSourceRef);
        CFRelease(eventTapMachPortRef);
    }
    return 0;
}
