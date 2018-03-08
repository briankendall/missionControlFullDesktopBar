#ifndef cursorPostionMethod_h
#define cursorPostionMethod_h

#import <ApplicationServices/ApplicationServices.h>

void showMissionControlWithFullDesktopBarUsingCursorPositionMethod();
void cursorPositionMethodCleanUp();
bool isCursorPositionEvent(CGEventRef event);
bool isCursorPositionResetEvent(CGEventRef event);
void handleCursorPositionEventAndPostNext();
void handleNonCursorPositionEvent();
void handleCursorPositionResetEvent(CGEventRef event);

#endif

