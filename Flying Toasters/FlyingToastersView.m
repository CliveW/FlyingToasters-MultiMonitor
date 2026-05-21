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
@end

@implementation FlyingToastersView

- (instancetype)init
{
    if (self = [super initWithFrame:NSZeroRect]) {
        _toasterScene = [[ScreenSaverScene alloc] initWithSize:self.frame.size];
        _toasterScene.backgroundColor = [NSColor blackColor];

        [self presentScene:_toasterScene];
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
    [world registerScreenRect:self.screenFrameInGlobal];
    [world start];
}

- (void)end
{
    ToasterWorld* world = [ToasterWorld shared];
    [world unregisterScreenRect:self.screenFrameInGlobal];
    [self.toasterScene resetSceneState];
}

- (BOOL)acceptsFirstResponder
{
    return NO;
}

@end
