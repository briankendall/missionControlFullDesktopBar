#import <Cocoa/Cocoa.h>
#import "wiggleMethod.h"
#import "app.h"
#import "events.h"

CGEventRef mouseMovementEventTapFunction(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *data);

static CFMachPortRef eventTapMachPortRef = NULL;
static CFRunLoopSourceRef eventTapRunLoopSourceRef = NULL;
static bool wigglingInProgress = false;
static CGPoint cursorStart;
static CGPoint cursorDelta = {0, 0};
static NSDate *wiggleStartTime = nil;
static int wiggleDuration = kWiggleDefaultDurationMS;
static int wiggleCount = 0;
static NSTimer *appStopTimer = nil;
static NSTimer *wiggleStepTimer = nil;


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

void performNextWiggleStep(int delayMS, void (^nextStep)(void))
{
    wiggleStepTimer = [NSTimer scheduledTimerWithTimeInterval:(delayMS / 1000.0)
                                                       target:[NSBlockOperation blockOperationWithBlock:nextStep]
                                                     selector:@selector(main)
                                                     userInfo:nil
                                                      repeats:NO];
}

void removeWiggleStepTimer()
{
    if (wiggleStepTimer && [wiggleStepTimer isValid]) {
        [wiggleStepTimer invalidate];
        wiggleStepTimer = nil;
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
        performNextWiggleStep(kTimeBetweenWiggleEventsMS, ^ (void) {
            wiggleCursor();
        });
        
    } else {
        // We now move the cursor to its original position plus the accumulated deltas
        // of all of the naturally occurring mouse events that we've observed, so that
        // the cursor ends up where the user expects it to be:
        performNextWiggleStep(0, ^ (void) {
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
        cleanUpAndFinish();
        return;
    }
    
    if (wigglingInProgress) {
        printf("Already wiggling\n");
        cleanUpAndFinish();
        return;
    }
    
    wigglingInProgress = false;
    wiggleDuration = inWiggleDuration;
    wiggleStartTime = nil;
    wiggleCount = 0;
    cursorDelta = CGPointMake(0, 0);
    
    printf("\nBeginning initial wait period for wiggle method\n");
    
    wiggleStepTimer = [NSTimer scheduledTimerWithTimeInterval:(kWiggleInitialWaitMS / 1000.0)
                                                       target:[NSBlockOperation blockOperationWithBlock:^{
        
        wigglingInProgress = true;
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
    stopEventTap();
    
    if (wigglingInProgress) {
        // Need to call this after stopEventTap() so that this event doesn't get snagged by the
        // event tap
        printf("Sending final cursor movement\n");
        moveCursor(cursorStart.x + cursorDelta.x, cursorStart.y + cursorDelta.y);
    }
    
    removeAppStopTimer();
    removeWiggleStepTimer();
    wigglingInProgress = false;
}

void wiggleMethodShutDown()
{
    destroyEventTap();
}

