#import <Cocoa/Cocoa.h>
#import "invisibleWindow.h"
#import "app.h"

static NSWindow *_invisibleWindow = nil;
static InvisibleView *_invisibleView = nil;

@interface NSWindow (Private)
- (void )_setPreventsActivation:(bool)preventsActivation;
@end

static void createSharedInvisibleWindowAndView()
{
    // The idea behind this window is that it's invisible and it cannot activate, but it
    // receives mouse clicks and clicking anywhere on it will trigger the start of a drag
    // operation. So all we need to do to make Mission Control use the full desktop bar is
    // have the window be in the process of dragging while Mission Control is invoked
    _invisibleWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0,
                                                                        kInvisibleWindowSize,
                                                                        kInvisibleWindowSize)
                                                   styleMask:NSWindowStyleMaskBorderless
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    _invisibleWindow.collectionBehavior = NSWindowCollectionBehaviorIgnoresCycle | NSWindowCollectionBehaviorTransient;
    [_invisibleWindow _setPreventsActivation:true];
    _invisibleWindow.ignoresMouseEvents = NO;
    [_invisibleWindow setBackgroundColor:[NSColor clearColor]];
    _invisibleWindow.opaque = NO;
    
    // In case we need to debug, uncomment this line to make the invisible window not invisible:
    //[_invisibleWindow setBackgroundColor:[NSColor colorWithRed:0.0 green:1.0 blue:1.0 alpha:0.5]];
    
    _invisibleView = [[InvisibleView alloc] initWithFrame:NSMakeRect(0, 0,
                                                                     _invisibleWindow.frame.size.width,
                                                                     _invisibleWindow.frame.size.height)];
    [_invisibleWindow setContentView:_invisibleView];
    [_invisibleView registerForDraggedTypes:@[NSStringPboardType]];
}

NSWindow * sharedInvisibleWindow()
{
    if (!_invisibleWindow) {
        createSharedInvisibleWindowAndView();
    }
    
    return _invisibleWindow;
}

InvisibleView * sharedInvisibleView()
{
    if (!_invisibleView) {
        createSharedInvisibleWindowAndView();
    }
    
    return _invisibleView;
}

@implementation InvisibleView {
    bool startedDrag;
    bool receivedMouseDown;
    NSTimer *abortTimer;
    CFTimeInterval startTime;
}

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    
    if (self) {
        abortTimer = nil;
        receivedMouseDown = false;
        [self resetTracking];
    }
    
    return self;
}

- (void)mouseDown:(NSEvent *)event
{
    if (startedDrag) {
        return;
    }
    
    printf("Received mouse down in invisible view\n");
    
    // Having received a mouse down event, we initiate a drag, as when a drag is in
    // progress, Mission Control always shows the full desktop bar. In this case we
    // are dragging an empty string of text, which should hopefully have no effect
    // on any other open apps.
    
    receivedMouseDown = true;
    startedDrag = true;
    NSString *stringData = @"";
    NSDraggingItem *dragItem = [[NSDraggingItem alloc] initWithPasteboardWriter:stringData];
    NSDraggingSession *draggingSession = [self beginDraggingSessionWithItems:[NSArray arrayWithObject:dragItem]
                                                                       event:event source:self];
    
    if (!draggingSession) {
        NSLog(@"Failed to create dragging session");
        cleanUpAndFinish();
        return;
    }
    
    draggingSession.animatesToStartingPositionsOnCancelOrFail = NO;
    draggingSession.draggingFormation = NSDraggingFormationNone;
    
    [self createAbortTimer];
}

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
    printf("Received drag event, invoking Mission Control...\n");
    // At this point we know the drag is successfully in progress, so we can invoke
    // Mission Control and immediately post an event to release the mouse button and
    // thus end the drag. With any luck, both the user and macOS should be none
    // the wiser.
    [self removeAbortTimer];
    invokeMissionControl();
    cleanUpAndFinish();
    
    return NSDragOperationNone;
}

- (void)resetTracking
{
    startedDrag = false;
    [self removeAbortTimer];
}

- (void)createAbortTimer
{
    [self removeAbortTimer];
    
    // We're giving ourselves half a second for the drag to occur, otherwise we abort.
    abortTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:NO block:^(NSTimer *timer) {
        printf("Drag never occurred -- ending\n");
        cleanUpAndFinish();
    }];
}

- (void)removeAbortTimer
{
    if (abortTimer) {
        if (abortTimer.isValid) {
            [abortTimer invalidate];
        }
        
        abortTimer = nil;
    }
}

- (bool)hasReceivedAnyMouseDowns
{
    return receivedMouseDown;
}

- (NSDragOperation)draggingSession:(NSDraggingSession *)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context
{
    return NSDragOperationNone;
}

@end
