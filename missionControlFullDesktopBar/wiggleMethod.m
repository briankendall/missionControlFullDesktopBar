#import <Cocoa/Cocoa.h>
#import "wiggleMethod.h"
#import "app.h"

CGEventRef mouseMovementEventTapFunction(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *data);

static CFMachPortRef eventTapMachPortRef = NULL;
static CFRunLoopSourceRef eventTapRunLoopSourceRef = NULL;
static CGPoint cursorStart;
static CGPoint cursorDelta = {0, 0};
static NSDate *wiggleStartTime = nil;
static int wiggleDuration = kWiggleDefaultDurationMS;
static int wiggleCount = 0;
static NSTimer *appStopTimer = nil;

// Low level event posting, with code by George Warner
io_connect_t getIOKitEventDriver(void)
{
    static  mach_port_t sEventDrvrRef = 0;
    mach_port_t masterPort, service, iter;
    kern_return_t    kr;
    
    if (!sEventDrvrRef)
    {
        // Get master device port
        kr = IOMasterPort( bootstrap_port, &masterPort );
        if (kr != KERN_SUCCESS) {
            NSLog(@"get_event_driver() error, IOMasterPort returned error code: %d", kr);
            return (io_connect_t)NULL;
        }
        
        kr = IOServiceGetMatchingServices( masterPort, IOServiceMatching(kIOHIDSystemClass ), &iter );
        if (kr != KERN_SUCCESS) {
            NSLog(@"get_event_driver() error, IOServiceGetMatchingServices returned error code: %d", kr);
            return (io_connect_t)NULL;
        }
        
        service = IOIteratorNext( iter );
        if (kr != KERN_SUCCESS) {
            NSLog(@"get_event_driver() error, IOIteratorNext returned error code: %d", kr);
            return (io_connect_t)NULL;
        }
        
        kr = IOServiceOpen( service, mach_task_self(), kIOHIDParamConnectType, &sEventDrvrRef );
        if (kr != KERN_SUCCESS) {
            NSLog(@"get_event_driver() error, IOServiceOpen returned error code: %d", kr);
            return (io_connect_t)NULL;
        }
        
        IOObjectRelease( service );
        IOObjectRelease( iter );
    }
    return sEventDrvrRef;
}

void moveCursor(short x, short y)
{
    NXEventData event;
    IOGPoint pos = {x, y};
    kern_return_t err;
    
    bzero(&event, sizeof(NXEventData));
    
    IOOptionBits options = kIOHIDSetCursorPosition;
    err = IOHIDPostEvent(getIOKitEventDriver(), NX_MOUSEMOVED, pos, &event, kNXEventDataVersion, 0, options);
    
    if (err != KERN_SUCCESS) {
        NSLog(@"Warning: Failed to post mouse event. Error: %d", err);
    }
}


CGPoint currentMouseLocation()
{
    CGEventRef event = CGEventCreate(NULL);
    
    if (!event) {
        NSLog(@"Error: could not create event");
        return CGPointMake(0,0);
    }
    
    CGPoint loc = CGEventGetLocation(event);
    CFRelease(event);
    return loc;
}

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

void removeAppStopTimer()
{
    if (appStopTimer && [appStopTimer isValid]) {
        [appStopTimer invalidate];
        appStopTimer = nil;
    }
}

void ensureAppStopsAfterDuration(double durationMS)
{
    removeAppStopTimer();
    appStopTimer = [NSTimer scheduledTimerWithTimeInterval:(durationMS / 1000.0)
                                                    target:[NSBlockOperation blockOperationWithBlock:^{
        cleanUpAndFinish();
    }]
                                                  selector:@selector(main)
                                                  userInfo:nil
                                                   repeats:NO];
}

void wiggleCursor()
{
    moveCursor(wiggleCount%2+1, 1);
}

bool isWiggleEvent(CGEventRef event)
{
    return CGEventGetIntegerValueField(event, kCGEventSourceUnixProcessID) == getpid();
}

void processWiggleEventAndPostNext(CGEventRef event)
{
    if (wiggleStartTime == nil) {
        wiggleStartTime = [NSDate date];
    }
    
    double durationMS = -[wiggleStartTime timeIntervalSinceNow] * 1000.0;
    ++wiggleCount;
    
    CGPoint location = CGEventGetLocation(event);
    printf("Received WIGGLE movement to: (%f , %f),   wiggleCount: %d     duration: %f\n",
           location.x, location.y, wiggleCount, durationMS);
    
    if (wiggleCount < kWiggleMinCount || durationMS < wiggleDuration) {
        // Keep on wiggling...
        // Waiting a little bit of time between receiving an event and posting it just so that
        // we don't flood the system with artificial mouse events
        dispatch_time_t time = dispatch_time(DISPATCH_TIME_NOW, kTimeBetweenWiggleEventsMS * NSEC_PER_MSEC);
        dispatch_after(time, dispatch_get_main_queue(), ^(void){
            wiggleCursor();
        });
        
    } else {
        // We now move the cursor to its original position plus the accumulated deltas
        // of all of the naturally occurring mouse events that we've observed, so that
        // the cursor ends up where the user expects it to be:
        printf("sending final movement...\n");
        dispatch_async(dispatch_get_main_queue(), ^(void){
            stopEventTap();
            // Need to call this after stopEventTap() so that this event doesn't get snagged by the
            // event tap
            moveCursor(cursorStart.x + cursorDelta.x, cursorStart.y + cursorDelta.y);
            cleanUpAndFinish();
        });
        
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
    } else {
        accumulateNaturalMouseMovement(event);
    }
    
    return event;
}

void showMissionControlWithFullDesktopBarUsingWiggleMethod(int inWiggleDuration)
{
    bool alreadyInMissionControl = false;
    
    if (!determineIfInMissionControl(&alreadyInMissionControl)) {
        return;
    }
    
    invokeMissionControl();
    
    if (alreadyInMissionControl) {
        // No need to do any cursor wiggling if we're already in Mission
        // Control, so in that case we can just quit here.
        printf("Already in Mission Control\n");
        return;
    }
    
    wiggleDuration = inWiggleDuration;
    wiggleStartTime = nil;
    wiggleCount = 0;
    cursorDelta = CGPointMake(0, 0);
    
    printf("\n\nBeginning initial wait period\n");
    
    [NSTimer scheduledTimerWithTimeInterval:(kWiggleInitialWaitMS / 1000.0)
                                     target:[NSBlockOperation blockOperationWithBlock:^{
        
        cursorStart = currentMouseLocation();
        printf("Original position: %f %f\n", cursorStart.x, cursorStart.y);
        
        if (!startEventTap()) {
            return;
        }
        
        ensureAppStopsAfterDuration(kMaxRunningTimeBufferMS + wiggleDuration);
        wiggleCursor();
    }]
                                   selector:@selector(main)
                                   userInfo:nil
                                    repeats:NO];
}

void wiggleMethodCleanUp()
{
    removeAppStopTimer();
    stopEventTap();
}

void wiggleMethodShutDown()
{
    destroyEventTap();
}

