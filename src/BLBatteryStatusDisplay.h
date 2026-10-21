#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, BLBatteryPowerStage) {
    BLBatteryPowerStageUnknown = 0,
    BLBatteryPowerStageDischarging,
    BLBatteryPowerStageCharging,
    BLBatteryPowerStageOnPowerNotCharging,
    BLBatteryPowerStageForceDischarging,
};

typedef NS_ENUM(NSInteger, BLStatusDisplayMode) {
    BLStatusDisplayModeIconOnly = 0,
    BLStatusDisplayModeIconAndPercentage,
    BLStatusDisplayModePercentageOnly,
    BLStatusDisplayModeTextOnly,
};

FOUNDATION_EXPORT NSString * const BLStatusDisplayModeKey;

/// Creates a monochrome horizontal battery icon. The fill is quantized to 10%.
FOUNDATION_EXPORT NSImage *BLCreateBatteryIcon(NSInteger percentage,
                                                BLBatteryPowerStage stage);

/// Status-item variant with a 20% optical increase to the icon/title gap.
FOUNDATION_EXPORT NSImage *BLCreateStatusItemBatteryIcon(NSInteger percentage,
                                                         BLBatteryPowerStage stage);

FOUNDATION_EXPORT NSString *BLBatteryStageShortName(BLBatteryPowerStage stage);
FOUNDATION_EXPORT NSString *BLBatteryStageAccessibilityName(BLBatteryPowerStage stage);
FOUNDATION_EXPORT NSString *BLStatusDisplayModeName(BLStatusDisplayMode mode);

NS_ASSUME_NONNULL_END
