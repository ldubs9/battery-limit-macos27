#import <AppKit/AppKit.h>

#import "BLAdapterController.h"
#import "BLBatteryState.h"
#import "BLSettings.h"
#import "PowerUIChargeLimit.h"

@interface BLAppDelegate : NSObject <NSApplicationDelegate>
@property (nonatomic, strong) BLChargeLimitController *controller;
@property (nonatomic, strong) BLAdapterController *adapterController;
@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) NSMenu *menu;
@property (nonatomic, strong) NSMenu *limitsMenu;
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
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.title = @"Battery — …";

    self.menu = [[NSMenu alloc] initWithTitle:@"Battery Limit"];
    self.statusMenuItem = [[NSMenuItem alloc] initWithTitle:@"Reading status…" action:nil keyEquivalent:@""];
    self.statusMenuItem.enabled = NO;
    [self.menu addItem:self.statusMenuItem];
    [self.menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *setLimit = [[NSMenuItem alloc] initWithTitle:@"Set charge limit" action:nil keyEquivalent:@""];
    self.limitsMenu = [[NSMenu alloc] initWithTitle:@"Set charge limit"];
    for (NSNumber *limit in @[@80, @85, @90, @95]) {
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

    self.forceDischargeMenuItem = [[NSMenuItem alloc] initWithTitle:@"Force discharge above limit"
                                                               action:@selector(toggleForceDischarge:)
                                                        keyEquivalent:@""];
    self.forceDischargeMenuItem.target = self;
    [self.menu addItem:self.forceDischargeMenuItem];
    [self.menu addItem:[[NSMenuItem alloc] initWithTitle:@"Refresh" action:@selector(refresh:) keyEquivalent:@""]];
    self.menu.itemArray.lastObject.target = self;
    [self.menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Quit Battery Limit" action:@selector(quit:) keyEquivalent:@"q"];
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

- (void)restoreAdapterIfNeeded {
    if (!self.adapterDisabledByUs) {
        return;
    }
    NSError *error = nil;
    if ([self.adapterController setAdapterEnabled:YES error:&error]) {
        self.adapterDisabledByUs = NO;
        self.lastForceDischargeError = nil;
    } else {
        self.lastForceDischargeError = error.localizedDescription;
    }
}

- (void)evaluateForceDischargeForLimit:(NSInteger)limit
                               battery:(BLBatteryState *)battery {
    if (!self.forceDischargeEnabled || !battery) {
        return;
    }

    if (!self.adapterController.helperPath) {
        self.lastForceDischargeError = @"No CHIE SMC helper is installed; run install.sh for force discharge.";
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
            self.lastForceDischargeError = nil;
        } else {
            self.lastForceDischargeError = error.localizedDescription;
        }
    }
}

- (void)updateForceDischargeMenuWithBattery:(BLBatteryState *)battery
                                      limit:(NSInteger)limit
                                    enabled:(BOOL)limitEnabled {
    BOOL forceEnabled = self.forceDischargeEnabled;
    self.forceDischargeMenuItem.state = forceEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.forceDischargeMenuItem.enabled = self.adapterController.helperPath != nil;

    if (!self.adapterController.helperPath) {
        self.forceDischargeMenuItem.title = @"Force discharge (install SMC helper)";
    } else if (!limitEnabled) {
        self.forceDischargeMenuItem.title = @"Force discharge (set a charge limit first)";
    } else if (self.adapterDisabledByUs) {
        self.forceDischargeMenuItem.title = @"Force discharge active (adapter off)";
    } else if (forceEnabled) {
        self.forceDischargeMenuItem.title = @"Force discharge above limit ✓";
    } else {
        self.forceDischargeMenuItem.title = @"Force discharge above limit";
    }

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
        self.statusItem.button.title = @"Battery — unavailable";
        self.statusMenuItem.title = error.localizedDescription ? error.localizedDescription : @"Native charge limit unavailable";
        self.forceDischargeMenuItem.enabled = NO;
        return;
    }

    if (self.forceDischargeEnabled && enabled) {
        [self evaluateForceDischargeForLimit:limit battery:battery];
    } else if (!self.forceDischargeEnabled || !enabled) {
        [self restoreAdapterIfNeeded];
    }

    NSString *batteryText = battery ? [NSString stringWithFormat:@"%ld%%", (long)battery.percentage] : @"battery ?";
    NSString *forceText = @"Force discharge: off";
    if (self.forceDischargeEnabled) {
        if (self.adapterDisabledByUs) {
            forceText = @"Force discharge: active";
        } else if (self.lastForceDischargeError.length > 0) {
            forceText = [NSString stringWithFormat:@"Force discharge: %@", self.lastForceDischargeError];
        } else {
            forceText = @"Force discharge: armed";
        }
    }

    self.statusItem.button.title = enabled
        ? [NSString stringWithFormat:@"Battery — %@%@", batteryText, self.adapterDisabledByUs ? @" ⤓" : @""]
        : [NSString stringWithFormat:@"Battery — %@", batteryText];
    self.statusMenuItem.title = enabled
        ? [NSString stringWithFormat:@"Limit: %@%% · %@ · %@", @(limit), batteryText, forceText]
        : [NSString stringWithFormat:@"Limit: disabled (100%%) · %@ · %@", batteryText, forceText];

    for (NSMenuItem *item in self.limitsMenu.itemArray) {
        if (item.tag == 0) {
            continue;
        }
        item.enabled = item.tag == 100 || [available containsObject:@(item.tag)];
        item.state = (enabled && item.tag == limit) || (!enabled && item.tag == 100)
            ? NSControlStateValueOn
            : NSControlStateValueOff;
    }
    [self updateForceDischargeMenuWithBattery:battery limit:limit enabled:enabled];
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

- (void)selectLimit:(NSMenuItem *)sender {
    NSError *error = nil;
    BOOL success = sender.tag == 100
        ? [self.controller disable:&error]
        : [self.controller setLimit:sender.tag error:&error];
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
