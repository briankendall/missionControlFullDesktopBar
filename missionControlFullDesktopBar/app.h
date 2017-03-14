#ifndef app_h
#define app_h

#import "commandLineArguments.h"

#define kMessageMissionControlTriggerPressed 1
#define kMessageMissionControlTriggerReleased 2

bool determineIfInMissionControl(bool *result);
void invokeMissionControl();
void releaseMissionControl();
void showMissionControlWithFullDesktopBar(CommandLineArgs *args);
void cleanUpAndFinish();
bool signalDaemon(CommandLineArgs *args);
void setupDaemon();

#endif /* app_h */
