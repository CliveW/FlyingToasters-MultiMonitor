//
//  ScreenSaverScene.m
//  Flying Toasters
//
//  Created by Robert Venturini on 3/9/19.
//  Copyright © 2019 Robert Venturini. All rights reserved.
//

#import "ScreenSaverScene.h"
#import "ToasterWorld.h"

static const NSTimeInterval kAnimFrameDuration = 0.085;

@interface ScreenSaverScene ()
@property (strong) NSMutableDictionary<NSNumber*, SKSpriteNode*>* nodeMap;
@end

@implementation ScreenSaverScene

- (instancetype)initWithSize:(CGSize)size
{
    if (self = [super initWithSize:size]) {
        _nodeMap = [NSMutableDictionary dictionary];
    }
    return self;
}

- (BOOL)acceptsFirstResponder
{
    // This scene is intended for use in a screensaver -- do not override the
    // built in screensaver catches or it will be difficult to end...
    return NO;
}

- (void)resetSceneState
{
    [self removeAllChildren];
    [self.nodeMap removeAllObjects];
}

- (void)update:(NSTimeInterval)currentTime
{
    [super update:currentTime];

    ToasterWorld* world = [ToasterWorld shared];
    NSTimeInterval now = CFAbsoluteTimeGetCurrent();
    [world tickAtTime:now];

    NSArray<FTToasterParticle*>* particles = world.particles;
    NSMutableSet<NSNumber*>* seen = [NSMutableSet setWithCapacity:particles.count];

    for (FTToasterParticle* p in particles) {
        NSNumber* key = @(p.particleId);
        [seen addObject:key];

        SKSpriteNode* node = self.nodeMap[key];
        if (!node) {
            node = [SKSpriteNode spriteNodeWithTexture:p.textures.firstObject];
            self.nodeMap[key] = node;
            [self addChild:node];
        }

        CGPoint g = [p positionAtTime:now];
        node.position = CGPointMake(g.x - self.screenOriginInGlobal.x,
                                    g.y - self.screenOriginInGlobal.y);

        if (p.animatesFrames && p.textures.count > 1) {
            NSUInteger frame =
                (NSUInteger)floor((now - p.birthTime) / kAnimFrameDuration) % p.textures.count;
            SKTexture* tex = p.textures[frame];
            if (node.texture != tex) node.texture = tex;
        }
    }

    NSMutableArray<NSNumber*>* gone = nil;
    for (NSNumber* k in self.nodeMap) {
        if (![seen containsObject:k]) {
            if (!gone) gone = [NSMutableArray array];
            [gone addObject:k];
        }
    }
    for (NSNumber* k in gone) {
        [self.nodeMap[k] removeFromParent];
        [self.nodeMap removeObjectForKey:k];
    }
}

@end
