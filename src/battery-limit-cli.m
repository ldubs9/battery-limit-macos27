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
    printf("  battery-limit set 60|65|70|75|80|85|90|95\n");
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

    NSInteger nativeLimit = 0;
    BOOL nativeEnabled = NO;
    if (![controller readCurrentLimit:&nativeLimit enabled:&nativeEnabled error:&error]) {
        printError(error);
        return 1;
    }

    NSInteger lowLimit = [BLSettings() integerForKey:BLLowChargeLimitKey];
    *limit = (lowLimit >= 60 && lowLimit <= 75 && lowLimit % 5 == 0) ? lowLimit : nativeLimit;
    *enabled = nativeEnabled;
    if (available) {
        *available = limits;
    }
    return 0;
}

static NSInteger validLowLimit(void) {
    NSInteger lowLimit = [BLSettings() integerForKey:BLLowChargeLimitKey];
    return (lowLimit >= 60 && lowLimit <= 75 && lowLimit % 5 == 0) ? lowLimit : 0;
}

static int printStatus(BLChargeLimitController *controller) {
    NSError *error = nil;
    NSArray<NSNumber *> *limits = [controller availableLimits:&error];
    if (error) {
        printError(error);
        return 1;
    }

    NSInteger nativeLimit = 0;
    BOOL enabled = NO;
    if (![controller readCurrentLimit:&nativeLimit enabled:&enabled error:&error]) {
        printError(error);
        return 1;
    }
    NSInteger lowLimit = validLowLimit();
    NSInteger currentLimit = lowLimit > 0 ? lowLimit : nativeLimit;
    NSMutableArray<NSNumber *> *reportedLimits = [NSMutableArray arrayWithArray:@[@60, @65, @70, @75]];
    [reportedLimits addObjectsFromArray:limits];

    NSOperatingSystemVersion version = NSProcessInfo.processInfo.operatingSystemVersion;
    printf("Battery Limit status\n");
    printf("macOS: %ld.%ld.%ld\n", (long)version.majorVersion, (long)version.minorVersion, (long)version.patchVersion);
    printf("PowerUI supported: %s\n", controller.isSupported ? "yes" : "no");
    printf("Available limits: %s\n", joinedLimits(reportedLimits).UTF8String);
    if (enabled && lowLimit > 0) {
        printf("Current limit: %ld%% (adapter mode; native safety limit %ld%%)\n", (long)currentLimit, (long)nativeLimit);
    } else if (enabled) {
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
    if (lowLimit > 0) {
        printf("Low-limit adapter mode: enabled (%ld%%)\n", (long)lowLimit);
    }

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

static int applyAdapterLimitOnce(BLChargeLimitController *controller) {
    NSInteger limit = 0;
    BOOL limitEnabled = NO;
    if (readLimit(controller, &limit, &limitEnabled, NULL) != 0) {
        return 1;
    }
    if (!limitEnabled) {
        fprintf(stderr, "Set a native charge limit before enabling adapter enforcement.\n");
        return 1;
    }

    BLBatteryState *battery = [BLBatteryState read:NULL];
    if (!battery) {
        return 0;
    }

    BLAdapterController *adapter = [[BLAdapterController alloc] init];
    if (!adapter.helperPath) {
        fprintf(stderr, "Limits below 80%% and force discharge require a CHIE SMC helper.\n");
        return 1;
    }

    BOOL adapterEnabled = NO;
    NSError *error = nil;
    if (![adapter readAdapterEnabled:&adapterEnabled error:&error]) {
        printError(error);
        return 1;
    }

    NSUserDefaults *settings = BLSettings();
    BOOL adapterDisabledByUs = [settings boolForKey:BLForceDischargeAdapterDisabledKey];
    if (battery.percentage > limit) {
        if (adapterEnabled && ![adapter setAdapterEnabled:NO error:&error]) {
            printError(error);
            return 1;
        }
        if (adapterEnabled || adapterDisabledByUs) {
            [settings setBool:YES forKey:BLForceDischargeAdapterDisabledKey];
            [settings synchronize];
        }
    } else if (adapterDisabledByUs && !adapterEnabled) {
        if (![adapter setAdapterEnabled:YES error:&error]) {
            printError(error);
            return 1;
        }
        [settings setBool:NO forKey:BLForceDischargeAdapterDisabledKey];
        [settings synchronize];
    }
    return 0;
}

static int restoreOwnedAdapter(BLAdapterController *adapter) {
    NSUserDefaults *settings = BLSettings();
    if (![settings boolForKey:BLForceDischargeAdapterDisabledKey]) {
        return 0;
    }
    if (!adapter.helperPath) {
        fprintf(stderr, "Cannot restore adapter control: CHIE SMC helper is unavailable.\n");
        return 1;
    }
    NSError *error = nil;
    if (![adapter setAdapterEnabled:YES error:&error]) {
        printError(error);
        return 1;
    }
    [settings setBool:NO forKey:BLForceDischargeAdapterDisabledKey];
    [settings synchronize];
    return 0;
}

static int handleForceDischarge(BLChargeLimitController *controller,
                                NSString *action) {
    NSUserDefaults *settings = BLSettings();
    BLAdapterController *adapter = [[BLAdapterController alloc] init];

    if ([action isEqualToString:@"status"]) {
        BOOL enabled = [settings boolForKey:BLForceDischargeEnabledKey];
        printf("Force discharge setting: %s\n", enabled ? "enabled" : "disabled");
        NSInteger lowLimit = validLowLimit();
        if (lowLimit > 0) {
            printf("Low-limit adapter mode: enabled (%ld%%)\n", (long)lowLimit);
        }
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
        if (applyAdapterLimitOnce(controller) != 0) {
            return 1;
        }
        if (validLowLimit() > 0) {
            printf("Force discharge remains required by the %ld%% low-limit adapter mode.\n", (long)limit);
        } else {
            printf("Force discharge enabled; Battery Limit will cut adapter power above %ld%% and restore it at or below that limit.\n", (long)limit);
        }
        return 0;
    }

    if ([action isEqualToString:@"disable"]) {
        [settings setBool:NO forKey:BLForceDischargeEnabledKey];
        [settings synchronize];
        if (validLowLimit() > 0) {
            if (applyAdapterLimitOnce(controller) != 0) {
                return 1;
            }
            printf("Optional force discharge disabled; the selected low limit remains enforced.\n");
        } else {
            if (restoreOwnedAdapter(adapter) != 0) {
                return 1;
            }
            printf("Force discharge disabled; adapter control restored.\n");
        }
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
            NSMutableArray<NSNumber *> *reportedLimits = [NSMutableArray arrayWithArray:@[@60, @65, @70, @75]];
            [reportedLimits addObjectsFromArray:limits];
            printf("%s\n", joinedLimits(reportedLimits).UTF8String);
            return 0;
        }

        if ([command isEqualToString:@"disable"]) {
            NSError *error = nil;
            if (![controller disable:&error]) {
                printError(error);
                return 1;
            }
            [BLSettings() setInteger:0 forKey:BLLowChargeLimitKey];
            [BLSettings() synchronize];
            if (restoreOwnedAdapter([[BLAdapterController alloc] init]) != 0) {
                return 1;
            }
            printf("Charge limit disabled; macOS may charge to 100%%.\n");
            return 0;
        }

        if ([command isEqualToString:@"set"]) {
            if (argc != 3) {
                fprintf(stderr, "Usage: battery-limit set 60|65|70|75|80|85|90|95\n");
                return 2;
            }
            NSInteger limit = [[NSString stringWithUTF8String:argv[2]] integerValue];
            NSError *error = nil;
            if (limit >= 60 && limit <= 75 && limit % 5 == 0) {
                BLAdapterController *adapter = [[BLAdapterController alloc] init];
                if (!adapter.helperPath) {
                    fprintf(stderr, "Limits below 80%% require a CHIE SMC helper.\n");
                    return 1;
                }
                if (![controller setLimit:80 error:&error]) {
                    printError(error);
                    return 1;
                }
                NSUserDefaults *settings = BLSettings();
                [settings setInteger:limit forKey:BLLowChargeLimitKey];
                [settings synchronize];
                if (applyAdapterLimitOnce(controller) != 0) {
                    return 1;
                }
                printf("Charge limit set to %ld%% using adapter mode below macOS's native 80%% floor.\n", (long)limit);
                return 0;
            }
            if (limit < 80 || limit > 95 || limit % 5 != 0 || ![controller setLimit:limit error:&error]) {
                if (!error) {
                    error = [NSError errorWithDomain:@"com.ecc.BatteryLimit.PowerUI"
                                                 code:21
                                             userInfo:@{NSLocalizedDescriptionKey: @"Charge limit must be 60, 65, 70, 75, 80, 85, 90, or 95 percent."}];
                }
                printError(error);
                return 1;
            }
            [BLSettings() setInteger:0 forKey:BLLowChargeLimitKey];
            [BLSettings() synchronize];
            if (restoreOwnedAdapter([[BLAdapterController alloc] init]) != 0) {
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
