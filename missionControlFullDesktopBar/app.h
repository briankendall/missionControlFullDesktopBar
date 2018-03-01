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
void becomeDaemon(int argc, const char *argv[]);
void ensureAppStopsAfterDuration(double durationMS);
void removeAppStopTimer();

#endif /* app_h */
