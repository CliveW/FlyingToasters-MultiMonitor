//
//  FlyingToasterScreenSaverView.m
//  Flying Toasters
//
//  Created by Robert Venturini on 3/9/19.
//  Copyright © 2019 Robert Venturini. All rights reserved.
//

#import "FlyingToasterPreferencesController.h"
#import "FlyingToastersView.h"
#import "FlyingToasterScreenSaverView.h"

static void FTLogView(NSString* msg)
{
    FILE* f = fopen("/tmp/flyingtoasters.log", "a");
    if (!f) return;
    NSString* line = [NSString stringWithFormat:@"%.3f %@\n",
                      CFAbsoluteTimeGetCurrent(), msg];
    fprintf(f, "%s", [line UTF8String]);
    fclose(f);
}

static NSNotificationName const ScreenSaverWillStopNotificationName = @"com.apple.screensaver.willstop";

@interface FlyingToasterScreenSaverView ()
@property (strong) FlyingToastersView* ftv;
@property (strong) FlyingToasterPreferencesController* prefsController;
@end

@implementation FlyingToasterScreenSaverView
- (instancetype)initWithFrame:(NSRect)frame isPreview:(BOOL)isPreview
{
    if (self = [super initWithFrame:frame isPreview:isPreview]) {
        [self setAnimationTimeInterval:1/30.0];
        
        _ftv = [[FlyingToastersView alloc] init];
        _ftv.frame = NSMakeRect(0, 0, frame.size.width, frame.size.height);
        
        [self addSubview:_ftv];
        
        
        [[NSDistributedNotificationCenter defaultCenter] addObserver:self
                                                            selector:@selector(screenSaverWillStopNotification:)
                                                                name:ScreenSaverWillStopNotificationName
                                                              object:nil];
    }
    
    return self;
}

- (void)setFrame:(NSRect)frame
{
    [super setFrame:frame];
    _ftv.frame = NSMakeRect(0, 0, frame.size.width, frame.size.height);
}

- (void)startAnimation
{
    [super startAnimation];

    self.ftv.toastLevel = [ToasterDefaults getToastLevel];
    self.ftv.speed = [ToasterDefaults getFlightSpeed];
    self.ftv.numOfToasters = [ToasterDefaults getNumberOfToasters];

    [self _captureScreenAndStart:0];
}

- (NSRect)_resolveScreenFrame
{
    if (self.isPreview) {
        return NSMakeRect(0, 0, self.bounds.size.width, self.bounds.size.height);
    }
    if (self.window.screen) {
        return self.window.screen.frame;
    }
    // window.screen is permanently nil for screensaver windows on external
    // displays. NSWindow.deviceDescription[NSScreenNumber] also returns nil.
    // But empirically, NSWindow.frame and NSScreen.frame agree on origin.x and
    // size — only y differs because the window reports in Quartz coords while
    // NSScreen reports in AppKit. Match by (x origin + size) to find the
    // NSScreen this window belongs to and use its canonical AppKit frame.
    if (self.window) {
        NSRect wf = self.window.frame;
        for (NSScreen* s in [NSScreen screens]) {
            if (CGSizeEqualToSize(s.frame.size, wf.size) &&
                fabs(s.frame.origin.x - wf.origin.x) < 1.0) {
                return s.frame;
            }
        }
    }
    return NSZeroRect;
}

- (void)_captureScreenAndStart:(NSUInteger)attempt
{
    NSRect frame = [self _resolveScreenFrame];
    if (NSIsEmptyRect(frame) && attempt < 5) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(50 * NSEC_PER_MSEC)),
                       dispatch_get_main_queue(), ^{
            [self _captureScreenAndStart:attempt + 1];
        });
        return;
    }
    if (NSIsEmptyRect(frame)) {
        frame = NSMakeRect(0, 0, self.bounds.size.width, self.bounds.size.height);
    }
    NSNumber* sn = self.window.deviceDescription[@"NSScreenNumber"];
    FTLogView([NSString stringWithFormat:
        @"view start: frame=%@ window.frame=%@ window.screen=%@ NSScreenNumber=%@ attempt=%lu",
        NSStringFromRect(frame),
        self.window ? NSStringFromRect(self.window.frame) : @"(no window)",
        self.window.screen ? @"yes" : @"NO",
        sn,
        (unsigned long)attempt]);
    self.ftv.screenFrameInGlobal = frame;
    [self.ftv start];
}

- (void)stopAnimation
{
    [super stopAnimation];
    [self.ftv end];
}

- (void)animateOneFrame
{
    return;
}

- (BOOL)hasConfigureSheet
{
    return YES;
}

- (NSWindow*)configureSheet
{
    _prefsController =
    [[FlyingToasterPreferencesController alloc] initWithWindowNibName:@"FlyingToasterPreferencesController"];
    
    return _prefsController.window;
}

- (void)screenSaverWillStopNotification:(NSNotification*)notification
{
    if (@available(macOS 14.0, *)) {
        // Bug in macOS 14+ warrants forcefully exiting the screensaver
        // so that the 'legacyScreenSaver' process will also quit and release its memory.
        // This is hacky, but seems to side step the problem.
        // This approach was reported working on the aerial screensaver here:
        // https://github.com/JohnCoates/Aerial/issues/1305
        exit(0);
    }
}

@end
