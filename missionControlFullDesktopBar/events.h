//
//  events.h
//  missionControlFullDesktopBar
//
//  Created by moof on 3/14/17.
//  Copyright © 2017 Brian Kendall. All rights reserved.
//

#ifndef events_h
#define events_h

#import <Cocoa/Cocoa.h>

void moveCursor(short x, short y);
void postLeftMouseButtonEvent(UInt32 eventType, short x, short y);
void postInternalMouseEvent(NSEventType type, NSWindow *window);
CGPoint currentMouseLocation();
CGPoint currentUnflippedMouseLocation();

#endif /* events_h */
