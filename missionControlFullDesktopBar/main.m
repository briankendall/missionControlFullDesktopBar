#import <Cocoa/Cocoa.h>
#include <IOKit/hidsystem/IOHIDShared.h>
#include <ApplicationServices/ApplicationServices.h>

/*
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

void postMouseMovedUsingIOHIDInterface(short x, short y)
{
    NXEventData event;
    IOGPoint pos = {x, y};
    kern_return_t err;
    
    bzero(&event, sizeof(NXEventData));

    //prevMouseLocation = currentMouseLocation();
    // For some reason it's necessary to round the prevMouseLocation values to the nearest integer
    //event.mouseMove.dx = pos.x-round(prevMouseLocation.x);
    //event.mouseMove.dy = pos.y-round(prevMouseLocation.y);
    
    IOOptionBits options = 0;//kIOHIDSetCursorPosition;
    err = IOHIDPostEvent(getIOKitEventDriver(), NX_MOUSEMOVED, pos, &event, kNXEventDataVersion, 0, options);
    
    if (err != KERN_SUCCESS) {
        NSLog(@"Warning: Failed to post mouse event. Error: %d", err);
    }
}
 */

// The following is a definition for an undocumented Apple API that allows background applications to hide the cursor
// While this technique has worked for several years, it should be noted that it is liable to stop working at
// any point.
typedef int CGSConnection;
void CGSSetConnectionProperty(int, int, const void *, const void *);
int	_CGSDefaultConnection();

// Enables the application to hide the cursor, in spite of being a background application.  Must be called at least once for each application process.
void enableBackgroundCursor()
{
    // Hack to make background cursor setting work
    CGSSetConnectionProperty(_CGSDefaultConnection(), _CGSDefaultConnection(), CFSTR("SetsCursorInBackground"), kCFBooleanTrue);
}

void setCursorVisibility(bool visible)
{
    const int maxDisplays = 20; // Seems like a reasonable upper bound
    CGDirectDisplayID displayList[maxDisplays];
    CGDisplayCount displayCount;
    CGDisplayErr err;
    
    // CGDisplayHideCursor or CGDisplayShowCursor must be called on all active displays, so we get them all here:
    err = CGGetOnlineDisplayList(maxDisplays, displayList, &displayCount);
    
    if (err != noErr || displayCount == 0) {
        // Just a little defensive coding, in case the above fails for some weird reason:
        displayList[0] = CGMainDisplayID();
        displayCount = 1;
    }
    
    if (visible) {
        for(unsigned int i = 0; i < displayCount; ++i) {
            CGDisplayShowCursor(displayList[i]);
        }
    } else {
        for(unsigned int i = 0; i < displayCount; ++i) {
            CGDisplayHideCursor(displayList[i]);
        }
    }
}

CGPoint currentMouseLocation()
{
    CGEventRef event = CGEventCreate(NULL);
    CGPoint loc = CGEventGetLocation(event);
    CFRelease(event);
    return loc;
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        /*
        NSArray *apps = [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.dock"];
        
        if (apps.count == 0) {
            NSLog(@"Dock is not running... cannot proceed");
            return 1;
        }
        
        NSRunningApplication *dock = apps[0];
        ProcessSerialNumber dockPSN;
        
        // Sadly Apple has provided no alternative to GetProcessForPID for functions that
        // absolutely requires a ProcessSerialNumber.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        GetProcessForPID(dock.processIdentifier, &dockPSN);
#pragma clang diagnostic pop
        */
        
        enableBackgroundCursor();
        
        //setCursorVisibility(false);
        
        /*float duration = 0.25;
        
        CFPropertyListRef animationDurationRef = CFPreferencesCopyAppValue(CFSTR("expose-animation-duration"), CFSTR("com.apple.dock"));
        
        if (animationDurationRef) {
            CFNumberGetValue(animationDurationRef, kCFNumberFloatType, &duration);
            CFRelease(animationDurationRef);
        } else {
            NSLog(@"null");
        }
        */
        
        CGPoint cursorStart = currentMouseLocation();
        
        NSString *path = [[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier:@"com.apple.exposelauncher"];
        NSBundle *bundle = [NSBundle bundleWithPath:path];
        NSString *executablePath = [bundle executablePath];
        [NSTask launchedTaskWithLaunchPath:executablePath arguments:@[]];
        setCursorVisibility(false);
        
        for(int i = 0; i < 10; ++i) {
            CGEventRef event = CGEventCreateMouseEvent(NULL, kCGEventMouseMoved, CGPointMake(i%2, 1), 0);
            CGEventPost(kCGSessionEventTap, event);
            CFRelease(event);
            
            usleep(USEC_PER_SEC * (1.0 / 30.0));
            setCursorVisibility(false);
            printf("%d\n", i);
        }
        
        CGWarpMouseCursorPosition(cursorStart);
        setCursorVisibility(true);
        
        NSLog(@"Done!");
    }
    return 0;
}
