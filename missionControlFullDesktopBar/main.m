#import <Cocoa/Cocoa.h>
#import "app.h"
#import "processes.h"

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

bool hasArg(int argc, const char * argv[], const char *arg)
{
    for(int i = 0; i < argc; ++i) {
        if (strcmp(argv[i], arg) == 0) {
            return true;
        }
    }
    
    return false;
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
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
        
        if (!accessibilityAvailable()) {
            NSLog(@"Cannot run without Accessibility");
            return 1;
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
            setupDaemon();
            
        } else if (appIsAlreadyRunning()) {
            // Don't want to interfere with an already running instance of this
            // app, so we just invoke Mission Control and quit
            NSLog(@"Already running");
            return 0;
        }
        
        showMissionControlWithFullDesktopBarUsingWiggleMethod();
        
        return NSApplicationMain(argc, argv);;
    }
}
