//
//  ToasterDefaults.m
//  Flying Toasters
//
//  Created by Robert Venturini on 3/9/19.
//  Copyright © 2019 Robert Venturini. All rights reserved.
//

#import "ToasterDefaults.h"
#import <pwd.h>
#import <os/log.h>

NSNotificationName const FlyingToastersPrefsChangedNotification = @"FlyingToastersPrefsChangedNotification";

static NSString* const ToasterDefaultsFlightSpeedKey      = @"toaster_flight_speed";
static NSString* const ToasterDefaultsToastLevelKey       = @"toast_level";
static NSString* const ToasterDefaultsNumberOfToastersKey = @"number_of_toasters";
static NSString* const ToasterDefaultsCloudCoverKey       = @"cloud_cover";
static NSString* const ToasterDefaultsFlightDirectionKey  = @"flight_direction";
static NSString* const ToasterDefaultsToastRatioKey       = @"toast_ratio";
static NSString* const ToasterDefaultsFastFrequencyKey    = @"fast_frequency";
static NSString* const ToasterDefaultsWingFlapMSKey       = @"wing_flap_ms";
static NSString* const ToasterDefaultsScaleDensityKey     = @"scale_density";

@implementation ToasterDefaults

static os_log_t _ftLog(void)
{
    static os_log_t log;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        log = os_log_create("com.vectoriant.flyingtoasters", "prefs");
    });
    return log;
}

// Cache the on-disk dictionary for the lifetime of the process. Invalidate
// on our own writes.
static NSDictionary* sCachedDict = nil;

// macOS 26 hosts the .saver inside legacyScreenSaver.appex, a sandboxed
// App Extension. The host has no write entitlement outside its own
// container, so ~/Library/Screen Savers/ is read-only to us. Instead we
// write inside the container's Application Support, which is always
// writable. NSFileManager.URLForDirectory: returns the sandbox-redirected
// path so the same call resolves correctly in both the prefs UI and the
// animation (both load into the same legacyScreenSaver.appex container).
+ (NSURL*)_prefsDirURL
{
    NSFileManager* fm = [NSFileManager defaultManager];
    NSURL* support = [fm URLForDirectory:NSApplicationSupportDirectory
                                inDomain:NSUserDomainMask
                       appropriateForURL:nil
                                  create:YES
                                   error:nil];
    return [support URLByAppendingPathComponent:@"Flying Toasters" isDirectory:YES];
}

+ (NSURL*)_prefsURL
{
    return [[self _prefsDirURL] URLByAppendingPathComponent:@"prefs.plist"];
}

+ (NSDictionary*)_load
{
    if (!sCachedDict) {
        NSURL* url = [self _prefsURL];
        BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:url.path];
        os_log(_ftLog(), "_load url=%{public}@ exists=%{BOOL}d", url.path, exists);
        NSError* err = nil;
        NSDictionary* d = [NSDictionary dictionaryWithContentsOfURL:url error:&err];
        if (!d && err) {
            os_log_error(_ftLog(), "_load read error: %{public}@", err);
        }
        sCachedDict = d ?: @{};
    }
    return sCachedDict;
}

// Robust write. Strategy: ensure parent dir exists, try atomic write via
// NSPropertyListSerialization+NSData (gives us granular error reporting),
// fall back to non-atomic on failure. Every step is logged.
+ (BOOL)_writeDictionary:(NSDictionary*)dict toURL:(NSURL*)url
{
    NSFileManager* fm = [NSFileManager defaultManager];

    // Step 1: ensure parent directory exists.
    NSURL* parent = [self _prefsDirURL];
    if (![fm fileExistsAtPath:parent.path]) {
        NSError* mkErr = nil;
        BOOL mkOk = [fm createDirectoryAtURL:parent
                withIntermediateDirectories:YES
                                 attributes:nil
                                      error:&mkErr];
        os_log(_ftLog(), "create parent dir %{public}@ ok=%{BOOL}d err=%{public}@",
                    parent.path, mkOk, mkErr);
        if (!mkOk) return NO;
    }

    // Step 2: serialize to NSData.
    NSError* serErr = nil;
    NSData* data = [NSPropertyListSerialization dataWithPropertyList:dict
                                                              format:NSPropertyListBinaryFormat_v1_0
                                                             options:0
                                                               error:&serErr];
    if (!data) {
        os_log_error(_ftLog(), "serialize failed: %{public}@", serErr);
        return NO;
    }

    // Step 3: atomic write first.
    NSError* atomicErr = nil;
    BOOL atomicOk = [data writeToURL:url options:NSDataWritingAtomic error:&atomicErr];
    os_log(_ftLog(), "atomic write url=%{public}@ ok=%{BOOL}d err=%{public}@",
                url.path, atomicOk, atomicErr);
    if (atomicOk) return YES;

    // Step 4: fall back to non-atomic. Some sandbox profiles allow direct
    // writes to a known file path but block the temp-file + rename pattern.
    NSError* directErr = nil;
    BOOL directOk = [data writeToURL:url options:0 error:&directErr];
    os_log(_ftLog(), "direct write url=%{public}@ ok=%{BOOL}d err=%{public}@",
                url.path, directOk, directErr);
    return directOk;
}

+ (void)_persistValue:(id)value forKey:(NSString*)key
{
    NSMutableDictionary* dict = [[self _load] mutableCopy];
    dict[key] = value;
    sCachedDict = [dict copy];

    os_log(_ftLog(), "_persistValue key=%{public}@ value=%{public}@", key, value);
    BOOL ok = [self _writeDictionary:dict toURL:[self _prefsURL]];
    os_log(_ftLog(), "_persistValue final ok=%{BOOL}d", ok);

    [[NSNotificationCenter defaultCenter]
        postNotificationName:FlyingToastersPrefsChangedNotification
                      object:nil];
}

+ (void)invalidateCache
{
    sCachedDict = nil;
}

// Public: write the entire current dict to disk, even if all values are
// defaults. Called when the prefs UI opens so the on-disk file always
// exists for the animation host to read. Idempotent — no-op cost is one
// disk write.
+ (void)ensurePersisted
{
    NSDictionary* base = [self _load];
    NSMutableDictionary* full = [base mutableCopy];

    // Seed every key the animation host might read.
    if (!full[ToasterDefaultsFlightSpeedKey])      full[ToasterDefaultsFlightSpeedKey]      = @(kMediumSpeed);
    if (!full[ToasterDefaultsToastLevelKey])       full[ToasterDefaultsToastLevelKey]       = @(kGoldenBrownToast);
    if (!full[ToasterDefaultsNumberOfToastersKey]) full[ToasterDefaultsNumberOfToastersKey] = @(6);
    if (!full[ToasterDefaultsCloudCoverKey])       full[ToasterDefaultsCloudCoverKey]       = @(0);
    if (!full[ToasterDefaultsFlightDirectionKey])  full[ToasterDefaultsFlightDirectionKey]  = @(kFlightDirectionSW);
    if (!full[ToasterDefaultsToastRatioKey])       full[ToasterDefaultsToastRatioKey]       = @(50);
    if (!full[ToasterDefaultsFastFrequencyKey])    full[ToasterDefaultsFastFrequencyKey]    = @(12);
    if (!full[ToasterDefaultsWingFlapMSKey])       full[ToasterDefaultsWingFlapMSKey]       = @(85);
    if (!full[ToasterDefaultsScaleDensityKey])     full[ToasterDefaultsScaleDensityKey]     = @YES;

    sCachedDict = [full copy];
    os_log(_ftLog(), "ensurePersisted writing %lu keys", (unsigned long)full.count);
    [self _writeDictionary:full toURL:[self _prefsURL]];
}

+ (NSUInteger)_uintForKey:(NSString*)key default:(NSUInteger)defaultValue
{
    NSNumber* n = [self _load][key];
    return n ? [n unsignedIntegerValue] : defaultValue;
}

+ (FlightSpeed)getFlightSpeed
{
    return (FlightSpeed)[self _uintForKey:ToasterDefaultsFlightSpeedKey default:kMediumSpeed];
}

+ (void)setFlightSpeed:(FlightSpeed)speed
{
    [self _persistValue:@(speed) forKey:ToasterDefaultsFlightSpeedKey];
}

+ (ToastLevel)getToastLevel
{
    return (ToastLevel)[self _uintForKey:ToasterDefaultsToastLevelKey default:kGoldenBrownToast];
}

+ (void)setToastLevel:(ToastLevel)level
{
    [self _persistValue:@(level) forKey:ToasterDefaultsToastLevelKey];
}

+ (NSUInteger)getNumberOfToasters
{
    return [self _uintForKey:ToasterDefaultsNumberOfToastersKey default:6];
}

+ (void)setNumberOfToasters:(NSUInteger)numOfToasters
{
    [self _persistValue:@(numOfToasters) forKey:ToasterDefaultsNumberOfToastersKey];
}

+ (NSUInteger)getCloudCover
{
    return [self _uintForKey:ToasterDefaultsCloudCoverKey default:0];
}

+ (void)setCloudCover:(NSUInteger)count
{
    [self _persistValue:@(count) forKey:ToasterDefaultsCloudCoverKey];
}

+ (FlightDirection)getFlightDirection
{
    return (FlightDirection)[self _uintForKey:ToasterDefaultsFlightDirectionKey default:kFlightDirectionSW];
}

+ (void)setFlightDirection:(FlightDirection)direction
{
    [self _persistValue:@(direction) forKey:ToasterDefaultsFlightDirectionKey];
}

+ (NSUInteger)getToastRatio
{
    return [self _uintForKey:ToasterDefaultsToastRatioKey default:50];
}

+ (void)setToastRatio:(NSUInteger)percent
{
    [self _persistValue:@(percent) forKey:ToasterDefaultsToastRatioKey];
}

+ (NSUInteger)getFastFrequency
{
    return [self _uintForKey:ToasterDefaultsFastFrequencyKey default:12];
}

+ (void)setFastFrequency:(NSUInteger)percent
{
    [self _persistValue:@(percent) forKey:ToasterDefaultsFastFrequencyKey];
}

+ (NSUInteger)getWingFlapMS
{
    return [self _uintForKey:ToasterDefaultsWingFlapMSKey default:85];
}

+ (void)setWingFlapMS:(NSUInteger)ms
{
    [self _persistValue:@(ms) forKey:ToasterDefaultsWingFlapMSKey];
}

+ (BOOL)getScaleDensity
{
    NSNumber* n = [self _load][ToasterDefaultsScaleDensityKey];
    return n ? [n boolValue] : YES;
}

+ (void)setScaleDensity:(BOOL)scale
{
    [self _persistValue:@(scale) forKey:ToasterDefaultsScaleDensityKey];
}

@end
