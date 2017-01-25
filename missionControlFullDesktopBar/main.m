#import <Cocoa/Cocoa.h>

#define kWiggleInitialWaitMS 60
#define kWiggleDurationMS 100
#define kWiggleRate 90
#define kWiggleMinCount 5
#define kMaxRunningTimeMS 400

CFMachPortRef eventTapMachPortRef;
CGPoint cursorStart;
CGPoint cursorDelta = {0, 0};
NSDate *wiggleStartTime = nil;
NSDate *overallStartTime = nil;
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
        fprintf(stderr, "Error: could not create event\n");
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

CGEventRef eventTapFunction(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *data)
{
    // Event taps can occasionally be disabled if they block for too long.  This will probably never happen, but
    // just in case it does, we want to do this:
    if (type == kCGEventTapDisabledByTimeout) {
        CGEventTapEnable(eventTapMachPortRef, true);
        return event;
    }
    
    CGPoint location = CGEventGetLocation(event);
    int64_t edx = CGEventGetIntegerValueField(event, kCGMouseEventDeltaX);
    int64_t edy = CGEventGetIntegerValueField(event, kCGMouseEventDeltaY);
    
    if (wiggleStartTime == nil) {
        wiggleStartTime = [NSDate date];
    }
    
    double duration = -[wiggleStartTime timeIntervalSinceNow] * 1000.0;
    
    // Artificial movement will always have no decimal component
    if ((location.x == 1.0 && location.y == 1.0) || (location.x == 2.0 && location.y == 1.0)) {
        NSLog(@"Received WIGGLE movement to: (%f , %f),   wiggleCount: %d     duration: %f", location.x, location.y, wiggleCount, duration);
        ++wiggleCount;
        
        if (wiggleCount < kWiggleMinCount || duration < kWiggleDurationMS) {
            dispatch_time_t time = dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_MSEC);//(1.0 / kWiggleRate) * NSEC_PER_SEC);
            dispatch_after(time, dispatch_get_main_queue(), ^(void){
            //dispatch_async(dispatch_get_main_queue(), ^(void){
                wiggleCursor();
            });
            
        } else {
            NSLog(@"sending final movement...");
            dispatch_async(dispatch_get_main_queue(), ^(void){
                moveCursor(cursorStart.x + cursorDelta.x, cursorStart.y + cursorDelta.y);
                CFRunLoopStop(CFRunLoopGetCurrent());
            });
            
        }
        
    } else {
        NSLog(@"Received regular movement to: (%f , %f),   reported delta: (%lld,%lld)", location.x, location.y, edx, edy);
        CGPoint *cursorDelta = (CGPoint *)data;
        cursorDelta->x += edx;
        cursorDelta->y += edy;
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
        
        if (alreadyInMissionControl) {
            NSLog(@"Already in Mission Control");
            return 0;
        }
        
        NSLog(@"\n\nBeginning initial wait period");
        usleep(kWiggleInitialWaitMS * NSEC_PER_USEC);
        
        overallStartTime = [NSDate date];
        cursorStart = currentMouseLocation();
        NSLog(@"Original position: %f %f", cursorStart.x, cursorStart.y);
        
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
        
        // Ensures app terminates after a specified length of time
        [NSTimer scheduledTimerWithTimeInterval:(kMaxRunningTimeMS / 1000.0)
                                         target:[NSBlockOperation blockOperationWithBlock:^{ CFRunLoopStop(CFRunLoopGetCurrent()); }]
                                       selector:@selector(main)
                                       userInfo:nil
                                        repeats:NO];
        
        wiggleCursor();
        
        CFRunLoopRun();
        
        CFRelease(eventTapRunLoopSourceRef);
        CFRelease(eventTapMachPortRef);
    }
    return 0;
}
