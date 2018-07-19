#import <Cocoa/Cocoa.h>
#import "app.h"
#import "wiggleMethod.h"
#import "dragMethod.h"
#import "cursorPositionMethod.h"
#import "eventTap.h"

static bool daemonized = false;
static CFMessagePortRef localPort = nil;
static CFRunLoopSourceRef localPortRunLoopSource = nil;
static NSDate *lastMissionControlInvocationTime = nil;
static NSTimer *appStopTimer = nil;

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

void invokeMissionControl()
{
    // Using some undocumented API's here!
    extern int CoreDockSendNotification(CFStringRef);
    CoreDockSendNotification(CFSTR("com.apple.expose.awake"));
    lastMissionControlInvocationTime = [NSDate date];
}

void releaseMissionControl()
{
    double timeSince = lastMissionControlInvocationTime ? -[lastMissionControlInvocationTime timeIntervalSinceNow] : 0;
    bool alreadyInMissionControl = false;
    determineIfInMissionControl(&alreadyInMissionControl);
    
    if (timeSince > 0.5 && alreadyInMissionControl) {
        printf("Released mission control trigger when in mission control after adequate time!\n");
        invokeMissionControl();
        cleanUpAndFinish();
    } else {
        printf("Release: not in Mission Control or too soon after initial trigger, so not doing anything");
    }
}

void showMissionControlWithFullDesktopBar(CommandLineArgs *args)
{
    if (args->release) {
        releaseMissionControl();
    } else if (args->method == kMethodWiggle) {
        showMissionControlWithFullDesktopBarUsingWiggleMethod(args->wiggleDuration);
    } else if (args->method == kMethodDrag) {
        showMissionControlWithFullDesktopBarUsingDragMethod(args->internalMouseDown);
    } else if (args->method == kMethodCursorPosition) {
        showMissionControlWithFullDesktopBarUsingCursorPositionMethod();
    } else {
        cleanUpAndFinish();
    }
}

void cleanUpAndFinish()
{
    printf("Cleaning up\n");
    stopEventTap();
    wiggleMethodCleanUp();
    dragMethodCleanUp();
    cursorPositionMethodCleanUp();
    
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

bool signalDaemon(CommandLineArgs *args)
{
    CFMessagePortRef remotePort = CFMessagePortCreateRemote(nil,
                                                            CFSTR("net.briankendall.missionControlFullDesktopBar"));
    
    if (!remotePort) {
        printf("Could not create remote port for signalling daemon, probably because it doesn't exist\n");
        return false;
    }
    
    CFTimeInterval timeout = 3.0;
    CFDataRef data = CFDataCreate(NULL, (UInt8 *)args, sizeof(*args));
    SInt32 status = CFMessagePortSendRequest(remotePort, 0, data, timeout, timeout, nil, nil);
    
    if (status != kCFMessagePortSuccess) {
        NSLog(@"Failed to signal daemon");
    }
    
    CFRelease(data);
    CFRelease(remotePort);
    return true;
}

static CFDataRef receivedMessageAsDaemon(CFMessagePortRef port, SInt32 messageID, CFDataRef data, void *info)
{
    CommandLineArgs args;
    CFDataGetBytes(data, CFRangeMake(0, sizeof(args)), (UInt8 *)&args);
    printf("Daemon: received signal. Args: %d %d %d %d %d %d", args.daemon, args.daemonized, args.release, args.method,
           args.wiggleDuration, args.internalMouseDown);
    showMissionControlWithFullDesktopBar(&args);
    return NULL;
}

void quitDaemon()
{
    daemonized = false;
    cleanUpAndFinish();
}

void setupDaemon()
{
    daemonized = true;
    localPort = CFMessagePortCreateLocal(nil, CFSTR("net.briankendall.missionControlFullDesktopBar"),
                                         receivedMessageAsDaemon, nil, nil);
    CFRunLoopSourceRef localPortRunLoopSource = CFMessagePortCreateRunLoopSource(nil, localPort, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), localPortRunLoopSource, kCFRunLoopCommonModes);
    
    // Work around for issue where various notifications and event taps stop working after the current user switches
    // or the computer goes to sleep.
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserverForName:NSWorkspaceSessionDidResignActiveNotification
                                                                    object:nil
                                                                     queue:nil
                                                                usingBlock:^(NSNotification *notification) { quitDaemon(); }];
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserverForName:NSWorkspaceScreensDidSleepNotification
                                                                    object:nil
                                                                     queue:nil
                                                                usingBlock:^(NSNotification *notification) { quitDaemon(); }];
}

void becomeDaemon(int argc, const char *argv[])
{
    if (fork() == 0) {
        printf("Running as daemon\n");
        const char *newArgs[argc+2];
        
        for(int i = 0; i < argc; ++i) {
            newArgs[i] = argv[i];
        }
        
        newArgs[argc] = "--daemonized";
        newArgs[argc+1] = NULL;
        execve(newArgs[0], (char * const *)newArgs, NULL);
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
        NSLog(@"Error: emergency stop timer has fired");
        cleanUpAndFinish();
    }]
                                                  selector:@selector(main)
                                                  userInfo:nil
                                                   repeats:NO];
}
