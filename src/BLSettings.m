#import "BLSettings.h"

NSString * const BLSettingsSuiteName = @"com.ecc.BatteryLimit.Settings";
NSString * const BLForceDischargeEnabledKey = @"forceDischargeEnabled";

NSUserDefaults *BLSettings(void) {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:BLSettingsSuiteName];
    return defaults ? defaults : [NSUserDefaults standardUserDefaults];
}
