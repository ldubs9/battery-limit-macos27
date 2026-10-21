#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const BLChargeLimitErrorDomain;

@interface BLChargeLimitController : NSObject

- (instancetype)init;

@property (nonatomic, readonly, getter=isAvailable) BOOL available;

- (BOOL)isSupported;
- (NSArray<NSNumber *> *)availableLimits:(NSError * _Nullable * _Nullable)error;
- (BOOL)readCurrentLimit:(NSInteger * _Nonnull)limit
                 enabled:(BOOL * _Nonnull)enabled
                   error:(NSError * _Nullable * _Nullable)error;
- (BOOL)setLimit:(NSInteger)limit error:(NSError * _Nullable * _Nullable)error;
- (BOOL)disable:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
