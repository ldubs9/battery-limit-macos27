#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BLBatteryState : NSObject

@property (nonatomic, assign, readonly) NSInteger percentage;
@property (nonatomic, assign, readonly, getter=isExternalConnected) BOOL externalConnected;
@property (nonatomic, assign, readonly, getter=isCharging) BOOL charging;

- (instancetype)initWithPercentage:(NSInteger)percentage
                 externalConnected:(BOOL)externalConnected
                           charging:(BOOL)charging;

+ (nullable instancetype)read:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
