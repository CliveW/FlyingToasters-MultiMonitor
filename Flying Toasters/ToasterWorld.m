//
//  ToasterWorld.m
//  Flying Toasters
//
//  Created by Clive Wright on 2026-05-19.
//  Copyright © 2026 Clive Wright. Licensed under the MIT License (see LICENSE).
//

#import "ToasterWorld.h"

@implementation FTToasterParticle
- (instancetype)init
{
    if (self = [super init]) {
        _alpha = 1.0;
        _zPosition = 0.0;
        _kind = FTParticleKindToaster;
    }
    return self;
}
- (CGPoint)positionAtTime:(NSTimeInterval)t
{
    NSTimeInterval dt = t - self.birthTime;
    return CGPointMake(self.origin.x + self.velocity.dx * dt,
                       self.origin.y + self.velocity.dy * dt);
}
@end


@interface ToasterWorld ()
@property (strong) NSMutableArray<FTToasterParticle*>* mutableParticles;  // toasters + toast
@property (strong) NSMutableArray<FTToasterParticle*>* mutableClouds;
@property (assign) NSRect globalBounds;
@property (assign) ToastLevel toastLevel;
@property (assign) FlightSpeed speed;
@property (assign) NSUInteger count;
@property (assign) NSUInteger cloudCover;
@property (assign) FlightDirection flightDirection;
@property (assign) NSUInteger toastRatio;        // 0..100
@property (assign) NSUInteger fastFrequency;     // 0 = disabled
@property (assign) BOOL scaleDensity;
@property (strong) NSBundle* bundle;
@property (assign) BOOL configured;
@property (assign) BOOL isRunning;
@property (assign) uint64_t nextParticleId;
@property (assign) NSTimeInterval nextSpawnTime;
@property (assign) NSUInteger spawnIndex;
@property (assign) NSInteger viewRefCount;

// Lazy-built texture caches.
@property (strong) NSArray<SKTexture*>* cachedToasterTextures;
@property (strong) NSDictionary<NSNumber*, SKTexture*>* cachedToastTextures;  // ToastLevel -> texture
@property (strong) SKTexture* cachedCloudTexture;
@end


@implementation ToasterWorld

+ (instancetype)shared
{
    static ToasterWorld* s_instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s_instance = [[ToasterWorld alloc] init];
    });
    return s_instance;
}

- (instancetype)init
{
    if (self = [super init]) {
        _mutableParticles = [NSMutableArray array];
        _mutableClouds = [NSMutableArray array];
        _nextParticleId = 1;
        _globalBounds = NSZeroRect;
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_prefsChanged:)
                                                     name:FlyingToastersPrefsChangedNotification
                                                   object:nil];
    }
    return self;
}

- (void)_prefsChanged:(NSNotification*)note
{
    // Skip until first configure call has supplied a bundle (we need it to
    // load textures).
    if (!self.bundle) return;
    [self _applyCurrentDefaults];
}

// Re-read every property from ToasterDefaults and recompute derived state.
// Cheap — just a dozen NSDictionary lookups + an NSScreen.screens walk.
- (void)_applyCurrentDefaults
{
    self.toastLevel       = [ToasterDefaults getToastLevel];
    self.speed            = [ToasterDefaults getFlightSpeed];
    self.flightDirection  = [ToasterDefaults getFlightDirection];
    self.toastRatio       = MIN([ToasterDefaults getToastRatio], (NSUInteger)100);
    self.fastFrequency    = [ToasterDefaults getFastFrequency];
    self.scaleDensity     = [ToasterDefaults getScaleDensity];
    self.cloudCover       = [ToasterDefaults getCloudCover];

    NSUInteger count = [ToasterDefaults getNumberOfToasters];
    NSArray<NSScreen*>* allScreens = [NSScreen screens];
    CGFloat largestArea = 1.0;
    NSRect computedBounds = NSZeroRect;
    BOOL first = YES;
    for (NSScreen* s in allScreens) {
        NSRect f = s.frame;
        CGFloat a = f.size.width * f.size.height;
        if (a > largestArea) largestArea = a;
        if (first) { computedBounds = f; first = NO; }
        else       { computedBounds = NSUnionRect(computedBounds, f); }
    }
    CGFloat globalArea = computedBounds.size.width * computedBounds.size.height;
    NSUInteger areaFactor = MAX((NSUInteger)1, (NSUInteger)ceil(globalArea / largestArea));
    self.count = self.scaleDensity ? (count * areaFactor) : count;

    // Toast texture cache depends on toastLevel — invalidate so it rebuilds
    // with the current level on next spawn. Toaster textures are
    // level-independent now that style is gone, so leave that cache alone.
    self.cachedToastTextures = nil;
}

- (NSArray<FTToasterParticle*>*)particles
{
    NSMutableArray<FTToasterParticle*>* all =
        [NSMutableArray arrayWithCapacity:self.mutableParticles.count + self.mutableClouds.count];
    [all addObjectsFromArray:self.mutableClouds];
    [all addObjectsFromArray:self.mutableParticles];
    return all;
}

- (void)configureWithToastLevel:(ToastLevel)level
                          speed:(FlightSpeed)speed
                          count:(NSUInteger)count
                      cloudCover:(NSUInteger)cloudCover
                 flightDirection:(FlightDirection)direction
                      toastRatio:(NSUInteger)toastPercent
                   fastFrequency:(NSUInteger)fastPercent
                    scaleDensity:(BOOL)scaleDensity
                          bundle:(NSBundle*)bundle
{
    if (self.configured) return;
    self.toastLevel = level;
    self.speed = speed;
    self.cloudCover = cloudCover;
    self.flightDirection = direction;
    self.toastRatio = MIN(toastPercent, (NSUInteger)100);
    self.fastFrequency = fastPercent;
    self.scaleDensity = scaleDensity;
    self.bundle = bundle;

    // Compute the virtual-desktop union directly from NSScreen.screens so
    // bounds are correct even if per-view registration is racy. Scale count
    // by total area divided by the largest single screen — this handles
    // non-rectangular layouts (gaps between displays) where a screen-count
    // multiplier would under-provision.
    NSArray<NSScreen*>* allScreens = [NSScreen screens];
    NSRect computedBounds = NSZeroRect;
    BOOL first = YES;
    CGFloat largestArea = 1.0;
    for (NSScreen* s in allScreens) {
        NSRect f = s.frame;
        CGFloat a = f.size.width * f.size.height;
        if (a > largestArea) largestArea = a;
        if (first) { computedBounds = f; first = NO; }
        else       { computedBounds = NSUnionRect(computedBounds, f); }
    }
    CGFloat globalArea = computedBounds.size.width * computedBounds.size.height;
    NSUInteger areaFactor = MAX((NSUInteger)1, (NSUInteger)ceil(globalArea / largestArea));
    if (scaleDensity) {
        self.count = count * areaFactor;
    } else {
        self.count = count;
    }
    if (NSIsEmptyRect(self.globalBounds)) {
        self.globalBounds = computedBounds;
    }

    self.configured = YES;
}

- (void)registerScreenRect:(NSRect)globalRect
{
    self.viewRefCount++;
}

- (void)unregisterScreenRect:(NSRect)globalRect
{
    self.viewRefCount--;
    if (self.viewRefCount <= 0) {
        self.viewRefCount = 0;
        [self stop];
    }
}

- (void)start
{
    if (self.isRunning) return;
    self.isRunning = YES;
    self.spawnIndex = 0;
    self.nextSpawnTime = CFAbsoluteTimeGetCurrent();
    [self.mutableParticles removeAllObjects];
    [self.mutableClouds removeAllObjects];
}

- (void)stop
{
    self.isRunning = NO;
    [self.mutableParticles removeAllObjects];
    [self.mutableClouds removeAllObjects];

    // Allow a subsequent -start to pick up fresh defaults (matters when the
    // System Settings preview re-instantiates the world between slider
    // changes). Cached textures must also drop so a toast-level change
    // becomes visible without restarting the host process.
    self.configured = NO;
    self.cachedToasterTextures = nil;
    self.cachedToastTextures = nil;
    self.cachedCloudTexture = nil;
}

- (void)tickAtTime:(NSTimeInterval)now
{
    if (!self.isRunning) return;
    if (NSIsEmptyRect(self.globalBounds)) return;

    [self _reapAndSpawnToastersAtTime:now];
    [self _reapAndSpawnCloudsAtTime:now];
}

#pragma mark - Toasters + toast

- (void)_reapAndSpawnToastersAtTime:(NSTimeInterval)now
{
    NSMutableArray<FTToasterParticle*>* survivors =
        [NSMutableArray arrayWithCapacity:self.mutableParticles.count];
    for (FTToasterParticle* p in self.mutableParticles) {
        if ([self _particleInBounds:p atTime:now]) [survivors addObject:p];
    }
    self.mutableParticles = survivors;

    NSTimeInterval spawnInterval = (NSTimeInterval)self.speed / 10.0;
    BOOL initialFill = self.mutableParticles.count < self.count && self.spawnIndex < self.count;
    while (self.mutableParticles.count < self.count) {
        if (initialFill && now < self.nextSpawnTime) break;
        FTToasterParticle* p = [self _spawnToasterAtTime:now];
        if (!p) break;
        [self.mutableParticles addObject:p];
        self.nextSpawnTime = now + spawnInterval;
        initialFill = self.spawnIndex < self.count;
    }
}

- (FTToasterParticle*)_spawnToasterAtTime:(NSTimeInterval)now
{
    if (NSIsEmptyRect(self.globalBounds)) return nil;

    self.spawnIndex++;

    // Toast vs toaster: probabilistic by ratio.
    BOOL isToast = (self.toastRatio > 0) &&
                   (arc4random_uniform(100) < (uint32_t)self.toastRatio);
    // Fast variant: only on non-toast, probabilistic by percentage.
    // fastFrequency is a 0-100 chance that any given non-toast spawn is
    // upgraded to the fast variant.
    BOOL isFast = !isToast && (self.fastFrequency > 0) &&
                  (arc4random_uniform(100) < (uint32_t)self.fastFrequency);

    NSArray<SKTexture*>* textures = isToast ? [self _toastTextures] : [self _toasterTextures];
    if (!textures.count) return nil;

    CGSize size = [textures.firstObject size];
    CGFloat nodeDiag = sqrt(size.width*size.width + size.height*size.height);
    CGFloat speedRate = (CGFloat)self.speed / 10.0;
    if (isFast) speedRate = [self _fastSpeedRate];
    CGFloat speedPxPerSec = (nodeDiag / speedRate);

    CGPoint origin = CGPointZero;
    CGVector velocity = CGVectorMake(0, 0);
    [self _originAndVelocityForDirection:self.flightDirection
                                  speed:speedPxPerSec
                                   size:size
                                 origin:&origin
                               velocity:&velocity];

    FTToasterParticle* p = [[FTToasterParticle alloc] init];
    p.particleId = self.nextParticleId++;
    p.kind = isToast ? FTParticleKindToast : FTParticleKindToaster;
    p.origin = origin;
    p.velocity = velocity;
    p.birthTime = now;
    p.textures = textures;
    p.animatesFrames = !isToast;
    p.size = size;
    p.alpha = 1.0;
    p.zPosition = 10.0;
    return p;
}

#pragma mark - Clouds

- (void)_reapAndSpawnCloudsAtTime:(NSTimeInterval)now
{
    if (self.cloudCover == 0) {
        if (self.mutableClouds.count) [self.mutableClouds removeAllObjects];
        return;
    }

    NSMutableArray<FTToasterParticle*>* survivors =
        [NSMutableArray arrayWithCapacity:self.mutableClouds.count];
    for (FTToasterParticle* c in self.mutableClouds) {
        if ([self _particleInBounds:c atTime:now]) [survivors addObject:c];
    }
    self.mutableClouds = survivors;

    while (self.mutableClouds.count < self.cloudCover) {
        FTToasterParticle* c = [self _spawnCloudAtTime:now];
        if (!c) break;
        [self.mutableClouds addObject:c];
    }
}

- (FTToasterParticle*)_spawnCloudAtTime:(NSTimeInterval)now
{
    if (NSIsEmptyRect(self.globalBounds)) return nil;
    SKTexture* tex = [self _cloudTexture];
    if (!tex) return nil;

    CGSize baseSize = tex.size;
    // Randomise size 0.6x .. 1.4x for visual variety.
    CGFloat scale = 0.6 + (CGFloat)arc4random_uniform(80) / 100.0;
    CGSize size = CGSizeMake(baseSize.width * scale, baseSize.height * scale);

    NSRect b = self.globalBounds;
    // Clouds drift at a leisurely pace in the horizontal direction matching
    // the toaster flight (aesthetic coherence — wind blows one way).
    // For purely-vertical flight directions, pick a random horizontal.
    BOOL goingLeft;
    switch (self.flightDirection) {
        case kFlightDirectionW:
        case kFlightDirectionNW:
        case kFlightDirectionSW: goingLeft = YES; break;
        case kFlightDirectionE:
        case kFlightDirectionNE:
        case kFlightDirectionSE: goingLeft = NO;  break;
        default:                 goingLeft = (arc4random_uniform(2) == 0); break;
    }
    CGFloat cloudSpeed = 8.0 + (CGFloat)arc4random_uniform(12);   // px/sec
    CGFloat dx = goingLeft ? -cloudSpeed : cloudSpeed;
    CGFloat startX = goingLeft ? (NSMaxX(b) + size.width) : (NSMinX(b) - size.width);
    CGFloat upperHalfY = NSMinY(b) + NSHeight(b) * 0.5 +
                         (CGFloat)arc4random_uniform((uint32_t)MAX((CGFloat)1, NSHeight(b) * 0.45));

    FTToasterParticle* c = [[FTToasterParticle alloc] init];
    c.particleId = self.nextParticleId++;
    c.kind = FTParticleKindCloud;
    c.origin = CGPointMake(startX, upperHalfY);
    c.velocity = CGVectorMake(dx, 0);
    c.birthTime = now;
    c.textures = @[tex];
    c.animatesFrames = NO;
    c.size = size;
    c.alpha = 0.35;
    c.zPosition = -10.0;  // behind everything
    return c;
}

#pragma mark - Geometry helpers

- (BOOL)_particleInBounds:(FTToasterParticle*)p atTime:(NSTimeInterval)t
{
    CGPoint pos = [p positionAtTime:t];
    CGFloat margin = MAX(p.size.width, p.size.height);
    if (pos.x < NSMinX(self.globalBounds) - margin) return NO;
    if (pos.y < NSMinY(self.globalBounds) - margin) return NO;
    if (pos.x > NSMaxX(self.globalBounds) + margin) return NO;
    if (pos.y > NSMaxY(self.globalBounds) + margin) return NO;
    return YES;
}

- (void)_originAndVelocityForDirection:(FlightDirection)direction
                                 speed:(CGFloat)speedPxPerSec
                                  size:(CGSize)size
                                origin:(CGPoint*)outOrigin
                              velocity:(CGVector*)outVelocity
{
    NSRect b = self.globalBounds;
    CGFloat ux = 0, uy = 0;
    switch (direction) {
        case kFlightDirectionN:  ux = 0;            uy = 1;            break;
        case kFlightDirectionNE: ux = M_SQRT1_2;    uy = M_SQRT1_2;    break;
        case kFlightDirectionE:  ux = 1;            uy = 0;            break;
        case kFlightDirectionSE: ux = M_SQRT1_2;    uy = -M_SQRT1_2;   break;
        case kFlightDirectionS:  ux = 0;            uy = -1;           break;
        case kFlightDirectionSW: ux = -M_SQRT1_2;   uy = -M_SQRT1_2;   break;
        case kFlightDirectionW:  ux = -1;           uy = 0;            break;
        case kFlightDirectionNW: ux = -M_SQRT1_2;   uy = M_SQRT1_2;    break;
    }
    *outVelocity = CGVectorMake(ux * speedPxPerSec, uy * speedPxPerSec);

    // Spawn just outside the edge the particle is flying AWAY FROM.
    BOOL canSpawnHorizontal = (ux != 0);
    BOOL canSpawnVertical = (uy != 0);
    BOOL spawnFromHorizontalEdge;
    if (canSpawnHorizontal && canSpawnVertical) {
        spawnFromHorizontalEdge = (arc4random_uniform(2) == 0);
    } else {
        spawnFromHorizontalEdge = canSpawnHorizontal;
    }

    if (spawnFromHorizontalEdge) {
        CGFloat x = (ux < 0) ? (NSMaxX(b) + size.width) : (NSMinX(b) - size.width);
        CGFloat y = NSMinY(b) + (CGFloat)arc4random_uniform((uint32_t)MAX((CGFloat)1, NSHeight(b)));
        *outOrigin = CGPointMake(x, y);
    } else {
        CGFloat x = NSMinX(b) + (CGFloat)arc4random_uniform((uint32_t)MAX((CGFloat)1, NSWidth(b)));
        CGFloat y = (uy < 0) ? (NSMaxY(b) + size.height) : (NSMinY(b) - size.height);
        *outOrigin = CGPointMake(x, y);
    }
}

- (CGFloat)_fastSpeedRate
{
    // FlightSpeed values are inverse rates (smaller = faster), so each
    // "faster" arm picks the next smaller enum value. At Lightning we're
    // already at the floor; stay there rather than wrapping back to
    // kFastSpeed (which would actually be slower).
    FlightSpeed faster = kFastSpeed;
    switch (self.speed) {
        case kSnailSpeed:     faster = kSlowSpeed;      break;
        case kSlowSpeed:      faster = kMediumSpeed;    break;
        case kMediumSpeed:    faster = kFastSpeed;      break;
        case kFastSpeed:      faster = kLightningSpeed; break;
        case kLightningSpeed: faster = kLightningSpeed; break;
    }
    return (CGFloat)faster / 10.0;
}

#pragma mark - Textures

- (NSArray<SKTexture*>*)_toasterTextures
{
    if (self.cachedToasterTextures) return self.cachedToasterTextures;

    NSString* t1 = [self.bundle pathForResource:@"Textures/toaster01" ofType:@"png"];
    NSString* t2 = [self.bundle pathForResource:@"Textures/toaster02" ofType:@"png"];
    NSString* t3 = [self.bundle pathForResource:@"Textures/toaster03" ofType:@"png"];
    NSString* t4 = [self.bundle pathForResource:@"Textures/toaster04" ofType:@"png"];
    if (!t1 || !t2 || !t3 || !t4) return @[];

    NSArray<NSString*>* paths = @[t1, t2, t3, t4];
    NSMutableArray<SKTexture*>* base = [NSMutableArray arrayWithCapacity:paths.count];
    for (NSString* p in paths) {
        NSImage* img = [[NSImage alloc] initWithContentsOfFile:p];
        if (!img) continue;
        [base addObject:[SKTexture textureWithImage:img]];
    }
    if (base.count != paths.count) return @[];

    // Classic four frames cycle as [T1, T2, T3, T4, T3, T2] for a smooth
    // open/close motion.
    NSMutableArray<SKTexture*>* cycle = [NSMutableArray arrayWithObjects:
        base[0], base[1], base[2], base[3], base[2], base[1], nil];

    // Random phase shift so a swarm of toasters isn't synchronised.
    NSUInteger shift = arc4random_uniform((uint32_t)cycle.count);
    while (shift--) {
        id first = cycle.firstObject;
        [cycle removeObjectAtIndex:0];
        [cycle addObject:first];
    }
    self.cachedToasterTextures = cycle;
    return cycle;
}

- (NSArray<SKTexture*>*)_toastTextures
{
    if (!self.cachedToastTextures) self.cachedToastTextures = [NSMutableDictionary dictionary];
    NSNumber* key = @(self.toastLevel);
    SKTexture* cached = self.cachedToastTextures[key];
    if (cached) return @[cached];

    NSString* name = @"Textures/toast1";
    switch (self.toastLevel) {
        case kLightToast:       name = @"Textures/toast0"; break;
        case kGoldenBrownToast: name = @"Textures/toast1"; break;
        case kDarkToast:        name = @"Textures/toast2"; break;
        case kBurntToast:       name = @"Textures/toast3"; break;
    }
    NSString* path = [self.bundle pathForResource:name ofType:@"gif"];
    if (!path) return @[];
    NSImage* img = [[NSImage alloc] initWithContentsOfFile:path];
    if (!img) return @[];
    SKTexture* tex = [SKTexture textureWithImage:img];
    NSMutableDictionary* mut = [self.cachedToastTextures mutableCopy];
    mut[key] = tex;
    self.cachedToastTextures = mut;
    return @[tex];
}

- (SKTexture*)_cloudTexture
{
    if (self.cachedCloudTexture) return self.cachedCloudTexture;

    NSInteger w = 200, h = 100;
    NSBitmapImageRep* rep =
        [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                pixelsWide:w
                                                pixelsHigh:h
                                             bitsPerSample:8
                                           samplesPerPixel:4
                                                  hasAlpha:YES
                                                  isPlanar:NO
                                            colorSpaceName:NSDeviceRGBColorSpace
                                               bytesPerRow:0
                                              bitsPerPixel:0];
    NSGraphicsContext* gc = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:gc];

    CGContextRef ctx = gc.CGContext;
    CGContextSetShouldAntialias(ctx, YES);

    // Soft white cloud built from three overlapping ovals with a generous
    // outer shadow to feather the edges into the background.
    CGContextSaveGState(ctx);
    CGFloat shadowComponents[] = {1.0, 1.0, 1.0, 0.7};
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGColorRef shadowColor = CGColorCreate(cs, shadowComponents);
    CGContextSetShadowWithColor(ctx, CGSizeZero, 18.0, shadowColor);
    CGColorRelease(shadowColor);
    CGColorSpaceRelease(cs);

    CGContextSetRGBFillColor(ctx, 1, 1, 1, 0.95);
    CGContextFillEllipseInRect(ctx, CGRectMake( 10, 30,  90, 50));
    CGContextFillEllipseInRect(ctx, CGRectMake( 55, 18,  80, 64));
    CGContextFillEllipseInRect(ctx, CGRectMake(110, 30,  80, 50));
    CGContextRestoreGState(ctx);

    [NSGraphicsContext restoreGraphicsState];

    NSImage* img = [[NSImage alloc] initWithSize:NSMakeSize(w, h)];
    [img addRepresentation:rep];

    self.cachedCloudTexture = [SKTexture textureWithImage:img];
    return self.cachedCloudTexture;
}

#pragma mark - Public accessor for wing-flap timing

// ScreenSaverScene reads wing-flap interval from defaults directly; we
// don't expose state here to avoid a circular dependency. See
// ScreenSaverScene.m.

@end
