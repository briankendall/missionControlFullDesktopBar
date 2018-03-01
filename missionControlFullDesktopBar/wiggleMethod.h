#ifndef wiggleMethod_h
#define wiggleMethod_h

#define kWiggleInitialWaitMS 60
#define kWiggleDefaultDurationMS 120
#define kTimeBetweenWiggleEventsMS 5
#define kMaxRunningTimeBufferMS 500
#define kWiggleMinCount 5

#import <ApplicationServices/ApplicationServices.h>

bool isWiggleEvent(CGEventRef event);
void processWiggleEventAndPostNext(CGEventRef event);
void showMissionControlWithFullDesktopBarUsingWiggleMethod(int inWiggleDuration);
void wiggleMethodCleanUp();

#endif /* wiggleMethod_h */
