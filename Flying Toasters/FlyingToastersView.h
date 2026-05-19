//
//  FlyingToastersView.h
//  Flying Toasters
//
//  Created by Robert Venturini on 3/8/19.
//  Copyright © 2019 Robert Venturini. All rights reserved.
//

#import <SpriteKit/SpriteKit.h>
#import "ToasterDefaults.h"

@interface FlyingToastersView : SKView

@property ToastLevel toastLevel;    // defaults to GoldenBrownToast
@property FlightSpeed speed;        // defaults to MediumSpeed
@property NSUInteger numOfToasters; // defaults to 6

// This screen's frame in AppKit's global display coordinate space.
// Set by FlyingToasterScreenSaverView before -start.
@property (assign) NSRect screenFrameInGlobal;

- (void)start;
- (void)end;
@end
