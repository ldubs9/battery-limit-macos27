#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface BLAdapterController : NSObject

@property (nonatomic, copy, readonly, nullable) NSString *helperPath;

/// Reads CHIE. YES means wall-power/adapter control is enabled.
- (BOOL)readAdapterEnabled:(BOOL *)enabled error:(NSError **)error;

/// Writes CHIE. This changes whether the Mac may draw from the plugged-in adapter.
- (BOOL)setAdapterEnabled:(BOOL)enabled error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
