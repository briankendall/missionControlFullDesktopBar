#ifndef eventTap_h
#define eventTap_h

bool startEventTap();
bool startEventTapAndResetCursorDelta();
void stopEventTap();
void destroyEventTap();
CGPoint accumulatedCursorMovementFromEventTap();

#endif
