#ifndef cursorPostionMethod_h
#define cursorPostionMethod_h

#import <ApplicationServices/ApplicationServices.h>

void showMissionControlWithFullDesktopBarUsingCursorPositionMethod();
void cursorPositionMethodCleanUp();
bool isCursorPositionEvent(CGEventRef event, CGEventTapProxy proxy);
void handleCursorPositionEventAndPostNext();
void handleNonCursorPositionEvent();

#endif

