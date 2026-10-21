#import "BLBatteryStatusDisplay.h"

NSString * const BLStatusDisplayModeKey = @"statusDisplayMode";

static CGFloat BLClampFraction(NSInteger percentage) {
    NSInteger clamped = percentage < 0 ? 0 : (percentage > 100 ? 100 : percentage);
    NSInteger tenPercentLevel = (clamped / 10) * 10;
    return (CGFloat)tenPercentLevel / 100.0;
}

static void BLClearPath(NSBezierPath *path) {
    NSGraphicsContext *context = [NSGraphicsContext currentContext];
    NSCompositingOperation previousOperation = context.compositingOperation;
    context.compositingOperation = NSCompositingOperationClear;
    [path fill];
    context.compositingOperation = previousOperation;
}

static void BLDrawChargingBolt(void) {
    NSBezierPath *bolt = [NSBezierPath bezierPath];
    [bolt moveToPoint:NSMakePoint(10.4, 5.0)];
    [bolt lineToPoint:NSMakePoint(7.5, 8.0)];
    [bolt lineToPoint:NSMakePoint(9.4, 8.0)];
    [bolt lineToPoint:NSMakePoint(8.3, 11.0)];
    [bolt lineToPoint:NSMakePoint(12.6, 7.1)];
    [bolt lineToPoint:NSMakePoint(10.7, 7.1)];
    [bolt closePath];
    BLClearPath(bolt);
}

static void BLDrawPowerMarker(void) {
    NSBezierPath *horizontal = [NSBezierPath bezierPathWithRect:NSMakeRect(7.9, 7.5, 4.2, 1.2)];
    NSBezierPath *vertical = [NSBezierPath bezierPathWithRect:NSMakeRect(9.4, 6.0, 1.2, 4.2)];
    BLClearPath(horizontal);
    BLClearPath(vertical);
}

static void BLDrawDownArrow(void) {
    NSBezierPath *arrow = [NSBezierPath bezierPath];
    [arrow moveToPoint:NSMakePoint(9.1, 3.0)];
    [arrow lineToPoint:NSMakePoint(10.9, 3.0)];
    [arrow lineToPoint:NSMakePoint(10.9, 1.8)];
    [arrow lineToPoint:NSMakePoint(12.2, 1.8)];
    [arrow lineToPoint:NSMakePoint(10.0, 0.2)];
    [arrow lineToPoint:NSMakePoint(7.8, 1.8)];
    [arrow lineToPoint:NSMakePoint(9.1, 1.8)];
    [arrow closePath];
    [arrow fill];
}

NSImage *BLCreateBatteryIcon(NSInteger percentage, BLBatteryPowerStage stage) {
    const NSSize size = NSMakeSize(21.0, 15.0);
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image lockFocus];

    NSGraphicsContext *context = [NSGraphicsContext currentContext];
    context.imageInterpolation = NSImageInterpolationHigh;

    NSColor *foreground = [NSColor whiteColor];
    [foreground setFill];
    [foreground setStroke];

    NSRect body = NSMakeRect(1.0, 4.0, 16.0, 9.0);
    NSBezierPath *outline = [NSBezierPath bezierPathWithRoundedRect:body xRadius:1.5 yRadius:1.5];
    outline.lineWidth = 1.35;
    [outline stroke];

    NSRect terminal = NSMakeRect(17.4, 6.7, 2.2, 3.6);
    NSBezierPath *terminalPath = [NSBezierPath bezierPathWithRoundedRect:terminal xRadius:0.8 yRadius:0.8];
    [terminalPath fill];

    CGFloat fillFraction = BLClampFraction(percentage);
    CGFloat innerWidth = 12.5 * fillFraction;
    if (innerWidth > 0.0) {
        NSRect fillRect = NSMakeRect(2.75, 5.75, innerWidth, 5.5);
        NSBezierPath *fill = [NSBezierPath bezierPathWithRoundedRect:fillRect xRadius:0.75 yRadius:0.75];
        [fill fill];
    }

    switch (stage) {
        case BLBatteryPowerStageCharging:
            BLDrawChargingBolt();
            break;
        case BLBatteryPowerStageOnPowerNotCharging:
            BLDrawPowerMarker();
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
    image.accessibilityDescription = [NSString stringWithFormat:@"Battery at %ld percent", (long)percentage];
    return image;
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
