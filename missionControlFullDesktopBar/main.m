#import <Cocoa/Cocoa.h>

CGPoint currentMouseLocation()
{
    CGEventRef event = CGEventCreate(NULL);
    CGPoint loc = CGEventGetLocation(event);
    CFRelease(event);
    return loc;
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        CGPoint cursorStart = currentMouseLocation();
        
        NSString *path = [[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier:@"com.apple.exposelauncher"];
        NSBundle *bundle = [NSBundle bundleWithPath:path];
        NSString *executablePath = [bundle executablePath];
        [NSTask launchedTaskWithLaunchPath:executablePath arguments:@[]];
        
        for(int i = 0; i < 10; ++i) {
            CGEventRef event = CGEventCreateMouseEvent(NULL, kCGEventMouseMoved, CGPointMake(i%2, 1), 0);
            CGEventPost(kCGSessionEventTap, event);
            CFRelease(event);
            
            usleep(USEC_PER_SEC * (1.0 / 30.0));
            printf("%d\n", i);
        }
        
        CGWarpMouseCursorPosition(cursorStart);
        
        NSLog(@"Done!");
    }
    return 0;
}
