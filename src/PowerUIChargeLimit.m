#import "PowerUIChargeLimit.h"

#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>

NSString * const BLChargeLimitErrorDomain = @"com.ecc.BatteryLimit.PowerUI";

static const char * const kPowerUIPath =
    "/System/Library/PrivateFrameworks/PowerUI.framework/Versions/A/PowerUI";

typedef id (*BLInitWithClientNameFn)(id, SEL, id);
typedef BOOL (*BLBoolFn)(id, SEL);
typedef unsigned char (*BLGetLimitFn)(id, SEL, NSError **);
typedef unsigned long long (*BLGetEnabledFn)(id, SEL, NSError **);
typedef id (*BLAvailableLimitsFn)(id, SEL, NSError **);
typedef BOOL (*BLSetLimitFn)(id, SEL, unsigned char, NSError **);
typedef BOOL (*BLDisableFn)(id, SEL, NSError **);

@interface BLChargeLimitController ()
@property (nonatomic, strong, nullable) id client;
@property (nonatomic, assign, getter=isAvailable) BOOL available;
@end

@implementation BLChargeLimitController

- (instancetype)init {
    self = [super init];
    if (!self) {
        return nil;
    }

    void *handle = dlopen(kPowerUIPath, RTLD_NOW | RTLD_LOCAL);
    if (!handle) {
        return self;
    }

    Class clientClass = NSClassFromString(@"PowerUISmartChargeClient");
    if (!clientClass) {
        return self;
    }

    id instance = [clientClass alloc];
    SEL initSelector = sel_registerName("initWithClientName:");
    if (![instance respondsToSelector:initSelector]) {
        return self;
    }

    instance = ((BLInitWithClientNameFn)objc_msgSend)(
        instance,
        initSelector,
        @"ecc-battery-limit");
    if (!instance) {
        return self;
    }

    NSArray<NSString *> *requiredSelectors = @[
        @"isMCLSupported",
        @"availableChargeLimitsWithError:",
        @"getMCLLimitWithError:",
        @"isMCLCurrentlyEnabled:",
        @"setMCLLimit:error:",
        @"disableMCL:"
    ];
    for (NSString *selectorName in requiredSelectors) {
        if (![instance respondsToSelector:NSSelectorFromString(selectorName)]) {
            return self;
        }
    }

    self.client = instance;
    self.available = YES;
    return self;
}

- (NSError *)errorWithCode:(NSInteger)code description:(NSString *)description {
    return [NSError errorWithDomain:BLChargeLimitErrorDomain
                                code:code
                            userInfo:@{NSLocalizedDescriptionKey: description}];
}

- (BOOL)requireClient:(NSError **)error {
    if (!self.client || !self.available) {
        if (error) {
            *error = [self errorWithCode:1
                              description:@"PowerUI's native charge-limit service is unavailable on this Mac."];
        }
        return NO;
    }
    return YES;
}

- (BOOL)isSupported {
    if (![self requireClient:NULL]) {
        return NO;
    }
    return ((BLBoolFn)objc_msgSend)(self.client, sel_registerName("isMCLSupported"));
}

- (NSArray<NSNumber *> *)availableLimits:(NSError **)error {
    if (![self requireClient:error]) {
        return @[];
    }

    NSError *providerError = nil;
    id result = ((BLAvailableLimitsFn)objc_msgSend)(
        self.client,
        sel_registerName("availableChargeLimitsWithError:"),
        &providerError);
    if (providerError || ![result isKindOfClass:[NSArray class]]) {
        if (error) {
            *error = providerError ? providerError : [self errorWithCode:2
                                                          description:@"PowerUI returned no usable charge limits."];
        }
        return @[];
    }

    NSMutableArray<NSNumber *> *limits = [NSMutableArray array];
    for (id value in (NSArray *)result) {
        if ([value respondsToSelector:@selector(integerValue)]) {
            [limits addObject:@([value integerValue])];
        }
    }
    [limits sortUsingComparator:^NSComparisonResult(NSNumber *left, NSNumber *right) {
        return [left compare:right];
    }];
    return [limits copy];
}

- (BOOL)readCurrentLimit:(NSInteger *)limit
                 enabled:(BOOL *)enabled
                   error:(NSError **)error {
    if (!limit || !enabled || ![self requireClient:error]) {
        if (error && !*error) {
            *error = [self errorWithCode:3 description:@"Invalid status output arguments."];
        }
        return NO;
    }

    NSError *providerError = nil;
    unsigned char currentLimit = ((BLGetLimitFn)objc_msgSend)(
        self.client,
        sel_registerName("getMCLLimitWithError:"),
        &providerError);
    if (providerError) {
        if (error) {
            *error = providerError;
        }
        return NO;
    }

    providerError = nil;
    unsigned long long currentlyEnabled = ((BLGetEnabledFn)objc_msgSend)(
        self.client,
        sel_registerName("isMCLCurrentlyEnabled:"),
        &providerError);
    if (providerError) {
        if (error) {
            *error = providerError;
        }
        return NO;
    }

    *limit = (NSInteger)currentLimit;
    *enabled = currentlyEnabled != 0;
    return YES;
}

- (BOOL)setLimit:(NSInteger)limit error:(NSError **)error {
    if (limit < 80 || limit > 100) {
        if (error) {
            *error = [self errorWithCode:4
                              description:@"macOS 27's native charge-limit service accepts 80, 85, 90, 95, or 100 percent on this Mac."];
        }
        return NO;
    }
    if (limit == 100) {
        return [self disable:error];
    }
    if (![self requireClient:error]) {
        return NO;
    }

    NSError *limitsError = nil;
    NSArray<NSNumber *> *limits = [self availableLimits:&limitsError];
    if (limitsError) {
        if (error) {
            *error = limitsError;
        }
        return NO;
    }
    if (![limits containsObject:@(limit)]) {
        if (error) {
            *error = [self errorWithCode:5
                              description:[NSString stringWithFormat:@"PowerUI does not advertise a %@%% limit on this Mac.", @(limit)]];
        }
        return NO;
    }

    NSError *providerError = nil;
    BOOL success = ((BLSetLimitFn)objc_msgSend)(
        self.client,
        sel_registerName("setMCLLimit:error:"),
        (unsigned char)limit,
        &providerError);
    if (!success || providerError) {
        if (error) {
            *error = providerError ? providerError : [self errorWithCode:6
                                                                  description:@"PowerUI failed to set the charge limit."];
        }
        return NO;
    }
    return YES;
}

- (BOOL)disable:(NSError **)error {
    if (![self requireClient:error]) {
        return NO;
    }

    NSError *providerError = nil;
    BOOL success = ((BLDisableFn)objc_msgSend)(
        self.client,
        sel_registerName("disableMCL:"),
        &providerError);
    if (!success || providerError) {
        if (error) {
            *error = providerError ? providerError : [self errorWithCode:7
                                                                  description:@"PowerUI failed to disable the charge limit."];
        }
        return NO;
    }
    return YES;
}

@end
