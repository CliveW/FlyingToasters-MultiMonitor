//
//  ScreenSaverScene.h
//  Flying Toasters
//
//  Created by Robert Venturini on 3/9/19.
//  Copyright © 2019 Robert Venturini. All rights reserved.
//

#import <SpriteKit/SpriteKit.h>

@interface ScreenSaverScene : SKScene

// Origin (bottom-left) of this view's screen in AppKit's global display
// coordinate space. Used to map global particle positions to scene-local
// coordinates each frame.
@property (assign) CGPoint screenOriginInGlobal;

- (void)resetSceneState;

@end
