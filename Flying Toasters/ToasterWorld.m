//
//  ToasterWorld.m
//  Flying Toasters
//

#import "ToasterWorld.h"

@implementation FTToasterParticle
- (CGPoint)positionAtTime:(NSTimeInterval)t
{
    NSTimeInterval dt = t - self.birthTime;
    return CGPointMake(self.origin.x + self.velocity.dx * dt,
                       self.origin.y + self.velocity.dy * dt);
}
@end


@interface ToasterWorld ()
@property (strong) NSMutableArray<FTToasterParticle*>* mutableParticles;
@property (assign) NSRect globalBounds;
@property (assign) ToastLevel toastLevel;
@property (assign) FlightSpeed speed;
@property (assign) NSUInteger count;
@property (strong) NSBundle* bundle;
@property (assign) BOOL configured;
@property (assign) BOOL isRunning;
@property (assign) uint64_t nextParticleId;
@property (assign) NSTimeInterval nextSpawnTime;
@property (assign) NSUInteger spawnIndex;
@property (assign) NSInteger viewRefCount;
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
        _nextParticleId = 1;
        _globalBounds = NSZeroRect;
    }
    return self;
}

- (NSArray<FTToasterParticle*>*)particles
{
    return [self.mutableParticles copy];
}

- (void)configureWithToastLevel:(ToastLevel)level
                          speed:(FlightSpeed)speed
                          count:(NSUInteger)count
                         bundle:(NSBundle*)bundle
{
    if (self.configured) return;
    self.toastLevel = level;
    self.speed = speed;
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
    self.count = count * areaFactor;
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
}

- (void)stop
{
    self.isRunning = NO;
    [self.mutableParticles removeAllObjects];
}

- (void)tickAtTime:(NSTimeInterval)now
{
    if (!self.isRunning) return;
    if (NSIsEmptyRect(self.globalBounds)) return;

    // Reap particles that have exited the global bounds (with a margin for sprite size).
    NSMutableArray<FTToasterParticle*>* survivors =
        [NSMutableArray arrayWithCapacity:self.mutableParticles.count];
    for (FTToasterParticle* p in self.mutableParticles) {
        CGPoint pos = [p positionAtTime:now];
        CGFloat margin = MAX(p.size.width, p.size.height);
        if (pos.x < NSMinX(self.globalBounds) - margin ||
            pos.y < NSMinY(self.globalBounds) - margin ||
            pos.x > NSMaxX(self.globalBounds) + margin ||
            pos.y > NSMaxY(self.globalBounds) + margin) {
            continue;
        }
        [survivors addObject:p];
    }
    self.mutableParticles = survivors;

    // Initial fill: spawn one per spawnInterval until the population hits
    // count. Thereafter, immediately replace anything reaped.
    NSTimeInterval spawnInterval = (NSTimeInterval)self.speed / 10.0;
    BOOL initialFill = self.mutableParticles.count < self.count && self.spawnIndex < self.count;
    while (self.mutableParticles.count < self.count) {
        if (initialFill && now < self.nextSpawnTime) break;
        FTToasterParticle* p = [self _spawnParticleAtTime:now];
        if (!p) break;
        [self.mutableParticles addObject:p];
        self.nextSpawnTime = now + spawnInterval;
        initialFill = self.spawnIndex < self.count;
    }
}

- (FTToasterParticle*)_spawnParticleAtTime:(NSTimeInterval)now
{
    if (NSIsEmptyRect(self.globalBounds)) return nil;

    NSUInteger idx = self.spawnIndex++;
    BOOL isToast = (idx % 2) == 1;
    BOOL isFast  = !isToast && ((idx % 8) == 0);

    NSArray<SKTexture*>* textures = isToast ? [self _toastTextures] : [self _toasterTextures];
    if (!textures.count) return nil;

    CGSize size = [textures.firstObject size];
    CGFloat nodeDiag = sqrt(size.width*size.width + size.height*size.height);
    CGFloat speedRate = (CGFloat)self.speed / 10.0;
    if (isFast) speedRate = [self _fastSpeedRate];
    CGFloat speedPxPerSec = (nodeDiag / speedRate);

    // Enter from top or right edge of the global rect; fly 45° down-left.
    NSRect b = self.globalBounds;
    CGPoint origin;
    BOOL fromTop = (arc4random_uniform(2) == 0);
    if (fromTop) {
        CGFloat x = NSMinX(b) + (CGFloat)arc4random_uniform((uint32_t)MAX((CGFloat)1, NSWidth(b)));
        origin = CGPointMake(x, NSMaxY(b) + size.height);
    } else {
        CGFloat y = NSMinY(b) + (CGFloat)arc4random_uniform((uint32_t)MAX((CGFloat)1, NSHeight(b)));
        origin = CGPointMake(NSMaxX(b) + size.width, y);
    }
    CGFloat v = speedPxPerSec / M_SQRT2;
    CGVector velocity = CGVectorMake(-v, -v);

    FTToasterParticle* p = [[FTToasterParticle alloc] init];
    p.particleId = self.nextParticleId++;
    p.origin = origin;
    p.velocity = velocity;
    p.birthTime = now;
    p.textures = textures;
    p.animatesFrames = !isToast;
    p.size = size;
    return p;
}

- (CGFloat)_fastSpeedRate
{
    FlightSpeed faster = kFastSpeed;
    switch (self.speed) {
        case kSnailSpeed:     faster = kSlowSpeed;      break;
        case kSlowSpeed:      faster = kMediumSpeed;    break;
        case kMediumSpeed:    faster = kFastSpeed;      break;
        case kFastSpeed:      faster = kLightningSpeed; break;
        case kLightningSpeed: faster = kFastSpeed;      break;
    }
    return (CGFloat)faster / 10.0;
}

- (NSArray<SKTexture*>*)_toasterTextures
{
    NSString* t1 = [self.bundle pathForResource:@"Textures/toaster01" ofType:@"png"];
    NSString* t2 = [self.bundle pathForResource:@"Textures/toaster02" ofType:@"png"];
    NSString* t3 = [self.bundle pathForResource:@"Textures/toaster03" ofType:@"png"];
    NSString* t4 = [self.bundle pathForResource:@"Textures/toaster04" ofType:@"png"];
    if (!t1 || !t2 || !t3 || !t4) return @[];

    SKTexture* T1 = [SKTexture textureWithImageNamed:t1];
    SKTexture* T2 = [SKTexture textureWithImageNamed:t2];
    SKTexture* T3 = [SKTexture textureWithImageNamed:t3];
    SKTexture* T4 = [SKTexture textureWithImageNamed:t4];

    NSMutableArray<SKTexture*>* textures = [@[T1, T2, T3, T4, T3, T2] mutableCopy];
    NSUInteger shift = arc4random_uniform((uint32_t)textures.count);
    while (shift--) {
        id first = textures.firstObject;
        [textures removeObjectAtIndex:0];
        [textures addObject:first];
    }
    return textures;
}

- (NSArray<SKTexture*>*)_toastTextures
{
    NSString* name = @"Textures/toast1.gif";
    switch (self.toastLevel) {
        case kLightToast:       name = @"Textures/toast0.gif"; break;
        case kGoldenBrownToast: name = @"Textures/toast1.gif"; break;
        case kDarkToast:        name = @"Textures/toast2.gif"; break;
        case kBurntToast:       name = @"Textures/toast3.gif"; break;
    }
    NSString* path = [self.bundle pathForResource:name ofType:nil];
    if (!path) return @[];
    return @[[SKTexture textureWithImageNamed:path]];
}

@end
