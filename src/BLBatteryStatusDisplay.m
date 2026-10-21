#import "BLBatteryStatusDisplay.h"

NSString * const BLStatusDisplayModeKey = @"statusDisplayMode";

static CGFloat BLClampFraction(NSInteger percentage) {
    NSInteger clamped = percentage < 0 ? 0 : (percentage > 100 ? 100 : percentage);
    NSInteger tenPercentLevel = (clamped / 10) * 10;
    return (CGFloat)tenPercentLevel / 100.0;
}

static void BLDrawChargingBolt(void) {
    NSBezierPath *bolt = [NSBezierPath bezierPath];
    // Hand-traced from the macOS Control Center battery-bolt-large reference.
    // The glyph is a solid template mark, not a contrasting badge.
    [bolt moveToPoint:NSMakePoint(11.0, 16.0)];
    [bolt lineToPoint:NSMakePoint(4.5, 10.0)];
    [bolt lineToPoint:NSMakePoint(9.0, 10.0)];
    [bolt lineToPoint:NSMakePoint(6.7, 2.1)];
    [bolt lineToPoint:NSMakePoint(13.5, 10.0)];
    [bolt lineToPoint:NSMakePoint(10.0, 10.0)];
    [bolt closePath];
    [[NSColor whiteColor] setFill];
    [bolt fill];
}

static void BLDrawPowerPlug(void) {
    // The reference uses Apple's solid plug silhouette: two short prongs,
    // a broad rounded body, a tapered lower shoulder, and a centered stem.
    NSBezierPath *leftProng = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(7.25, 14.0, 1.5, 2.5)
                                                                xRadius:0.35
                                                                yRadius:0.35];
    NSBezierPath *rightProng = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(10.75, 14.0, 1.5, 2.5)
                                                                 xRadius:0.35
                                                                 yRadius:0.35];
    NSBezierPath *body = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(5.25, 10.5, 8.0, 3.5)
                                                           xRadius:0.8
                                                           yRadius:0.8];
    NSBezierPath *shoulder = [NSBezierPath bezierPath];
    [shoulder moveToPoint:NSMakePoint(6.0, 10.7)];
    [shoulder lineToPoint:NSMakePoint(12.5, 10.7)];
    [shoulder curveToPoint:NSMakePoint(11.9, 9.1)
             controlPoint1:NSMakePoint(12.4, 10.1)
             controlPoint2:NSMakePoint(11.6, 8.0)];
    [shoulder lineToPoint:NSMakePoint(10.25, 7.0)];
    [shoulder lineToPoint:NSMakePoint(8.25, 7.0)];
    [shoulder curveToPoint:NSMakePoint(6.0, 10.7)
             controlPoint1:NSMakePoint(7.1, 8.0)
             controlPoint2:NSMakePoint(6.5, 9.1)];
    [shoulder closePath];
    NSBezierPath *stem = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(8.25, 2.5, 2.0, 4.8)
                                                           xRadius:0.45
                                                           yRadius:0.45];
    [[NSColor whiteColor] setFill];
    [leftProng fill];
    [rightProng fill];
    [body fill];
    [shoulder fill];
    [stem fill];
}

static void BLDrawDownArrow(void) {
    NSImage *arrow = [NSImage imageWithSystemSymbolName:@"arrow.down.left"
                                  accessibilityDescription:nil];
    NSImageSymbolConfiguration *size = [NSImageSymbolConfiguration configurationWithPointSize:14.0
                                                                                           weight:NSFontWeightRegular
                                                                                            scale:NSImageSymbolScaleMedium];
    NSImageSymbolConfiguration *palette = [NSImageSymbolConfiguration configurationWithPaletteColors:@[[NSColor whiteColor]]];
    arrow = [arrow imageWithSymbolConfiguration:[size configurationByApplyingConfiguration:palette]];
    [arrow drawInRect:NSMakeRect(2.0, 0.5, 14.0, 14.0)
             fromRect:NSZeroRect
            operation:NSCompositingOperationSourceOver
             fraction:1.0];
}

NSImage *BLCreateBatteryIcon(NSInteger percentage, BLBatteryPowerStage stage) {
    // The visible battery remains the same 16x9 body; the larger transparent
    // canvas matches Apple's taller stage glyphs without enlarging the battery.
    const NSSize size = NSMakeSize(22.0, 18.0);
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image lockFocus];

    NSGraphicsContext *context = [NSGraphicsContext currentContext];
    context.imageInterpolation = NSImageInterpolationHigh;

    NSColor *foreground = [NSColor whiteColor];
    [foreground setFill];
    [foreground setStroke];

    NSRect body = NSMakeRect(1.5, 4.5, 16.0, 9.0);
    NSBezierPath *outline = [NSBezierPath bezierPathWithRoundedRect:body xRadius:1.5 yRadius:1.5];
    outline.lineWidth = 1.35;
    [outline stroke];

    NSRect terminal = NSMakeRect(17.9, 7.2, 2.2, 3.6);
    NSBezierPath *terminalPath = [NSBezierPath bezierPathWithRoundedRect:terminal xRadius:0.8 yRadius:0.8];
    [terminalPath fill];

    CGFloat fillFraction = BLClampFraction(percentage);
    CGFloat innerWidth = 12.5 * fillFraction;
    if (innerWidth > 0.0) {
        NSRect fillRect = NSMakeRect(3.25, 6.25, innerWidth, 5.5);
        NSBezierPath *fill = [NSBezierPath bezierPathWithRoundedRect:fillRect xRadius:0.75 yRadius:0.75];
        [fill fill];
    }

    switch (stage) {
        case BLBatteryPowerStageCharging:
            BLDrawChargingBolt();
            break;
        case BLBatteryPowerStageOnPowerNotCharging:
            BLDrawPowerPlug();
            break;
        case BLBatteryPowerStageForceDischarging:
            BLDrawDownArrow();
            break;
        case BLBatteryPowerStageUnknown:
        case BLBatteryPowerStageDischarging:
            break;
    }

    [image unlockFocus];
    image.template = YES;
    NSString *stageDescription = BLBatteryStageAccessibilityName(stage);
    image.accessibilityDescription = [NSString stringWithFormat:@"%@ at %ld percent", stageDescription, (long)percentage];
    return image;
}

NSImage *BLCreateStatusItemBatteryIcon(NSInteger percentage, BLBatteryPowerStage stage) {
    NSImage *base = BLCreateBatteryIcon(percentage, stage);
    // AppKit's default image/title separation is small in a status button.
    // Add 2 pt of transparent trailing space, approximately 20% more optical
    // separation without changing the icon's physical size.
    const CGFloat trailingPadding = 2.0;
    NSImage *padded = [[NSImage alloc] initWithSize:NSMakeSize(base.size.width + trailingPadding,
                                                                base.size.height)];
    [padded lockFocus];
    [base drawAtPoint:NSZeroPoint
             fromRect:NSZeroRect
            operation:NSCompositingOperationSourceOver
             fraction:1.0];
    [padded unlockFocus];
    padded.template = base.template;
    padded.accessibilityDescription = base.accessibilityDescription;
    return padded;
}

NSString *BLBatteryStageShortName(BLBatteryPowerStage stage) {
    switch (stage) {
        case BLBatteryPowerStageCharging:
            return @"Charging";
        case BLBatteryPowerStageOnPowerNotCharging:
            return @"On power";
        case BLBatteryPowerStageForceDischarging:
            return @"Discharging";
        case BLBatteryPowerStageDischarging:
            return @"On battery";
        case BLBatteryPowerStageUnknown:
            return @"Unavailable";
    }
}

NSString *BLBatteryStageAccessibilityName(BLBatteryPowerStage stage) {
    switch (stage) {
        case BLBatteryPowerStageCharging:
            return @"charging";
        case BLBatteryPowerStageOnPowerNotCharging:
            return @"connected to power and not charging";
        case BLBatteryPowerStageForceDischarging:
            return @"force discharging while connected to power";
        case BLBatteryPowerStageDischarging:
            return @"discharging on battery power";
        case BLBatteryPowerStageUnknown:
            return @"battery status unavailable";
    }
}

NSString *BLStatusDisplayModeName(BLStatusDisplayMode mode) {
    switch (mode) {
        case BLStatusDisplayModeIconOnly:
            return @"Icon only";
        case BLStatusDisplayModeIconAndPercentage:
            return @"Icon + %";
        case BLStatusDisplayModePercentageOnly:
            return @"% only";
        case BLStatusDisplayModeTextOnly:
            return @"Text only";
    }
}
