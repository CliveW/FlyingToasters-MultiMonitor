//
//  FlyingToastersView.m
//  Flying Toasters
//
//  Created by Robert Venturini on 3/8/19.
//  Copyright © 2019 Robert Venturini. All rights reserved.
//

#import "FlyingToastersView.h"
#import "ScreenSaverScene.h"
#import "ToasterDefaults.h"
#import "ToasterWorld.h"

@interface FlyingToastersView ()
@property (strong) ScreenSaverScene* toasterScene;
@property (assign) BOOL registeredWithWorld;
@end

@implementation FlyingToastersView

- (instancetype)init
{
    if (self = [super initWithFrame:NSZeroRect]) {
        _toasterScene = [[ScreenSaverScene alloc] initWithSize:self.frame.size];
        _toasterScene.backgroundColor = [NSColor blackColor];

        [self presentScene:_toasterScene];
        // Don't render until -start. The host can create views it never
        // starts (e.g. behind the lock screen); those used to draw an empty,
        // never-started world at full frame rate.
        self.paused = YES;
    }

    return self;
}

- (void)setFrame:(NSRect)frame
{
    [super setFrame:frame];
    _toasterScene.size = frame.size;
}

- (void)setScreenFrameInGlobal:(NSRect)screenFrameInGlobal
{
    _screenFrameInGlobal = screenFrameInGlobal;
    _toasterScene.screenOriginInGlobal = screenFrameInGlobal.origin;
}

- (void)start
{
    ToasterWorld* world = [ToasterWorld shared];
    [world configureWithToastLevel:[ToasterDefaults getToastLevel]
                             speed:[ToasterDefaults getFlightSpeed]
                             count:[ToasterDefaults getNumberOfToasters]
                        cloudCover:[ToasterDefaults getCloudCover]
                   flightDirection:[ToasterDefaults getFlightDirection]
                        toastRatio:[ToasterDefaults getToastRatio]
                     fastFrequency:[ToasterDefaults getFastFrequency]
                      scaleDensity:[ToasterDefaults getScaleDensity]
                            bundle:[NSBundle bundleForClass:[self class]]];
    if (!self.registeredWithWorld) {
        [world registerScreenRect:self.screenFrameInGlobal];
        self.registeredWithWorld = YES;
    }
    [world start];

    // SKView defaults to 60 fps. On a 75 Hz (or 120 Hz) display that paces
    // frames unevenly and the flight path judders.
    self.preferredFramesPerSecond = [self _refreshRateForScreenFrame:self.screenFrameInGlobal];
    self.paused = NO;
}

- (void)end
{
    self.paused = YES;
    // Only a started view holds a reference on the shared world. An
    // unbalanced unregister from a never-started view could drop the count
    // to zero and stop the world under views that were still running.
    if (self.registeredWithWorld) {
        self.registeredWithWorld = NO;
        [[ToasterWorld shared] unregisterScreenRect:self.screenFrameInGlobal];
    }
    [self.toasterScene resetSceneState];
}

- (NSInteger)_refreshRateForScreenFrame:(NSRect)frame
{
    // window.screen is nil for screensaver windows on external displays, so
    // fall back to matching the global frame.
    NSScreen* screen = self.window.screen;
    if (!screen) {
        for (NSScreen* s in [NSScreen screens]) {
            if (NSEqualRects(s.frame, frame)) {
                screen = s;
                break;
            }
        }
    }
    NSInteger fps = screen.maximumFramesPerSecond;
    return fps > 0 ? fps : 60;
}

- (BOOL)acceptsFirstResponder
{
    return NO;
}

@end
