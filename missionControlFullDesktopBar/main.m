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

int main(int argc, const char *argv[])
{
    @autoreleasepool {
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
        
        return NSApplicationMain(argc, argv);;
    }
}
