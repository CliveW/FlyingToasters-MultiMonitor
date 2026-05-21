//
//  FlyingToasterPreferencesController.m
//  Flying Toasters
//
//  Created by Robert Venturini on 3/9/19.
//  Copyright © 2019 Robert Venturini. All rights reserved.
//

#import "FlyingToasterPreferencesController.h"
#import "ToasterDefaults.h"

// Window geometry.
static const CGFloat kWindowWidth   = 660;
static const CGFloat kWindowHeight  = 540;
static const CGFloat kColumnWidth   = 300;
static const CGFloat kSliderWidth   = 270;
static const CGFloat kRowSpacing    = 14;
static const CGFloat kColumnSpacing = 30;
static const CGFloat kEdgePadding   = 24;

@interface FlyingToasterPreferencesController ()
@property (strong) NSSlider*    densitySlider;
@property (strong) NSSlider*    styleSlider;
@property (strong) NSTextField* styleValueLabel;
@property (strong) NSSlider*    speedSlider;
@property (strong) NSSlider*    wingFlapSlider;
@property (strong) NSSlider*    directionSlider;
@property (strong) NSTextField* directionValueLabel;
@property (strong) NSSlider*    ratioSlider;
@property (strong) NSSlider*    fastFreqSlider;
@property (strong) NSSlider*    toastLevelSlider;
@property (strong) NSSlider*    cloudCoverSlider;
@property (strong) NSButton*    scaleDensityCheckbox;
@end


@implementation FlyingToasterPreferencesController

- (instancetype)init
{
    NSRect contentRect = NSMakeRect(0, 0, kWindowWidth, kWindowHeight);
    NSWindow* window =
        [[NSWindow alloc] initWithContentRect:contentRect
                                    styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                      backing:NSBackingStoreBuffered
                                        defer:NO];
    window.title = @"Flying Toasters";
    window.releasedWhenClosed = NO;

    if (self = [super initWithWindow:window]) {
        // Materialise the prefs file on first open so the animation host
        // always has something to read, and so write errors surface in
        // os_log even if the user doesn't touch a slider.
        [ToasterDefaults ensurePersisted];
        [self _buildContent];
        [self _loadValuesFromDefaults];
    }
    return self;
}

#pragma mark - Layout

- (void)_buildContent
{
    NSView* root = self.window.contentView;
    root.wantsLayer = YES;

    // Two column stacks side by side; Done button bottom right.
    NSStackView* leftCol  = [self _verticalStack];
    NSStackView* rightCol = [self _verticalStack];

    // Left column — motion / toasters.
    self.densitySlider = [self _appendSliderRowToStack:leftCol
                                                 title:@"Toasters per Display"
                                              minLabel:@"Sparse"
                                              maxLabel:@"Flock"
                                                   min:1 max:20 ticks:20
                                                action:@selector(_densityChanged:)];

    NSTextField* styleVD = nil;
    self.styleSlider = [self _appendSliderRowToStack:leftCol
                                               title:@"Toaster Style"
                                            minLabel:@"Classic"
                                            maxLabel:@"Inverted"
                                                 min:0 max:2 ticks:3
                                              action:@selector(_styleChanged:)
                                       valueDisplay:&styleVD];
    self.styleValueLabel = styleVD;

    self.speedSlider = [self _appendSliderRowToStack:leftCol
                                               title:@"Flight Speed"
                                            minLabel:@"Slow"
                                            maxLabel:@"Fast"
                                                 min:0 max:4 ticks:5
                                              action:@selector(_speedChanged:)];

    self.wingFlapSlider = [self _appendSliderRowToStack:leftCol
                                                  title:@"Wing-Flap Speed"
                                               minLabel:@"Slow"
                                               maxLabel:@"Fast"
                                                    min:0 max:8 ticks:9
                                                 action:@selector(_wingFlapChanged:)];

    NSTextField* dirVD = nil;
    self.directionSlider = [self _appendSliderRowToStack:leftCol
                                                   title:@"Flight Direction"
                                                minLabel:@"N"
                                                maxLabel:@"NW"
                                                     min:0 max:7 ticks:8
                                                  action:@selector(_directionChanged:)
                                            valueDisplay:&dirVD];
    self.directionValueLabel = dirVD;

    self.ratioSlider = [self _appendSliderRowToStack:leftCol
                                               title:@"Toast / Toaster Ratio"
                                            minLabel:@"All Toasters"
                                            maxLabel:@"All Toast"
                                                 min:0 max:100 ticks:11
                                              action:@selector(_ratioChanged:)];

    self.fastFreqSlider = [self _appendSliderRowToStack:leftCol
                                                  title:@"Fast Toaster Frequency"
                                               minLabel:@"Off"
                                               maxLabel:@"Often"
                                                    min:0 max:100 ticks:11
                                                 action:@selector(_fastFreqChanged:)];

    // Right column — visuals / display.
    self.toastLevelSlider = [self _appendSliderRowToStack:rightCol
                                                    title:@"Toast Level"
                                                 minLabel:@"Light"
                                                 maxLabel:@"Burnt"
                                                      min:0 max:3 ticks:4
                                                   action:@selector(_toastLevelChanged:)];

    self.cloudCoverSlider = [self _appendSliderRowToStack:rightCol
                                                    title:@"Cloud Cover"
                                                 minLabel:@"Clear"
                                                 maxLabel:@"Overcast"
                                                      min:0 max:20 ticks:11
                                                   action:@selector(_cloudCoverChanged:)];

    // Scale density checkbox.
    self.scaleDensityCheckbox =
        [NSButton checkboxWithTitle:@"Constant density across displays"
                             target:self
                             action:@selector(_scaleDensityChanged:)];
    [self _appendControlRowToStack:rightCol view:self.scaleDensityCheckbox];

    // Outer horizontal stack.
    NSStackView* columns = [NSStackView stackViewWithViews:@[leftCol, rightCol]];
    columns.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    columns.spacing = kColumnSpacing;
    columns.alignment = NSLayoutAttributeTop;
    columns.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:columns];

    // Done button bottom-right.
    NSButton* done = [NSButton buttonWithTitle:@"Done"
                                        target:self
                                        action:@selector(_donePressed:)];
    done.keyEquivalent = @"\r";
    done.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:done];

    [NSLayoutConstraint activateConstraints:@[
        [columns.topAnchor      constraintEqualToAnchor:root.topAnchor      constant:kEdgePadding],
        [columns.leadingAnchor  constraintEqualToAnchor:root.leadingAnchor  constant:kEdgePadding],
        [columns.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-kEdgePadding],

        [done.trailingAnchor    constraintEqualToAnchor:root.trailingAnchor constant:-kEdgePadding],
        [done.bottomAnchor      constraintEqualToAnchor:root.bottomAnchor   constant:-kEdgePadding],
        [done.widthAnchor       constraintGreaterThanOrEqualToConstant:90],
    ]];
}

- (NSStackView*)_verticalStack
{
    NSStackView* s = [NSStackView stackViewWithViews:@[]];
    s.orientation = NSUserInterfaceLayoutOrientationVertical;
    s.alignment = NSLayoutAttributeLeading;
    s.spacing = kRowSpacing;
    s.translatesAutoresizingMaskIntoConstraints = NO;
    [s setHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationHorizontal];
    return s;
}

- (NSSlider*)_appendSliderRowToStack:(NSStackView*)stack
                               title:(NSString*)title
                            minLabel:(NSString*)minLabel
                            maxLabel:(NSString*)maxLabel
                                 min:(double)minVal
                                 max:(double)maxVal
                               ticks:(NSInteger)ticks
                              action:(SEL)action
{
    return [self _appendSliderRowToStack:stack
                                   title:title
                                minLabel:minLabel
                                maxLabel:maxLabel
                                     min:minVal
                                     max:maxVal
                                   ticks:ticks
                                  action:action
                            valueDisplay:NULL];
}

- (NSSlider*)_appendSliderRowToStack:(NSStackView*)stack
                               title:(NSString*)title
                            minLabel:(NSString*)minLabel
                            maxLabel:(NSString*)maxLabel
                                 min:(double)minVal
                                 max:(double)maxVal
                               ticks:(NSInteger)ticks
                              action:(SEL)action
                        valueDisplay:(NSTextField**)outValueDisplay
{
    NSTextField* titleLabel = [NSTextField labelWithString:title];
    titleLabel.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize] weight:NSFontWeightSemibold];

    NSSlider* slider = [NSSlider sliderWithTarget:self action:action];
    slider.minValue = minVal;
    slider.maxValue = maxVal;
    slider.numberOfTickMarks = (NSInteger)ticks;
    slider.allowsTickMarkValuesOnly = YES;
    slider.tickMarkPosition = NSTickMarkPositionAbove;
    slider.translatesAutoresizingMaskIntoConstraints = NO;
    [slider.widthAnchor constraintEqualToConstant:kSliderWidth].active = YES;

    NSTextField* minTickLabel = [NSTextField labelWithString:minLabel];
    NSTextField* maxTickLabel = [NSTextField labelWithString:maxLabel];
    minTickLabel.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    maxTickLabel.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    maxTickLabel.alignment = NSTextAlignmentRight;

    NSStackView* tickRow = [NSStackView stackViewWithViews:@[minTickLabel, [NSView new], maxTickLabel]];
    tickRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    tickRow.distribution = NSStackViewDistributionFill;
    tickRow.translatesAutoresizingMaskIntoConstraints = NO;
    [tickRow.widthAnchor constraintEqualToConstant:kSliderWidth].active = YES;

    NSMutableArray<NSView*>* rowViews = [@[titleLabel, slider, tickRow] mutableCopy];

    if (outValueDisplay) {
        NSTextField* vd = [NSTextField labelWithString:@""];
        vd.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize] weight:NSFontWeightSemibold];
        vd.alignment = NSTextAlignmentCenter;
        vd.translatesAutoresizingMaskIntoConstraints = NO;
        [vd.widthAnchor constraintEqualToConstant:kSliderWidth].active = YES;
        [rowViews addObject:vd];
        *outValueDisplay = vd;
    }

    NSStackView* row = [NSStackView stackViewWithViews:rowViews];
    row.orientation = NSUserInterfaceLayoutOrientationVertical;
    row.alignment = NSLayoutAttributeLeading;
    row.spacing = 2;
    row.translatesAutoresizingMaskIntoConstraints = NO;

    [stack addArrangedSubview:row];
    return slider;
}

- (void)_appendControlRowToStack:(NSStackView*)stack view:(NSView*)view
{
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [stack addArrangedSubview:view];
}

#pragma mark - Loading current values

- (void)_loadValuesFromDefaults
{
    self.densitySlider.integerValue    = [ToasterDefaults getNumberOfToasters];
    self.styleSlider.integerValue      = [ToasterDefaults getToasterStyle];
    self.speedSlider.integerValue      = [self _tickForFlightSpeed:[ToasterDefaults getFlightSpeed]];
    self.wingFlapSlider.integerValue   = [self _tickForWingFlapMS:[ToasterDefaults getWingFlapMS]];
    self.directionSlider.integerValue  = [ToasterDefaults getFlightDirection];
    self.ratioSlider.integerValue      = [ToasterDefaults getToastRatio];
    self.fastFreqSlider.integerValue   = [ToasterDefaults getFastFrequency];
    self.toastLevelSlider.integerValue = [self _tickForToastLevel:[ToasterDefaults getToastLevel]];
    self.cloudCoverSlider.integerValue = [ToasterDefaults getCloudCover];
    self.scaleDensityCheckbox.state    = [ToasterDefaults getScaleDensity] ? NSControlStateValueOn : NSControlStateValueOff;

    // Seed the live value displays so they match the initial slider state.
    self.styleValueLabel.stringValue     = [self _styleName:[ToasterDefaults getToasterStyle]];
    self.directionValueLabel.stringValue = [self _directionName:[ToasterDefaults getFlightDirection]];
}

#pragma mark - Slider <-> enum translations

- (NSInteger)_tickForFlightSpeed:(FlightSpeed)speed
{
    switch (speed) {
        case kSnailSpeed:     return 0;
        case kSlowSpeed:      return 1;
        case kMediumSpeed:    return 2;
        case kFastSpeed:      return 3;
        case kLightningSpeed: return 4;
    }
    return 2;
}

- (FlightSpeed)_flightSpeedForTick:(NSInteger)tick
{
    switch (tick) {
        case 0: return kSnailSpeed;
        case 1: return kSlowSpeed;
        case 2: return kMediumSpeed;
        case 3: return kFastSpeed;
        case 4: return kLightningSpeed;
        default: return kMediumSpeed;
    }
}

- (NSInteger)_tickForToastLevel:(ToastLevel)level
{
    switch (level) {
        case kLightToast:       return 0;
        case kGoldenBrownToast: return 1;
        case kDarkToast:        return 2;
        case kBurntToast:       return 3;
    }
    return 1;
}

- (ToastLevel)_toastLevelForTick:(NSInteger)tick
{
    switch (tick) {
        case 0:  return kLightToast;
        case 1:  return kGoldenBrownToast;
        case 2:  return kDarkToast;
        case 3:  return kBurntToast;
        default: return kGoldenBrownToast;
    }
}

#pragma mark - Actions

- (void)_densityChanged:(NSSlider*)s
{
    [ToasterDefaults setNumberOfToasters:(NSUInteger)s.integerValue];
}

- (void)_styleChanged:(NSSlider*)s
{
    ToasterStyle style = (ToasterStyle)s.integerValue;
    [ToasterDefaults setToasterStyle:style];
    self.styleValueLabel.stringValue = [self _styleName:style];
}

- (NSString*)_styleName:(ToasterStyle)style
{
    switch (style) {
        case kToasterStyleClassic:   return @"Classic";
        case kToasterStyleGreyscale: return @"Greyscale";
        case kToasterStyleInverted:  return @"Inverted";
    }
    return @"";
}

- (void)_speedChanged:(NSSlider*)s
{
    [ToasterDefaults setFlightSpeed:[self _flightSpeedForTick:s.integerValue]];
}

- (void)_wingFlapChanged:(NSSlider*)s
{
    [ToasterDefaults setWingFlapMS:[self _wingFlapMSForTick:s.integerValue]];
}

// Wing-flap slider: 9 ticks. Tick 0 = slowest (200 ms/frame); tick 8 = fastest (40 ms/frame).
- (NSInteger)_tickForWingFlapMS:(NSUInteger)ms
{
    NSInteger clamped = MIN((NSInteger)200, MAX((NSInteger)40, (NSInteger)ms));
    return (200 - clamped) / 20;
}

- (NSUInteger)_wingFlapMSForTick:(NSInteger)tick
{
    NSInteger ms = 200 - tick * 20;
    return (NSUInteger)MAX((NSInteger)40, MIN((NSInteger)200, ms));
}

- (void)_directionChanged:(NSSlider*)s
{
    FlightDirection d = (FlightDirection)s.integerValue;
    [ToasterDefaults setFlightDirection:d];
    self.directionValueLabel.stringValue = [self _directionName:d];
}

- (NSString*)_directionName:(FlightDirection)d
{
    switch (d) {
        case kFlightDirectionN:  return @"N";
        case kFlightDirectionNE: return @"NE";
        case kFlightDirectionE:  return @"E";
        case kFlightDirectionSE: return @"SE";
        case kFlightDirectionS:  return @"S";
        case kFlightDirectionSW: return @"SW";
        case kFlightDirectionW:  return @"W";
        case kFlightDirectionNW: return @"NW";
    }
    return @"";
}

- (void)_ratioChanged:(NSSlider*)s
{
    [ToasterDefaults setToastRatio:(NSUInteger)s.integerValue];
}

- (void)_fastFreqChanged:(NSSlider*)s
{
    [ToasterDefaults setFastFrequency:(NSUInteger)s.integerValue];
}

- (void)_toastLevelChanged:(NSSlider*)s
{
    [ToasterDefaults setToastLevel:[self _toastLevelForTick:s.integerValue]];
}

- (void)_cloudCoverChanged:(NSSlider*)s
{
    [ToasterDefaults setCloudCover:(NSUInteger)s.integerValue];
}

- (void)_scaleDensityChanged:(NSButton*)b
{
    [ToasterDefaults setScaleDensity:(b.state == NSControlStateValueOn)];
}

- (void)_donePressed:(id)sender
{
    if (self.delegate != nil) {
        [self.delegate flyingToasterPreferencesDidFinish:self];
        return;
    }
    [self.window.sheetParent endSheet:self.window returnCode:NSModalResponseOK];
}

@end
