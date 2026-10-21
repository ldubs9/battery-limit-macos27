#import "BLBatteryState.h"

#import <IOKit/ps/IOPowerSources.h>
#import <IOKit/ps/IOPSKeys.h>
#import <math.h>

static NSString * const BLBatteryErrorDomain = @"com.ecc.BatteryLimit.Battery";

@interface BLBatteryState ()
@property (nonatomic, assign, readwrite) NSInteger percentage;
@property (nonatomic, assign, readwrite, getter=isExternalConnected) BOOL externalConnected;
@property (nonatomic, assign, readwrite, getter=isCharging) BOOL charging;
@end

@implementation BLBatteryState

- (instancetype)initWithPercentage:(NSInteger)percentage
                 externalConnected:(BOOL)externalConnected
                           charging:(BOOL)charging {
    self = [super init];
    if (!self) {
        return nil;
    }
    _percentage = percentage < 0 ? 0 : (percentage > 100 ? 100 : percentage);
    _externalConnected = externalConnected;
    _charging = charging;
    return self;
}

+ (instancetype)read:(NSError **)error {
    CFTypeRef powerSourcesInfo = IOPSCopyPowerSourcesInfo();
    if (!powerSourcesInfo) {
        if (error) {
            *error = [NSError errorWithDomain:BLBatteryErrorDomain
                                          code:1
                                      userInfo:@{NSLocalizedDescriptionKey: @"macOS did not return power-source information."}];
        }
        return nil;
    }

    CFArrayRef powerSourcesList = IOPSCopyPowerSourcesList(powerSourcesInfo);
    if (!powerSourcesList || CFArrayGetCount(powerSourcesList) == 0) {
        if (powerSourcesList) {
            CFRelease(powerSourcesList);
        }
        CFRelease(powerSourcesInfo);
        if (error) {
            *error = [NSError errorWithDomain:BLBatteryErrorDomain
                                          code:2
                                      userInfo:@{NSLocalizedDescriptionKey: @"No battery power source was found."}];
        }
        return nil;
    }

    NSDictionary *battery = nil;
    for (CFIndex index = 0; index < CFArrayGetCount(powerSourcesList); index++) {
        CFTypeRef source = CFArrayGetValueAtIndex(powerSourcesList, index);
        CFDictionaryRef description = IOPSGetPowerSourceDescription(powerSourcesInfo, source);
        if (!description) {
            continue;
        }
        NSDictionary *candidate = (__bridge NSDictionary *)description;
        NSString *type = candidate[@kIOPSTypeKey];
        if ([type isEqualToString:@kIOPSInternalType]) {
            battery = candidate;
            break;
        }
        if (!battery) {
            battery = candidate;
        }
    }

    NSDictionary *description = battery;
    NSNumber *currentCapacity = description[@kIOPSCurrentCapacityKey];
    NSNumber *maximumCapacity = description[@kIOPSMaxCapacityKey];
    NSString *powerSourceState = description[@kIOPSPowerSourceStateKey];
    NSNumber *charging = description[@kIOPSIsChargingKey];

    if (!currentCapacity || !maximumCapacity || maximumCapacity.integerValue <= 0) {
        CFRelease(powerSourcesList);
        CFRelease(powerSourcesInfo);
        if (error) {
            *error = [NSError errorWithDomain:BLBatteryErrorDomain
                                          code:3
                                      userInfo:@{NSLocalizedDescriptionKey: @"Battery capacity was not available."}];
        }
        return nil;
    }

    NSInteger percentage = (NSInteger)llround((double)currentCapacity.integerValue * 100.0 /
                                              (double)maximumCapacity.integerValue);
    BLBatteryState *state = [[self alloc] initWithPercentage:percentage
                                          externalConnected:[powerSourceState isEqualToString:@kIOPSACPowerValue]
                                                    charging:charging.boolValue];
    CFRelease(powerSourcesList);
    CFRelease(powerSourcesInfo);
    return state;
}

@end
