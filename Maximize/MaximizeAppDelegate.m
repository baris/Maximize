//
//  MaximizeAppDelegate.m
//  Maximize
//
//  Created by Baris Metin on 2/29/12.
//  Copyright (c) 2012 Baris Metin.
//

#import "MaximizeAppDelegate.h"


@interface MaximizeAppDelegate()
typedef enum {
    STATE_UNKNOWN,
    STATE_RESIZE,
    STATE_MOVE,
    
    STATE_MAXIMIZE,
    STATE_LEFT,
    STATE_RIGHT,
    
    STATE_OTHER
} EventState;

@property (nonatomic) NSWindow *activeWindow;
@property (nonatomic) NSString *activeWindowTitle;
@property (nonatomic) NSString *activeApplication;
@property (nonatomic) id eventMonitor;
@property (nonatomic) EventState currentEventState;
@property (nonatomic) NSPoint mouseLocation;
@property (nonatomic) NSStatusItem *statusBarItem;
@end


@implementation MaximizeAppDelegate
@synthesize window = _window;
@synthesize activeWindowTitle = _activeWindowTitle;
@synthesize activeWindow = _activeWindow;
@synthesize activeApplication = _activeApplication;
@synthesize eventMonitor = _eventMonitor;
@synthesize currentEventState = _currentEventState;
@synthesize mouseLocation = _mouseLocation;
@synthesize statusBarItem = _statusBarItem;


void windowListApplierFunction(const void *inputDictionary, void *context)
{
    NSDictionary *entry = (__bridge NSDictionary*)inputDictionary;
    NSMutableDictionary *activeWindowData = (__bridge NSMutableDictionary*)context;
    
    if ([activeWindowData valueForKey:@"title"]) return;
    if ([[entry objectForKey:(id)kCGWindowLayer] integerValue] == 0) {
        [activeWindowData setValue:[entry objectForKey:(id)kCGWindowName] forKey:@"title"];
        [activeWindowData setValue:[entry objectForKey:(id)kCGWindowNumber] forKey:@"ID"];
        [activeWindowData setValue:[entry objectForKey:(id)kCGWindowOwnerName] forKey:@"application"];
//        NSLog(@"%@", activeWindowData);
    }
}


- (void)findFrontMostWindow
{
    NSMutableDictionary* activeWindowData = [[NSMutableDictionary alloc] init];
    CFArrayRef windowList = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements, kCGNullWindowID);
    CFArrayApplyFunction(windowList, CFRangeMake(0, CFArrayGetCount(windowList)), windowListApplierFunction, (__bridge void*)activeWindowData);
    CFRelease(windowList);
    self.activeApplication = [activeWindowData valueForKey:@"application"];
    self.activeWindowTitle = [activeWindowData valueForKey:@"title"];
    self.activeWindow = [[NSApplication sharedApplication] windowWithWindowNumber:[[activeWindowData valueForKey:@"ID"] integerValue]];
}


- (EventState)currentEventState
{
    if (_currentEventState == STATE_UNKNOWN) _currentEventState = STATE_OTHER;
    return _currentEventState;
}


- (NSStatusItem*)statusBarItem
{
    if (!_statusBarItem) _statusBarItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    return _statusBarItem;
}


- (void)handleEventStates
{
    if (self.currentEventState == STATE_OTHER || self.currentEventState == STATE_UNKNOWN) {
        self.mouseLocation = [NSEvent mouseLocation];
        return;
    }
    [self findFrontMostWindow];
    
    int deltaX, deltaY;
    NSPoint currentMouseLocation = [NSEvent mouseLocation];
    deltaX = currentMouseLocation.x - self.mouseLocation.x;
    deltaY = -(currentMouseLocation.y - self.mouseLocation.y);
    self.mouseLocation = currentMouseLocation;

    NSString *script = @"tell application \"Finder\"\n"
    "set screen_resolution to bounds of window of desktop\n"
    "set screen_width to item 3 of screen_resolution\n"
	"set screen_height to item 4 of screen_resolution\n"
    "end tell\n";    
    if (self.currentEventState == STATE_MAXIMIZE) {
        script = [NSString stringWithFormat:@"%@\n"
                  "tell application \"%@\"\n"
                  "set the bounds of the first window to screen_resolution\n"
                  "end tell\n", script, self.activeApplication];
    } else if (self.currentEventState == STATE_LEFT) {
        script = [NSString stringWithFormat:@"%@\n"
                  "tell application \"%@\"\n"
                  "set the bounds of the first window to {0,0,screen_width/2,screen_height}\n"
                  "end tell\n", script, self.activeApplication];
    } else if (self.currentEventState == STATE_RIGHT) {
        script = [NSString stringWithFormat:@"%@\n"
                  "tell application \"%@\"\n"
                  "set the bounds of the first window to {screen_width/2,0,screen_width,screen_height}\n"
                  "end tell\n", script, self.activeApplication];        
    } else if (self.currentEventState == STATE_RESIZE) {
        script = [NSString stringWithFormat:@"%@\n"
                  "tell application \"%@\"\n"
                  "set current_bounds to the bounds of the first window\n"
                  "set x to item 1 of current_bounds\n"
                  "set y to item 2 of current_bounds\n"
                  "set width to item 3 of current_bounds\n"
                  "set height to item 4 of current_bounds\n"
                  "set the bounds of the first window to {x,y,width+%d,height+%d}\n"
                  "end tell\n", script, self.activeApplication, deltaX, deltaY];
    } else if (self.currentEventState == STATE_MOVE) {
        script = [NSString stringWithFormat:@"%@\n"
                  "tell application \"%@\"\n"
                  "set current_bounds to the bounds of the first window\n"
                  "set x to item 1 of current_bounds\n"
                  "set y to item 2 of current_bounds\n"
                  "set width to item 3 of current_bounds\n"
                  "set height to item 4 of current_bounds\n"
                  "set the bounds of the first window to {x+%d,y+%d,width+%d,height+%d}\n"
                  "end tell\n", script, self.activeApplication, deltaX, deltaY, deltaX, deltaY];
    }
//    NSLog(@"%@", script);
    NSAppleScript *eventScript = [[NSAppleScript alloc] initWithSource:script];
    [eventScript executeAndReturnError:nil];

}


- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    [[NSApplication sharedApplication] setActivationPolicy:NSApplicationActivationPolicyProhibited];
    
    [self.statusBarItem setHighlightMode:YES];
    [self.statusBarItem setTitle:@""];
    [self.statusBarItem setEnabled:YES];
    [self.statusBarItem setToolTip: @"Maximize"];
    NSImage *img = [NSImage imageNamed:@"max.png"];
    [img setSize:NSMakeSize(18, 18)];
    [self.statusBarItem setImage:img];
    
    [NSTimer scheduledTimerWithTimeInterval:.05 target:self selector:@selector(handleEventStates) userInfo:nil repeats:YES];

    [NSEvent addGlobalMonitorForEventsMatchingMask:NSKeyDownMask handler:^(NSEvent *event) {
//        NSLog(@"%d", [event keyCode]);
        self.currentEventState = STATE_OTHER;
        NSUInteger m = [event modifierFlags];

        if (m&NSControlKeyMask && m&NSCommandKeyMask && m&NSShiftKeyMask) {
            if ([event keyCode] == 46) { // m
                self.currentEventState = STATE_MAXIMIZE;
            } else if ([event keyCode] == 37) { // l
                self.currentEventState = STATE_LEFT;
            } else if ([event keyCode] == 15) { // r
                self.currentEventState = STATE_RIGHT;
            } else if ([event keyCode] == 1) { // s
                self.currentEventState = STATE_RESIZE;
            } else if ([event keyCode] == 13) { // w
                self.currentEventState = STATE_MOVE;
            }
        }
    }];
    [NSEvent addGlobalMonitorForEventsMatchingMask:NSKeyUpMask handler:^(NSEvent *event) {
        self.currentEventState = STATE_OTHER;
    }];
}

@end
