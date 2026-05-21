//
//  ToasterDefaults.h
//  Flying Toasters
//
//  Created by Robert Venturini on 3/9/19.
//  Copyright © 2019 Robert Venturini. All rights reserved.
//

#import <Cocoa/Cocoa.h>

// Posted whenever any setting is written. Subscribers (ToasterWorld and
// ScreenSaverScene) re-read their inputs from this class so the running
// animation reflects slider changes immediately while the prefs UI is
// open.
extern NSNotificationName const FlyingToastersPrefsChangedNotification;

typedef NS_ENUM(NSUInteger, ToastLevel) {
    kLightToast,
    kGoldenBrownToast,
    kDarkToast,
    kBurntToast
};

typedef NS_ENUM(NSUInteger, FlightSpeed) {
    kSnailSpeed = 20,
    kSlowSpeed = 10,
    kMediumSpeed = 8,
    kFastSpeed = 3,
    kLightningSpeed = 1
};

// 8-way compass. Indices are slider ticks; default SW matches the original
// down-and-left flight path.
typedef NS_ENUM(NSUInteger, FlightDirection) {
    kFlightDirectionN  = 0,
    kFlightDirectionNE = 1,
    kFlightDirectionE  = 2,
    kFlightDirectionSE = 3,
    kFlightDirectionS  = 4,
    kFlightDirectionSW = 5,
    kFlightDirectionW  = 6,
    kFlightDirectionNW = 7,
};

@interface ToasterDefaults : NSObject

+ (FlightSpeed)getFlightSpeed;
+ (void)setFlightSpeed:(FlightSpeed)speed;

+ (ToastLevel)getToastLevel;
+ (void)setToastLevel:(ToastLevel)level;

+ (NSUInteger)getNumberOfToasters;
+ (void)setNumberOfToasters:(NSUInteger)numOfToasters;

+ (NSUInteger)getCloudCover;
+ (void)setCloudCover:(NSUInteger)count;

+ (FlightDirection)getFlightDirection;
+ (void)setFlightDirection:(FlightDirection)direction;

+ (NSUInteger)getToastRatio;
+ (void)setToastRatio:(NSUInteger)percent;

+ (NSUInteger)getFastFrequency;
+ (void)setFastFrequency:(NSUInteger)percent;

+ (NSUInteger)getWingFlapMS;
+ (void)setWingFlapMS:(NSUInteger)ms;

+ (BOOL)getScaleDensity;
+ (void)setScaleDensity:(BOOL)scale;

// Writes the full settings dictionary (with defaults for any missing keys)
// to disk, even if the user hasn't touched a slider. Call this from the
// prefs UI so the on-disk file always exists for the animation host.
+ (void)ensurePersisted;

@end
