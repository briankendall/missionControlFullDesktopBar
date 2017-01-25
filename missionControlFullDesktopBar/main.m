#import <Cocoa/Cocoa.h>
#import "processes.h"

#define kWiggleInitialWaitMS 60
#define kWiggleDurationMS 100
#define kTimeBetweenWiggleEventsMS 5
#define kMaxRunningTimeMS 400
#define kWiggleMinCount 5

CFMachPortRef eventTapMachPortRef = NULL;
CFRunLoopSourceRef eventTapRunLoopSourceRef = NULL;
CGPoint cursorStart;
CGPoint cursorDelta = {0, 0};
NSDate *wiggleStartTime = nil;
int wiggleCount = 0;

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
    CGPoint location = CGEventGetLocation(event);
    // Artificial movement created with IOHIDPostEvent will always have no decimal component
    // Also, there's only one of two positions we're moving the mouse to when wiggling it:
    return ((location.x == 1.0 && location.y == 1.0) || (location.x == 2.0 && location.y == 1.0));
}

void processWiggleEventAndPostNext(CGEventRef event)
{
    if (wiggleStartTime == nil) {
        wiggleStartTime = [NSDate date];
    }
    
    double durationMS = -[wiggleStartTime timeIntervalSinceNow] * 1000.0;
    ++wiggleCount;
    
    CGPoint location = CGEventGetLocation(event);
    NSLog(@"Received WIGGLE movement to: (%f , %f),   wiggleCount: %d     duration: %f", location.x, location.y, wiggleCount, durationMS);
    
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
        NSLog(@"sending final movement...");
        dispatch_async(dispatch_get_main_queue(), ^(void){
            moveCursor(cursorStart.x + cursorDelta.x, cursorStart.y + cursorDelta.y);
            CFRunLoopStop(CFRunLoopGetCurrent());
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
    NSLog(@"Received regular movement to: (%f , %f),   reported delta: (%lld,%lld)", location.x, location.y, dx, dy);
}

CGEventRef mouseMovementEventTapFunction(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *data)
{
    // Event taps can occasionally be disabled if they block for too long.  This will probably never happen, but
    // just in case it does, we want to do this:
    if (type == kCGEventTapDisabledByTimeout) {
        CGEventTapEnable(eventTapMachPortRef, true);
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
    NSString *path = [[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier:@"com.apple.exposelauncher"];
    NSBundle *bundle = [NSBundle bundleWithPath:path];
    NSString *executablePath = [bundle executablePath];
    [NSTask launchedTaskWithLaunchPath:executablePath arguments:@[]];
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
    CFMachPortRef eventTapMachPortRef = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionListenOnly,
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

void destroyEventTap()
{
    if (eventTapRunLoopSourceRef) {
        CFRelease(eventTapRunLoopSourceRef);
    }
    
    if (eventTapMachPortRef) {
        CFRelease(eventTapMachPortRef);
    }
}

void ensureAppQuitsAfterDuration(double durationMS)
{
    [NSTimer scheduledTimerWithTimeInterval:(durationMS / 1000.0)
                                     target:[NSBlockOperation blockOperationWithBlock:^{ CFRunLoopStop(CFRunLoopGetCurrent()); }]
                                   selector:@selector(main)
                                   userInfo:nil
                                    repeats:NO];
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        if (!accessibilityAvailable()) {
            NSLog(@"Cannot run without Accessibility");
            return 1;
        }
        
        bool alreadyInMissionControl = false;
        
        if (!determineIfInMissionControl(&alreadyInMissionControl)) {
            return 1;
        }
        
        invokeMissionControl();
        
        if (appIsAlreadyRunning()) {
            // Don't want to interfere with an already running instance of this
            // app, so we just invoke Mission Control and quit
            NSLog(@"Already running");
            return 0;
        }
        
        if (alreadyInMissionControl) {
            // No need to do any cursor wiggling if we're already in Mission
            // Control, so in that case we can just quit here.
            NSLog(@"Already in Mission Control");
            return 0;
        }
        
        NSLog(@"\n\nBeginning initial wait period");
        usleep(kWiggleInitialWaitMS * NSEC_PER_USEC);
        
        cursorStart = currentMouseLocation();
        NSLog(@"Original position: %f %f", cursorStart.x, cursorStart.y);
        
        if (!createEventTap()) {
            return 1;
        }
        
        ensureAppQuitsAfterDuration(kMaxRunningTimeMS);
        wiggleCursor();
        
        CFRunLoopRun();
        
        destroyEventTap();
    }
    return 0;
}
