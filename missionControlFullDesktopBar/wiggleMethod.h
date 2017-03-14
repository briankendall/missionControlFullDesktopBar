#ifndef wiggleMethod_h
#define wiggleMethod_h

#define kWiggleInitialWaitMS 60
#define kWiggleDefaultDurationMS 120
#define kTimeBetweenWiggleEventsMS 5
#define kMaxRunningTimeBufferMS 500
#define kWiggleMinCount 5

void showMissionControlWithFullDesktopBarUsingWiggleMethod(int inWiggleDuration);
void wiggleMethodCleanUp();
void wiggleMethodShutDown();

#endif /* wiggleMethod_h */
