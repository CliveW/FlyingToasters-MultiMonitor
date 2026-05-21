//
//  FlyingToastersView.h
//  Flying Toasters
//
//  Created by Robert Venturini on 3/8/19.
//  Copyright © 2019 Robert Venturini. All rights reserved.
//

#import <SpriteKit/SpriteKit.h>

@interface FlyingToastersView : SKView

// This screen's frame in AppKit's global display coordinate space.
// Set by FlyingToasterScreenSaverView before -start.
@property (assign) NSRect screenFrameInGlobal;

- (void)start;
- (void)end;
@end
