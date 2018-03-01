#import <Cocoa/Cocoa.h>
#import "events.h"

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

void postLeftMouseButtonEvent(UInt32 eventType, short x, short y)
{
    postLeftMouseButtonEventWithUserData(eventType, x, y, 0);
}

void postLeftMouseButtonEventWithUserData(UInt32 eventType, short x, short y, int64_t userData)
{
    CGEventRef event = CGEventCreateMouseEvent(NULL, (CGEventType)eventType, CGPointMake(x,y), kCGMouseButtonLeft);
    
    if (!event) {
        NSLog(@"Failed to create mouse event in postLeftMouseButtonEvent()");
        return;
    }
    
    if (eventType == kCGEventMouseMoved || eventType == kCGEventLeftMouseDragged) {
        CGPoint prevMouseLocation = currentMouseLocation();
        // Mouse location can be a decimal value, so for this calculation to work correctly we have to round to the nearest integer:
        CGEventSetIntegerValueField(event, kCGMouseEventDeltaX, x-round(prevMouseLocation.x));
        CGEventSetIntegerValueField(event, kCGMouseEventDeltaY, y-round(prevMouseLocation.y));
    }
    
    if (userData != 0) {
        CGEventSetIntegerValueField(event, kCGEventSourceUserData, userData);
    }
    
    CGEventPost(kCGSessionEventTap, event);
    CFRelease(event);
}

void postInternalMouseEvent(NSEventType type, NSWindow *window)
{
    NSEvent *nsevent = [NSEvent mouseEventWithType:type
                                          location:NSMakePoint(window.frame.size.width/2, window.frame.size.height/2)
                                     modifierFlags:0
                                         timestamp:CACurrentMediaTime()
                                      windowNumber:[window windowNumber]
                                           context:[window graphicsContext]
                                       eventNumber:0
                                        clickCount:1
                                          pressure:1.0];
    
    [[NSApplication sharedApplication] postEvent:nsevent atStart:YES];
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

CGPoint currentUnflippedMouseLocation()
{
    CGEventRef event = CGEventCreate(NULL);
    
    if (!event) {
        NSLog(@"Error: could not create event");
        return CGPointMake(0,0);
    }
    
    CGPoint loc = CGEventGetUnflippedLocation(event);
    CFRelease(event);
    return loc;
}

