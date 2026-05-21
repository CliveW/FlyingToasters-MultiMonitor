//
//  FlyingToasterPreferencesController.h
//  Flying Toasters
//
//  Created by Robert Venturini on 3/9/19.
//  Copyright © 2019 Robert Venturini. All rights reserved.
//
//  macOS 26 rewrite: builds the prefs window entirely in code rather than
//  loading from a nib. Apple's hosted prefs sheet for legacy savers in
//  macOS 26 appears to break the nib-load path after first use; a
//  programmatic window sidesteps that entirely.
//

#import <Cocoa/Cocoa.h>

@protocol FlyingToasterPreferencesDelegate;

@interface FlyingToasterPreferencesController : NSWindowController
@property (weak) id<FlyingToasterPreferencesDelegate> delegate;
@end


@protocol FlyingToasterPreferencesDelegate <NSObject>
- (void)flyingToasterPreferencesDidFinish:(FlyingToasterPreferencesController*)prefs;
@end
