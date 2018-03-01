#import <Cocoa/Cocoa.h>
#import "app.h"
#import "processes.h"
#import "commandLineArguments.h"
#import "wiggleMethod.h"

bool accessibilityAvailable()
{
    return AXIsProcessTrustedWithOptions((CFDictionaryRef)@{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @true});
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

#include "events.h"

static CFMachPortRef eventTapMachPortRef = NULL;
static CGPoint mouseStart;

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


int main(int argc, const char *argv[])
{
    @autoreleasepool {
        /*
        printf("Whee! %lf\n", CACurrentMediaTime());
        fflush(stdout);
        
        mouseStart = currentMouseLocation();
        
        printf("%f %f\n", mouseStart.x, mouseStart.y);
        fflush(stdout);
        
        eventTapMachPortRef = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionListenOnly,
                                               CGEventMaskBit(kCGEventMouseMoved), (CGEventTapCallBack)mouseMovementEventTapFunction, NULL);
        
        if (!eventTapMachPortRef) {
            NSLog(@"Error: could not create event tap");
            return 1;
        }
        
        CFRunLoopSourceRef eventTapRunLoopSourceRef = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTapMachPortRef, 0);
        
        if (!eventTapRunLoopSourceRef) {
            NSLog(@"Error: could not create event tap run loop source");
            return 1;
        }
        
        CFRunLoopAddSource(CFRunLoopGetCurrent(), eventTapRunLoopSourceRef, kCFRunLoopDefaultMode);
        
        // For whatever reason, our event tap may not catch this mouse event unless we post it using the Quartz event services API
        CGEventRef event = CGEventCreateMouseEvent(NULL, kCGEventMouseMoved, CGPointMake(100, 0), kCGMouseButtonLeft);
        CGEventPost(kCGHIDEventTap, event);
        CFRelease(event);
        
        //moveCursor(100, 0);
        
        //extern int CoreDockSendNotification(CFStringRef);
        //CoreDockSendNotification(CFSTR("com.apple.expose.awake"));
        
        //usleep(0.002 * USEC_PER_SEC);
        
        //event = CGEventCreateMouseEvent(NULL, kCGEventMouseMoved, p, kCGMouseButtonLeft);
        //CGEventPost(kCGHIDEventTap, event);
        //CFRelease(event);
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^ () {
            printf("Failed!\n");
            CFRunLoopStop(CFRunLoopGetCurrent());
        });
        
        CFRunLoopRun();
        
        printf("Done! %lf\n", CACurrentMediaTime());
        fflush(stdout);
        
        return 0;
        */
        
        CommandLineArgs args;
        
        if (!parseCommandLineArgs(&args, argc, argv)) {
            return 1;
        }
        
        if (signalDaemon(&args)) {
            return 0;
        }
        
        if (!accessibilityAvailable()) {
            NSLog(@"Cannot run without Accessibility");
            return 1;
        }
        
        if (args.daemon && !args.daemonized) {
            becomeDaemon(argc, argv);
            return 0;
        }
        
        NSApplicationLoad();
        
        if (args.daemonized) {
            setupDaemon();
            
        } else if (appIsAlreadyRunning()) {
            // Don't want to interfere with an already running instance of this
            // app, so we just invoke Mission Control and quit
            NSLog(@"Already running");
            invokeMissionControl();
            return 0;
        }
        
        showMissionControlWithFullDesktopBar(&args);
        
        return NSApplicationMain(argc, argv);
    }
}
