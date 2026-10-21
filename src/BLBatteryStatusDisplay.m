#import "BLBatteryStatusDisplay.h"

NSString * const BLStatusDisplayModeKey = @"statusDisplayMode";

static CGFloat BLClampFraction(NSInteger percentage) {
    NSInteger clamped = percentage < 0 ? 0 : (percentage > 100 ? 100 : percentage);
    NSInteger tenPercentLevel = (clamped / 10) * 10;
    return (CGFloat)tenPercentLevel / 100.0;
}

static void BLDrawChargingBolt(void) {
    NSBezierPath *bolt = [NSBezierPath bezierPath];
    // This is a compact hand-traced analogue of macOS Control Center's
    // battery-bolt-large glyph: asymmetric, narrow, and intentionally taller
    // than the battery body while remaining centered on it.
    [bolt moveToPoint:NSMakePoint(11.0, 14.5)];
    [bolt lineToPoint:NSMakePoint(4.5, 8.5)];
    [bolt lineToPoint:NSMakePoint(9.0, 8.5)];
    [bolt lineToPoint:NSMakePoint(6.7, 0.6)];
    [bolt lineToPoint:NSMakePoint(13.5, 8.5)];
    [bolt lineToPoint:NSMakePoint(10.0, 8.5)];
    [bolt closePath];
    [[NSColor controlBackgroundColor] setFill];
    [bolt fill];
    [[NSColor labelColor] setStroke];
    bolt.lineWidth = 0.3;
    [bolt stroke];
}

static void BLDrawDownArrow(void) {
    NSBezierPath *arrow = [NSBezierPath bezierPath];
    // Apple-style arrow.down proportions: a narrow shaft and broad, centered
    // chevron, enlarged enough to remain legible over the filled battery.
    [arrow moveToPoint:NSMakePoint(8.1, 11.0)];
    [arrow lineToPoint:NSMakePoint(9.9, 11.0)];
    [arrow lineToPoint:NSMakePoint(9.9, 6.2)];
    [arrow lineToPoint:NSMakePoint(11.7, 6.2)];
    [arrow lineToPoint:NSMakePoint(9.0, 3.3)];
    [arrow lineToPoint:NSMakePoint(6.3, 6.2)];
    [arrow lineToPoint:NSMakePoint(8.1, 6.2)];
    [arrow closePath];
    [[NSColor controlBackgroundColor] setFill];
    [arrow fill];
    [[NSColor labelColor] setStroke];
    arrow.lineWidth = 0.3;
    [arrow stroke];
}

NSImage *BLCreateBatteryIcon(NSInteger percentage, BLBatteryPowerStage stage) {
    const NSSize size = NSMakeSize(21.0, 15.0);
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image lockFocus];

    NSGraphicsContext *context = [NSGraphicsContext currentContext];
    context.imageInterpolation = NSImageInterpolationHigh;

    BOOL explicitStageColors = stage == BLBatteryPowerStageCharging
        || stage == BLBatteryPowerStageForceDischarging;
    NSColor *foreground = explicitStageColors ? [NSColor labelColor] : [NSColor whiteColor];
    [foreground setFill];
    [foreground setStroke];

    NSRect body = NSMakeRect(1.0, 3.0, 16.0, 9.0);
    NSBezierPath *outline = [NSBezierPath bezierPathWithRoundedRect:body xRadius:1.5 yRadius:1.5];
    outline.lineWidth = 1.35;
    [outline stroke];

    NSRect terminal = NSMakeRect(17.4, 5.7, 2.2, 3.6);
    NSBezierPath *terminalPath = [NSBezierPath bezierPathWithRoundedRect:terminal xRadius:0.8 yRadius:0.8];
    [terminalPath fill];

    CGFloat fillFraction = BLClampFraction(percentage);
    CGFloat innerWidth = 12.5 * fillFraction;
    if (innerWidth > 0.0) {
        NSRect fillRect = NSMakeRect(2.75, 4.75, innerWidth, 5.5);
        NSBezierPath *fill = [NSBezierPath bezierPathWithRoundedRect:fillRect xRadius:0.75 yRadius:0.75];
        [fill fill];
    }

    switch (stage) {
        case BLBatteryPowerStageCharging:
            BLDrawChargingBolt();
            break;
        case BLBatteryPowerStageOnPowerNotCharging:
            // Apple keeps the connected/not-charging state in the status text;
            // do not add a competing overlay to the user's battery artwork.
            break;
        case BLBatteryPowerStageForceDischarging:
            BLDrawDownArrow();
            break;
        case BLBatteryPowerStageUnknown:
        case BLBatteryPowerStageDischarging:
            break;
    }

    [image unlockFocus];
    image.template = !explicitStageColors;
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
