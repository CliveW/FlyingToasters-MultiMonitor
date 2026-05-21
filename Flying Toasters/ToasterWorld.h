//
//  ToasterWorld.h
//  Flying Toasters
//
//  Created by Clive Wright on 2026-05-19.
//  Copyright © 2026 Clive Wright. Licensed under the MIT License (see LICENSE).
//
//  Process-wide singleton that simulates the toaster swarm across the union
//  of all attached displays. On macOS 14+ legacyScreenSaver hosts every
//  ScreenSaverView for every display in a single process, so a shared
//  singleton suffices — no IPC required.
//
//  Positions are pure functions of CFAbsoluteTime, so each per-screen scene
//  can render the world independently and stay in sync without coordination.
//

#import <Cocoa/Cocoa.h>
#import <SpriteKit/SpriteKit.h>
#import "ToasterDefaults.h"

typedef NS_ENUM(NSUInteger, FTParticleKind) {
    FTParticleKindToaster = 0,
    FTParticleKindToast   = 1,
    FTParticleKindCloud   = 2,
};

@interface FTToasterParticle : NSObject
@property (assign) uint64_t particleId;
@property (assign) FTParticleKind kind;
@property (assign) CGPoint origin;            // AppKit global coords at birth
@property (assign) CGVector velocity;         // pixels/sec
@property (assign) NSTimeInterval birthTime;  // CFAbsoluteTime
@property (strong) NSArray<SKTexture*>* textures;
@property (assign) BOOL animatesFrames;       // toasters yes, toast/clouds no
@property (assign) CGSize size;
@property (assign) CGFloat alpha;             // clouds <1
@property (assign) CGFloat zPosition;         // clouds behind, toasters front
- (CGPoint)positionAtTime:(NSTimeInterval)t;
@end


@interface ToasterWorld : NSObject

+ (instancetype)shared;

// Register/unregister each ScreenSaverView's screen frame in AppKit's
// global display coordinate space. Idempotent.
- (void)registerScreenRect:(NSRect)globalRect;
- (void)unregisterScreenRect:(NSRect)globalRect;

// First-write-wins configuration. All views share the same prefs anyway.
- (void)configureWithToastLevel:(ToastLevel)level
                          speed:(FlightSpeed)speed
                          count:(NSUInteger)count
                      cloudCover:(NSUInteger)cloudCover
                 flightDirection:(FlightDirection)direction
                      toastRatio:(NSUInteger)toastPercent
                   fastFrequency:(NSUInteger)fastPercent
                    scaleDensity:(BOOL)scaleDensity
                          bundle:(NSBundle*)bundle;

- (void)start;
- (void)stop;

// Drive spawn/reap. Cheap; safe to call from every scene's update:.
- (void)tickAtTime:(NSTimeInterval)now;

@property (readonly) NSArray<FTToasterParticle*>* particles;
@property (readonly) NSRect globalBounds;
@property (readonly) BOOL isRunning;

@end
