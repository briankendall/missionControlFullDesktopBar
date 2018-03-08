#import <Cocoa/Cocoa.h>
#import "wiggleMethod.h"
#import "app.h"
#import "events.h"
#import "eventTap.h"

static bool wigglingInProgress = false;
static CGPoint cursorStart;
static NSDate *wiggleStartTime = nil;
static int wiggleDuration = kWiggleDefaultDurationMS;
static int wiggleCount = 0;
static NSTimer *wiggleStepTimer = nil;

void performNextWiggleStep(int delayMS, void (^nextStep)(void))
{
    wiggleStepTimer = [NSTimer scheduledTimerWithTimeInterval:(delayMS / 1000.0)
                                                       target:[NSBlockOperation blockOperationWithBlock:nextStep]
                                                     selector:@selector(main)
                                                     userInfo:nil
                                                      repeats:NO];
}

void removeWiggleStepTimer()
{
    if (wiggleStepTimer && [wiggleStepTimer isValid]) {
        [wiggleStepTimer invalidate];
        wiggleStepTimer = nil;
    }
}

void wiggleCursor()
{
    moveCursor(wiggleCount%2+1, 1);
}

bool isWiggleEvent(CGEventRef event)
{
    return CGEventGetIntegerValueField(event, kCGEventSourceUnixProcessID) == getpid() && CGEventGetLocation(event).x < 80;
}

void processWiggleEventAndPostNext(CGEventRef event)
{
    if (wiggleStartTime == nil) {
        wiggleStartTime = [NSDate date];
    }
    
    double durationMS = -[wiggleStartTime timeIntervalSinceNow] * 1000.0;
    ++wiggleCount;
    
    CGPoint location = CGEventGetLocation(event);
    printf("Received WIGGLE movement to: (%f , %f),   wiggleCount: %d     duration: %f\n",
           location.x, location.y, wiggleCount, durationMS);
    
    if (wiggleCount < kWiggleMinCount || durationMS < wiggleDuration) {
        // Keep on wiggling...
        // Waiting a little bit of time between receiving an event and posting it just so that
        // we don't flood the system with artificial mouse events
        performNextWiggleStep(kTimeBetweenWiggleEventsMS, ^ (void) {
            wiggleCursor();
        });
        
    } else {
        // We now move the cursor to its original position plus the accumulated deltas
        // of all of the naturally occurring mouse events that we've observed, so that
        // the cursor ends up where the user expects it to be:
        performNextWiggleStep(0, ^ (void) {
            cleanUpAndFinish();
        });
    }
}

void showMissionControlWithFullDesktopBarUsingWiggleMethod(int inWiggleDuration)
{
    bool alreadyInMissionControl = false;
    
    if (!determineIfInMissionControl(&alreadyInMissionControl)) {
        return;
    }
    
    invokeMissionControl();
    
    if (alreadyInMissionControl) {
        // No need to do any cursor wiggling if we're already in Mission
        // Control, so in that case we can just quit here.
        printf("Already in Mission Control\n");
        cleanUpAndFinish();
        return;
    }
    
    if (wigglingInProgress) {
        printf("Already wiggling\n");
        cleanUpAndFinish();
        return;
    }
    
    wigglingInProgress = false;
    wiggleDuration = inWiggleDuration;
    wiggleStartTime = nil;
    wiggleCount = 0;
    
    printf("\nBeginning initial wait period for wiggle method\n");
    
    wiggleStepTimer = [NSTimer scheduledTimerWithTimeInterval:(kWiggleInitialWaitMS / 1000.0)
                                                       target:[NSBlockOperation blockOperationWithBlock:^{
        
        wigglingInProgress = true;
        cursorStart = currentMouseLocation();
        printf("Original position: %f %f\n", cursorStart.x, cursorStart.y);
        
        if (!startEventTapAndResetCursorDelta()) {
            return;
        }
        
        ensureAppStopsAfterDuration(kMaxRunningTimeBufferMS + wiggleDuration);
        wiggleCursor();
    }]
                                                     selector:@selector(main)
                                                     userInfo:nil
                                                      repeats:NO];
}

void wiggleMethodCleanUp()
{
    if (wigglingInProgress) {
        // Need to call this after stopEventTap() so that this event doesn't get snagged by the
        // event tap
        printf("Sending final cursor movement\n");
        CGPoint cursorDelta = accumulatedCursorMovementFromEventTap();
        moveCursor(cursorStart.x + cursorDelta.x, cursorStart.y + cursorDelta.y);
    }
    
    removeAppStopTimer();
    removeWiggleStepTimer();
    wigglingInProgress = false;
}

