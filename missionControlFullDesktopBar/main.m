#import <Cocoa/Cocoa.h>
#import "processes.h"

#define kWiggleInitialWaitMS 60
#define kWiggleDurationMS 120
#define kTimeBetweenWiggleEventsMS 5
#define kMaxRunningTimeMS 400
#define kWiggleMinCount 5

#define kMessageMissionControlTriggerPressed 1
#define kMessageMissionControlTriggerReleased 2

void stopEventTap();
void removeAppStopTimer();
void cleanUpAndFinish();

static bool daemonized = false;
CFMachPortRef eventTapMachPortRef = NULL;
CFRunLoopSourceRef eventTapRunLoopSourceRef = NULL;
CGPoint cursorStart;
CGPoint cursorDelta = {0, 0};
NSDate *wiggleStartTime = nil;
int wiggleCount = 0;
NSDate *lastMissionControlInvocationTime = nil;
NSTimer *appStopTimer = nil;
CFMessagePortRef localPort = nil;
CFRunLoopSourceRef localPortRunLoopSource = nil;

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
    
    if (wiggleCount < kWiggleMinCount || durationMS < kWiggleDurationMS) {
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

void invokeMissionControl()
{
    extern int CoreDockSendNotification(CFStringRef);
    CoreDockSendNotification(CFSTR("com.apple.expose.awake"));
    lastMissionControlInvocationTime = [NSDate date];
}

bool accessibilityAvailable()
{
    return AXIsProcessTrustedWithOptions((CFDictionaryRef)@{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @true});
}

// Sets the memory result points to to true if Mission Control is up. Returns true if able to
// successfully determine the state of Mission Control, false if an error occurred.
bool determineIfInMissionControl(bool *result)
{
    (*result) = false;
    NSArray *apps = [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.dock"];
    
    if (apps.count == 0) {
        NSLog(@"Error: Dock is not running!");
        return false;
    }
    
    NSRunningApplication *dock = apps[0];
    AXUIElementRef dockElement = AXUIElementCreateApplication(dock.processIdentifier);
    
    if (!dockElement) {
        NSLog(@"Error: cannot create AXUIElementRef for Dock");
        return false;
    }
    
    CFArrayRef children = NULL;
    AXError error = AXUIElementCopyAttributeValue(dockElement, kAXChildrenAttribute, (const void **)&children);
    
    if (error != kAXErrorSuccess || !children) {
        NSLog(@"Error: cannot get Dock children UI elements");
        CFRelease(dockElement);
        return false;
    }
    
    for(int i = 0; i < CFArrayGetCount(children); ++i) {
        AXUIElementRef child = (AXUIElementRef)CFArrayGetValueAtIndex(children, i);
        CFStringRef identifier;
        error = AXUIElementCopyAttributeValue(child, kAXIdentifierAttribute, (CFTypeRef *)&identifier);
        
        if (error != kAXErrorSuccess || !identifier || CFGetTypeID(identifier) != CFStringGetTypeID()) {
            continue;
        }
        
        // We can tell if Mission Control is already up if the Dock has a UI element with
        // an AXIdentifier property of "mc". This is undocumented and therefore is liable
        // to change, but hopefully not anytime soon!
        if (CFStringCompare(identifier, CFSTR("mc"), 0) == kCFCompareEqualTo) {
            (*result) = true;
            break;
        }
    }
    
    CFRelease(children);
    CFRelease(dockElement);
    
    return true;
}

bool appIsAlreadyRunning()
{
    int sysctlError = 0;
    unsigned int matches = 0;
    NSString *processName = [[NSProcessInfo processInfo] processName];
    
    // Unfortunately we can't use NSRunningApplication as this app will not show up in its list.
    // We instead have to use a much lower level way of getting all the running processes:
    int error = getCountOfProcessesWithName([processName cStringUsingEncoding:NSUTF8StringEncoding], &matches, &sysctlError);
    
    return (error == kSuccess && matches > 1);
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

void ensureAppStopsAfterDuration(double durationMS)
{
    removeAppStopTimer();
    appStopTimer = [NSTimer scheduledTimerWithTimeInterval:(durationMS / 1000.0)
                                     target:[NSBlockOperation blockOperationWithBlock:^{ cleanUpAndFinish(); }]
                                   selector:@selector(main)
                                   userInfo:nil
                                    repeats:NO];
}

void removeAppStopTimer()
{
    if (appStopTimer && [appStopTimer isValid]) {
        [appStopTimer invalidate];
        appStopTimer = nil;
    }
}

void cleanUpAndFinish()
{
    printf("Cleaning up\n");
    removeAppStopTimer();
    stopEventTap();
    
    if (!daemonized) {
        printf("Shutting down\n");
        destroyEventTap();
        
        if (localPortRunLoopSource) {
            CFRelease(localPortRunLoopSource);
            localPortRunLoopSource = nil;
        }
        
        if (localPort) {
            CFRelease(localPort);
            localPort = nil;
        }
        
        [NSApp terminate:0];
    }
}

void showMissionControlWithFullDesktopBar()
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
        
        ensureAppStopsAfterDuration(kMaxRunningTimeMS);
        wiggleCursor();
    }]
                                   selector:@selector(main)
                                   userInfo:nil
                                    repeats:NO];
}

void releaseMissionControl()
{
    double timeSince = -[lastMissionControlInvocationTime timeIntervalSinceNow];
    bool alreadyInMissionControl = false;
    determineIfInMissionControl(&alreadyInMissionControl);
    
    if (timeSince > 0.5 && alreadyInMissionControl) {
        printf("Released mission control trigger when in mission control after adequate time!\n");
        invokeMissionControl();
    }
}

bool hasArg(int argc, const char * argv[], const char *arg)
{
    for(int i = 0; i < argc; ++i) {
        if (strcmp(argv[i], arg) == 0) {
            return true;
        }
    }
    
    return false;
}

static CFDataRef receivedMessageAsDaemon(CFMessagePortRef port, SInt32 messageID, CFDataRef data, void *info)
{
    if (messageID == kMessageMissionControlTriggerPressed) {
        showMissionControlWithFullDesktopBar();
    } else if (messageID == kMessageMissionControlTriggerReleased) {
        releaseMissionControl();
    }
    
    return NULL;
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        if (!accessibilityAvailable()) {
            NSLog(@"Cannot run without Accessibility");
            return 1;
        }
        
        CFMessagePortRef remotePort = CFMessagePortCreateRemote(nil,
                                                                CFSTR("net.briankendall.missionControlFullDesktopBar"));
        
        if (remotePort) {
            CFTimeInterval timeout = 3.0;
            int message = ((hasArg(argc, argv, "-r") || hasArg(argc, argv, "--release"))
                           ? kMessageMissionControlTriggerReleased : kMessageMissionControlTriggerPressed);
            SInt32 status = CFMessagePortSendRequest(remotePort, message, nil, timeout, timeout, nil, nil);
            
            if (status != kCFMessagePortSuccess) {
                fprintf(stderr, "Failed to signal daemon\n");
                return 1;
            }
            
            CFRelease(remotePort);
            return 0;
        }
        
        if (hasArg(argc, argv, "-d") || hasArg(argc, argv, "--daemon")) {
            if (fork() == 0) {
                printf("Running as daemon\n");
                const char *args[3];
                args[0] = argv[0];
                args[1] = "--daemonized";
                args[2] = NULL;
                execve(args[0], (char * const *)args, NULL);
            } else {
                return 0;
            }
        }
        
        NSApplicationLoad();
        
        if (hasArg(argc, argv, "--daemonized")) {
            daemonized = true;
            localPort = CFMessagePortCreateLocal(nil, CFSTR("net.briankendall.missionControlFullDesktopBar"),
                                                 receivedMessageAsDaemon, nil, nil);
            CFRunLoopSourceRef localPortRunLoopSource = CFMessagePortCreateRunLoopSource(nil, localPort, 0);
            CFRunLoopAddSource(CFRunLoopGetCurrent(), localPortRunLoopSource, kCFRunLoopCommonModes);
            
        } else if (appIsAlreadyRunning()) {
            // Don't want to interfere with an already running instance of this
            // app, so we just invoke Mission Control and quit
            NSLog(@"Already running");
            return 0;
        }
        
        showMissionControlWithFullDesktopBar();
        
        return NSApplicationMain(argc, argv);;
    }
}
