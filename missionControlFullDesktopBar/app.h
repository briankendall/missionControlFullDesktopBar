#ifndef app_h
#define app_h

#define kMessageMissionControlTriggerPressed 1
#define kMessageMissionControlTriggerReleased 2

bool determineIfInMissionControl(bool *result);
void invokeMissionControl();
void releaseMissionControl();
void cleanUpAndFinish();
void setupDaemon();

#endif /* app_h */
