#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const BLSettingsSuiteName;
FOUNDATION_EXPORT NSString * const BLForceDischargeEnabledKey;
FOUNDATION_EXPORT NSString * const BLForceDischargeAdapterDisabledKey;

NSUserDefaults *BLSettings(void);

NS_ASSUME_NONNULL_END
