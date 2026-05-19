//
//  ToasterWorld.h
//  Flying Toasters
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

@interface FTToasterParticle : NSObject
@property (assign) uint64_t particleId;
@property (assign) CGPoint origin;            // AppKit global coords at birth
@property (assign) CGVector velocity;         // pixels/sec
@property (assign) NSTimeInterval birthTime;  // CFAbsoluteTime
@property (strong) NSArray<SKTexture*>* textures;
@property (assign) BOOL animatesFrames;       // toasters yes, toast no
@property (assign) CGSize size;
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
                         bundle:(NSBundle*)bundle;

- (void)start;
- (void)stop;

// Drive spawn/reap. Cheap; safe to call from every scene's update:.
- (void)tickAtTime:(NSTimeInterval)now;

@property (readonly) NSArray<FTToasterParticle*>* particles;
@property (readonly) NSRect globalBounds;
@property (readonly) BOOL isRunning;

@end
