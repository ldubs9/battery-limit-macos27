#import <AppKit/AppKit.h>

#import "BLAdapterController.h"
#import "BLBatteryState.h"
#import "BLBatteryStatusDisplay.h"
#import "BLSettings.h"
#import "PowerUIChargeLimit.h"

@interface BLAppDelegate : NSObject <NSApplicationDelegate>
@property (nonatomic, strong) BLChargeLimitController *controller;
@property (nonatomic, strong) BLAdapterController *adapterController;
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) NSMenu *menu;
@property (nonatomic, strong) NSMenu *limitsMenu;
@property (nonatomic, strong) NSMenu *displayModeMenu;
@property (nonatomic, strong) NSMenuItem *statusMenuItem;
@property (nonatomic, strong) NSMenuItem *forceDischargeMenuItem;
@property (nonatomic, strong) NSTimer *pollTimer;
@property (nonatomic, assign) BOOL adapterDisabledByUs;
@property (nonatomic, copy) NSString *lastForceDischargeError;
@end

@implementation BLAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    self.controller = [[BLChargeLimitController alloc] init];
    self.adapterController = [[BLAdapterController alloc] init];
    self.adapterDisabledByUs = [BLSettings() boolForKey:BLForceDischargeAdapterDisabledKey];

    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.title = @"—";
    self.statusItem.button.imageScaling = NSImageScaleProportionallyDown;
    self.statusItem.button.imagePosition = NSImageLeft;

    self.menu = [[NSMenu alloc] initWithTitle:@"Battery Limit"];
    self.statusMenuItem = [[NSMenuItem alloc] initWithTitle:@"Reading status…" action:nil keyEquivalent:@""];
    self.statusMenuItem.enabled = NO;
    [self.menu addItem:self.statusMenuItem];
    [self.menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *setLimit = [[NSMenuItem alloc] initWithTitle:@"Charge limit" action:nil keyEquivalent:@""];
    self.limitsMenu = [[NSMenu alloc] initWithTitle:@"Charge limit"];
    for (NSNumber *limit in @[@60, @65, @70, @75, @80, @85, @90, @95]) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%@%%", limit]
                                                       action:@selector(selectLimit:)
                                                keyEquivalent:@""];
        item.target = self;
        item.tag = limit.integerValue;
        [self.limitsMenu addItem:item];
    }
    [self.limitsMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *disable = [[NSMenuItem alloc] initWithTitle:@"Disable (100%)"
                                                     action:@selector(selectLimit:)
                                              keyEquivalent:@""];
    disable.target = self;
    disable.tag = 100;
    [self.limitsMenu addItem:disable];
    setLimit.submenu = self.limitsMenu;
    [self.menu addItem:setLimit];

    self.forceDischargeMenuItem = [[NSMenuItem alloc] initWithTitle:@"Force discharge"
                                                               action:@selector(toggleForceDischarge:)
                                                        keyEquivalent:@""];
    self.forceDischargeMenuItem.target = self;
    [self.menu addItem:self.forceDischargeMenuItem];

    NSMenuItem *displayMode = [[NSMenuItem alloc] initWithTitle:@"Menu bar display" action:nil keyEquivalent:@""];
    self.displayModeMenu = [[NSMenu alloc] initWithTitle:@"Menu bar display"];
    for (NSInteger rawMode = BLStatusDisplayModeIconOnly;
         rawMode <= BLStatusDisplayModeTextOnly;
         rawMode++) {
        BLStatusDisplayMode mode = (BLStatusDisplayMode)rawMode;
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:BLStatusDisplayModeName(mode)
                                                       action:@selector(selectDisplayMode:)
                                                keyEquivalent:@""];
        item.target = self;
        item.tag = rawMode;
        [self.displayModeMenu addItem:item];
    }
    displayMode.submenu = self.displayModeMenu;
    [self.menu addItem:displayMode];

    NSMenuItem *refreshItem = [[NSMenuItem alloc] initWithTitle:@"Refresh" action:@selector(refresh:) keyEquivalent:@""];
    refreshItem.target = self;
    [self.menu addItem:refreshItem];
    [self.menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Quit" action:@selector(quit:) keyEquivalent:@"q"];
    quit.target = self;
    [self.menu addItem:quit];
    self.statusItem.menu = self.menu;

    [self refresh:nil];
    self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:15.0
                                                       target:self
                                                     selector:@selector(refresh:)
                                                     userInfo:nil
                                                      repeats:YES];
}

- (BOOL)forceDischargeEnabled {
    return [BLSettings() boolForKey:BLForceDischargeEnabledKey];
}

- (void)setForceDischargeEnabled:(BOOL)enabled {
    NSUserDefaults *settings = BLSettings();
    [settings setBool:enabled forKey:BLForceDischargeEnabledKey];
    [settings synchronize];
}

- (NSInteger)lowLimitOverride {
    NSInteger limit = [BLSettings() integerForKey:BLLowChargeLimitKey];
    return (limit >= 60 && limit <= 75 && limit % 5 == 0) ? limit : 0;
}

- (BOOL)adapterEnforcementEnabled {
    return self.forceDischargeEnabled || [self lowLimitOverride] > 0;
}

- (BLStatusDisplayMode)displayMode {
    NSUserDefaults *settings = BLSettings();
    if (![settings objectForKey:BLStatusDisplayModeKey]) {
        return BLStatusDisplayModeIconAndPercentage;
    }
    NSInteger rawMode = [settings integerForKey:BLStatusDisplayModeKey];
    if (rawMode < BLStatusDisplayModeIconOnly || rawMode > BLStatusDisplayModeTextOnly) {
        return BLStatusDisplayModeIconAndPercentage;
    }
    return (BLStatusDisplayMode)rawMode;
}

- (void)setDisplayMode:(BLStatusDisplayMode)mode {
    NSUserDefaults *settings = BLSettings();
    [settings setInteger:mode forKey:BLStatusDisplayModeKey];
    [settings synchronize];
}

- (void)restoreAdapterIfNeeded {
    if (!self.adapterDisabledByUs) {
        return;
    }
    NSError *error = nil;
    if ([self.adapterController setAdapterEnabled:YES error:&error]) {
        self.adapterDisabledByUs = NO;
        NSUserDefaults *settings = BLSettings();
        [settings setBool:NO forKey:BLForceDischargeAdapterDisabledKey];
        [settings synchronize];
        self.lastForceDischargeError = nil;
    } else {
        self.lastForceDischargeError = error.localizedDescription;
    }
}

- (void)evaluateForceDischargeForLimit:(NSInteger)limit
                               battery:(BLBatteryState *)battery {
    if (![self adapterEnforcementEnabled] || !battery) {
        return;
    }

    if (!self.adapterController.helperPath) {
        self.lastForceDischargeError = @"No CHIE helper; run install.sh";
        return;
    }

    BOOL adapterEnabled = NO;
    NSError *error = nil;
    if (![self.adapterController readAdapterEnabled:&adapterEnabled error:&error]) {
        self.lastForceDischargeError = error.localizedDescription;
        return;
    }

    if (battery.percentage > limit) {
        if (adapterEnabled) {
            if ([self.adapterController setAdapterEnabled:NO error:&error]) {
                self.adapterDisabledByUs = YES;
                NSUserDefaults *settings = BLSettings();
                [settings setBool:YES forKey:BLForceDischargeAdapterDisabledKey];
                [settings synchronize];
                self.lastForceDischargeError = nil;
            } else {
                self.lastForceDischargeError = error.localizedDescription;
            }
        }
        return;
    }

    // Re-enable at or below the configured limit. The strict > check above
    // prevents an immediate disable/re-enable loop at the boundary.
    if (self.adapterDisabledByUs && !adapterEnabled) {
        if ([self.adapterController setAdapterEnabled:YES error:&error]) {
            self.adapterDisabledByUs = NO;
            NSUserDefaults *settings = BLSettings();
            [settings setBool:NO forKey:BLForceDischargeAdapterDisabledKey];
            [settings synchronize];
            self.lastForceDischargeError = nil;
        } else {
            self.lastForceDischargeError = error.localizedDescription;
        }
    }
}

- (BLBatteryPowerStage)stageForBattery:(BLBatteryState *)battery {
    if (!battery) {
        return BLBatteryPowerStageUnknown;
    }
    if (self.adapterDisabledByUs) {
        return BLBatteryPowerStageForceDischarging;
    }
    if (battery.isExternalConnected && battery.isCharging) {
        return BLBatteryPowerStageCharging;
    }
    if (battery.isExternalConnected) {
        return BLBatteryPowerStageOnPowerNotCharging;
    }
    return BLBatteryPowerStageDischarging;
}

- (void)updateStatusButtonForBattery:(BLBatteryState *)battery
                               stage:(BLBatteryPowerStage)stage {
    BLStatusDisplayMode mode = [self displayMode];
    NSInteger percentage = battery ? battery.percentage : 0;
    NSString *percentageText = battery ? [NSString stringWithFormat:@"%ld%%", (long)percentage] : @"—";
    NSButton *button = self.statusItem.button;
    button.image = (mode == BLStatusDisplayModeIconOnly || mode == BLStatusDisplayModeIconAndPercentage)
        ? (mode == BLStatusDisplayModeIconAndPercentage
            ? BLCreateStatusItemBatteryIcon(percentage, stage)
            : BLCreateBatteryIcon(percentage, stage))
        : nil;
    button.title = @"";

    switch (mode) {
        case BLStatusDisplayModeIconOnly:
            button.imagePosition = NSImageOnly;
            break;
        case BLStatusDisplayModeIconAndPercentage:
            button.imagePosition = NSImageLeft;
            button.title = percentageText;
            break;
        case BLStatusDisplayModePercentageOnly:
            button.imagePosition = NSNoImage;
            button.title = percentageText;
            break;
        case BLStatusDisplayModeTextOnly:
            button.imagePosition = NSNoImage;
            button.title = battery
                ? [NSString stringWithFormat:@"Battery - %@", percentageText]
                : @"Battery - unavailable";
            break;
    }

    NSString *accessibilityText = battery
        ? [NSString stringWithFormat:@"Battery at %ld percent, %@", (long)percentage, BLBatteryStageAccessibilityName(stage)]
        : @"Battery status unavailable";
    button.accessibilityLabel = accessibilityText;
    button.toolTip = accessibilityText;
}

- (void)updateDisplayModeMenu {
    BLStatusDisplayMode currentMode = [self displayMode];
    for (NSMenuItem *item in self.displayModeMenu.itemArray) {
        item.state = item.tag == currentMode ? NSControlStateValueOn : NSControlStateValueOff;
    }
}

- (void)updateForceDischargeMenuWithLimitEnabled:(BOOL)limitEnabled
                                        lowLimit:(NSInteger)lowLimit {
    BOOL forceEnabled = self.forceDischargeEnabled;
    BOOL lowLimitActive = lowLimit > 0;
    self.forceDischargeMenuItem.state = (forceEnabled || lowLimitActive)
        ? NSControlStateValueOn
        : NSControlStateValueOff;
    self.forceDischargeMenuItem.enabled = self.adapterController.helperPath != nil && !lowLimitActive;
    self.forceDischargeMenuItem.title = @"Force discharge";
    if (self.lastForceDischargeError.length > 0) {
        self.forceDischargeMenuItem.toolTip = self.lastForceDischargeError;
    } else if (!self.adapterController.helperPath) {
        self.forceDischargeMenuItem.toolTip = @"Install the CHIE SMC helper to enable force discharge.";
    } else if (lowLimitActive) {
        self.forceDischargeMenuItem.toolTip = [NSString stringWithFormat:@"Required to enforce the %@%% limit below macOS's native 80%% floor.", @(lowLimit)];
    } else if (!limitEnabled) {
        self.forceDischargeMenuItem.toolTip = @"Set a charge limit before enabling force discharge.";
    } else {
        self.forceDischargeMenuItem.toolTip = forceEnabled
            ? @"Enabled: adapter power is cut above the charge limit."
            : @"Disabled";
    }
}

- (BOOL)ensureNativeSafetyLimitForLowLimit:(NSInteger)lowLimit
                               nativeLimit:(NSInteger *)nativeLimit
                                   enabled:(BOOL *)enabled
                                     error:(NSError **)error {
    if (lowLimit == 0 || (*enabled && *nativeLimit == 80)) {
        return YES;
    }
    if (![self.controller setLimit:80 error:error]) {
        return NO;
    }
    *nativeLimit = 80;
    *enabled = YES;
    return YES;
}

- (void)refresh:(id)sender {
    (void)sender;
    NSError *error = nil;
    NSArray<NSNumber *> *available = [self.controller availableLimits:&error];
    NSInteger limit = 0;
    BOOL enabled = NO;
    BOOL limitRead = !error && [self.controller readCurrentLimit:&limit enabled:&enabled error:&error];
    BLBatteryState *battery = [BLBatteryState read:NULL];

    if (!limitRead) {
        self.statusItem.button.image = nil;
        self.statusItem.button.title = @"Battery - unavailable";
        self.statusMenuItem.image = nil;
        self.statusMenuItem.title = @"Battery status unavailable";
        self.forceDischargeMenuItem.enabled = NO;
        [self updateDisplayModeMenu];
        return;
    }

    NSInteger lowLimit = [self lowLimitOverride];
    NSError *safetyError = nil;
    BOOL safetyLimitReady = [self ensureNativeSafetyLimitForLowLimit:lowLimit
                                                           nativeLimit:&limit
                                                               enabled:&enabled
                                                                 error:&safetyError];
    if (!safetyLimitReady) {
        self.lastForceDischargeError = safetyError.localizedDescription;
    }

    NSInteger effectiveLimit = lowLimit > 0 ? lowLimit : limit;
    BOOL effectiveLimitEnabled = enabled && (lowLimit == 0 || safetyLimitReady);
    if (self.forceDischargeEnabled && enabled) {
        [self evaluateForceDischargeForLimit:effectiveLimit battery:battery];
    } else if ([self adapterEnforcementEnabled] && effectiveLimitEnabled) {
        [self evaluateForceDischargeForLimit:effectiveLimit battery:battery];
    } else if (![self adapterEnforcementEnabled] || !effectiveLimitEnabled) {
        [self restoreAdapterIfNeeded];
    }

    BLBatteryPowerStage stage = [self stageForBattery:battery];
    NSInteger percentage = battery ? battery.percentage : 0;
    NSString *percentageText = battery ? [NSString stringWithFormat:@"%ld%%", (long)percentage] : @"—";
    NSString *stageText = BLBatteryStageShortName(stage);
    NSString *limitText = effectiveLimitEnabled
        ? [NSString stringWithFormat:@"Limit %@%%", @(effectiveLimit)]
        : @"Limit off";

    self.statusMenuItem.title = battery
        ? [NSString stringWithFormat:@"%@ · %@ · %@", percentageText, stageText, limitText]
        : [NSString stringWithFormat:@"Battery unavailable · %@", limitText];
    self.statusMenuItem.image = battery ? BLCreateBatteryIcon(percentage, stage) : nil;
    self.statusMenuItem.toolTip = battery
        ? [NSString stringWithFormat:@"Battery at %@, %@, %@", percentageText, BLBatteryStageAccessibilityName(stage), limitText]
        : @"Battery status unavailable";

    for (NSMenuItem *item in self.limitsMenu.itemArray) {
        if (item.tag == 0) {
            continue;
        }
        item.enabled = item.tag == 100
            || (item.tag < 80 ? self.adapterController.helperPath != nil
                              : [available containsObject:@(item.tag)]);
        item.state = (lowLimit > 0 && item.tag == lowLimit)
            || (lowLimit == 0 && enabled && item.tag == limit)
            || (lowLimit == 0 && !enabled && item.tag == 100)
            ? NSControlStateValueOn
            : NSControlStateValueOff;
    }

    [self updateStatusButtonForBattery:battery stage:stage];
    [self updateDisplayModeMenu];
    [self updateForceDischargeMenuWithLimitEnabled:effectiveLimitEnabled lowLimit:lowLimit];
}

- (void)toggleForceDischarge:(NSMenuItem *)sender {
    (void)sender;
    BOOL enabled = !self.forceDischargeEnabled;
    [self setForceDischargeEnabled:enabled];
    if (!enabled) {
        [self restoreAdapterIfNeeded];
        self.lastForceDischargeError = nil;
    }
    [self refresh:nil];
}

- (void)selectDisplayMode:(NSMenuItem *)sender {
    [self setDisplayMode:(BLStatusDisplayMode)sender.tag];
    [self refresh:nil];
}

- (void)selectLimit:(NSMenuItem *)sender {
    NSInteger selectedLimit = sender.tag;
    NSError *error = nil;
    BOOL success = NO;
    if (selectedLimit < 80) {
        if (!self.adapterController.helperPath) {
            error = [NSError errorWithDomain:@"com.ecc.BatteryLimit.Adapter"
                                         code:20
                                     userInfo:@{NSLocalizedDescriptionKey: @"Limits below 80% require the CHIE SMC helper."}];
        } else {
            // Keep macOS's native 80% cap as a safety ceiling while the
            // adapter loop enforces the requested lower limit.
            success = [self.controller setLimit:80 error:&error];
        }
        if (success) {
            NSUserDefaults *settings = BLSettings();
            [settings setInteger:selectedLimit forKey:BLLowChargeLimitKey];
            [settings synchronize];
        }
    } else {
        success = selectedLimit == 100
            ? [self.controller disable:&error]
            : [self.controller setLimit:selectedLimit error:&error];
        if (success) {
            NSUserDefaults *settings = BLSettings();
            [settings setInteger:0 forKey:BLLowChargeLimitKey];
            [settings synchronize];
        }
    }
    if (!success) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.alertStyle = NSAlertStyleWarning;
        alert.messageText = @"Could not change the charge limit";
        alert.informativeText = error.localizedDescription ? error.localizedDescription : @"PowerUI returned an unknown error.";
        [alert runModal];
        return;
    }
    [self refresh:nil];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    [self restoreAdapterIfNeeded];
}

- (void)quit:(id)sender {
    (void)sender;
    [NSApp terminate:nil];
}

@end

int main(int argc, const char * argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        application.activationPolicy = NSApplicationActivationPolicyAccessory;
        BLAppDelegate *delegate = [[BLAppDelegate alloc] init];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
