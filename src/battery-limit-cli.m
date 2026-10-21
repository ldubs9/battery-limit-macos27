#import <Foundation/Foundation.h>

#import "BLAdapterController.h"
#import "BLBatteryState.h"
#import "BLSettings.h"
#import "PowerUIChargeLimit.h"

static void printUsage(void) {
    printf("Battery Limit for macOS 27\n\n");
    printf("Usage:\n");
    printf("  battery-limit status\n");
    printf("  battery-limit limits\n");
    printf("  battery-limit set 80|85|90|95\n");
    printf("  battery-limit disable\n");
    printf("  battery-limit force-discharge status\n");
    printf("  battery-limit force-discharge enable|disable\n");
    printf("\nThe charge limit uses macOS's native PowerUI service.\n");
    printf("Force discharge uses the CHIE SMC adapter-control key and requires install.sh's helper.\n");
}

static void printError(NSError *error) {
    const char *message = error.localizedDescription.UTF8String;
    fprintf(stderr, "Error: %s\n", message ? message : "unknown error");
}

static NSString *joinedLimits(NSArray<NSNumber *> *limits) {
    NSMutableArray<NSString *> *values = [NSMutableArray arrayWithCapacity:limits.count];
    for (NSNumber *limit in limits) {
        [values addObject:[NSString stringWithFormat:@"%@%%", limit]];
    }
    return [values componentsJoinedByString:@", "];
}

static int readLimit(BLChargeLimitController *controller,
                     NSInteger *limit,
                     BOOL *enabled,
                     NSArray<NSNumber *> **available) {
    NSError *error = nil;
    NSArray<NSNumber *> *limits = [controller availableLimits:&error];
    if (error) {
        printError(error);
        return 1;
    }
    if (![controller readCurrentLimit:limit enabled:enabled error:&error]) {
        printError(error);
        return 1;
    }
    if (available) {
        *available = limits;
    }
    return 0;
}

static int printStatus(BLChargeLimitController *controller) {
    NSError *error = nil;
    NSArray<NSNumber *> *limits = [controller availableLimits:&error];
    if (error) {
        printError(error);
        return 1;
    }

    NSInteger currentLimit = 0;
    BOOL enabled = NO;
    if (![controller readCurrentLimit:&currentLimit enabled:&enabled error:&error]) {
        printError(error);
        return 1;
    }

    NSOperatingSystemVersion version = NSProcessInfo.processInfo.operatingSystemVersion;
    printf("Battery Limit status\n");
    printf("macOS: %ld.%ld.%ld\n", (long)version.majorVersion, (long)version.minorVersion, (long)version.patchVersion);
    printf("PowerUI supported: %s\n", controller.isSupported ? "yes" : "no");
    printf("Available limits: %s\n", joinedLimits(limits).UTF8String);
    if (enabled) {
        printf("Current limit: %ld%% (enabled)\n", (long)currentLimit);
    } else {
        printf("Current limit: disabled (100%%)\n");
    }

    BLBatteryState *battery = [BLBatteryState read:NULL];
    if (battery) {
        printf("Battery: %ld%%, %s, %s\n",
               (long)battery.percentage,
               battery.isExternalConnected ? "adapter connected" : "running on battery",
               battery.isCharging ? "charging" : "not charging");
    }
    BOOL forceEnabled = [BLSettings() boolForKey:BLForceDischargeEnabledKey];
    printf("Force discharge setting: %s\n", forceEnabled ? "enabled" : "disabled");

    BLAdapterController *adapter = [[BLAdapterController alloc] init];
    BOOL adapterEnabled = NO;
    if ([adapter readAdapterEnabled:&adapterEnabled error:&error]) {
        printf("CHIE adapter control: %s (%s)\n",
               adapterEnabled ? "enabled" : "disabled",
               adapter.helperPath.UTF8String ? adapter.helperPath.UTF8String : "helper");
    } else {
        printf("CHIE adapter control: unavailable (%s)\n",
               error.localizedDescription.UTF8String ? error.localizedDescription.UTF8String : "no helper");
    }
    return 0;
}

static int applyForceDischargeOnce(BLChargeLimitController *controller) {
    NSInteger limit = 0;
    BOOL limitEnabled = NO;
    if (readLimit(controller, &limit, &limitEnabled, NULL) != 0) {
        return 1;
    }
    if (!limitEnabled) {
        fprintf(stderr, "Set a native charge limit before enabling force discharge.\n");
        return 1;
    }

    BLBatteryState *battery = [BLBatteryState read:NULL];
    if (!battery || battery.percentage <= limit) {
        return 0;
    }

    BLAdapterController *adapter = [[BLAdapterController alloc] init];
    BOOL adapterEnabled = NO;
    NSError *error = nil;
    if (![adapter readAdapterEnabled:&adapterEnabled error:&error]) {
        printError(error);
        return 1;
    }
    if (adapterEnabled && ![adapter setAdapterEnabled:NO error:&error]) {
        printError(error);
        return 1;
    }
    [BLSettings() setBool:YES forKey:BLForceDischargeAdapterDisabledKey];
    [BLSettings() synchronize];
    return 0;
}

static int handleForceDischarge(BLChargeLimitController *controller,
                                NSString *action) {
    NSUserDefaults *settings = BLSettings();
    BLAdapterController *adapter = [[BLAdapterController alloc] init];

    if ([action isEqualToString:@"status"]) {
        BOOL enabled = [settings boolForKey:BLForceDischargeEnabledKey];
        printf("Force discharge setting: %s\n", enabled ? "enabled" : "disabled");
        BOOL adapterEnabled = NO;
        NSError *error = nil;
        if ([adapter readAdapterEnabled:&adapterEnabled error:&error]) {
            printf("CHIE adapter: %s\n", adapterEnabled ? "enabled" : "disabled");
        } else {
            printf("CHIE adapter: unavailable (%s)\n", error.localizedDescription.UTF8String ? error.localizedDescription.UTF8String : "unknown error");
        }
        return 0;
    }

    if ([action isEqualToString:@"enable"]) {
        NSInteger limit = 0;
        BOOL limitEnabled = NO;
        if (readLimit(controller, &limit, &limitEnabled, NULL) != 0) {
            return 1;
        }
        if (!limitEnabled) {
            fprintf(stderr, "Set a native charge limit before enabling force discharge.\n");
            return 1;
        }
        [settings setBool:YES forKey:BLForceDischargeEnabledKey];
        [settings synchronize];
        if (applyForceDischargeOnce(controller) != 0) {
            return 1;
        }
        printf("Force discharge enabled; Battery Limit will cut adapter power above %ld%% and restore it at or below that limit.\n", (long)limit);
        return 0;
    }

    if ([action isEqualToString:@"disable"]) {
        [settings setBool:NO forKey:BLForceDischargeEnabledKey];
        [settings setBool:NO forKey:BLForceDischargeAdapterDisabledKey];
        [settings synchronize];
        NSError *error = nil;
        if (adapter.helperPath && ![adapter setAdapterEnabled:YES error:&error]) {
            printError(error);
            return 1;
        }
        printf("Force discharge disabled; adapter control restored.\n");
        return 0;
    }

    fprintf(stderr, "Usage: battery-limit force-discharge status|enable|disable\n");
    return 2;
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        if (argc < 2 || strcmp(argv[1], "help") == 0 || strcmp(argv[1], "--help") == 0) {
            printUsage();
            return 0;
        }

        BLChargeLimitController *controller = [[BLChargeLimitController alloc] init];
        NSString *command = [NSString stringWithUTF8String:argv[1]];

        if ([command isEqualToString:@"status"]) {
            return printStatus(controller);
        }

        if ([command isEqualToString:@"limits"]) {
            NSError *error = nil;
            NSArray<NSNumber *> *limits = [controller availableLimits:&error];
            if (error) {
                printError(error);
                return 1;
            }
            printf("%s\n", joinedLimits(limits).UTF8String);
            return 0;
        }

        if ([command isEqualToString:@"disable"]) {
            NSError *error = nil;
            if (![controller disable:&error]) {
                printError(error);
                return 1;
            }
            printf("Charge limit disabled; macOS may charge to 100%%.\n");
            return 0;
        }

        if ([command isEqualToString:@"set"]) {
            if (argc != 3) {
                fprintf(stderr, "Usage: battery-limit set 80|85|90|95\n");
                return 2;
            }
            NSInteger limit = [[NSString stringWithUTF8String:argv[2]] integerValue];
            NSError *error = nil;
            if (![controller setLimit:limit error:&error]) {
                printError(error);
                return 1;
            }
            printf("Charge limit set to %ld%%.\n", (long)limit);
            return 0;
        }

        if ([command isEqualToString:@"force-discharge"]) {
            if (argc != 3) {
                fprintf(stderr, "Usage: battery-limit force-discharge status|enable|disable\n");
                return 2;
            }
            return handleForceDischarge(controller, [NSString stringWithUTF8String:argv[2]]);
        }

        fprintf(stderr, "Unknown command: %s\n\n", argv[1]);
        printUsage();
        return 2;
    }
}
