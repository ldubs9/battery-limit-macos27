#import "BLAdapterController.h"

static NSString * const BLAdapterErrorDomain = @"com.ecc.BatteryLimit.Adapter";
static const NSInteger BLAdapterErrorUnavailable = 1;
static const NSInteger BLAdapterErrorCommand = 2;
static const NSInteger BLAdapterErrorUnexpectedValue = 3;
static const NSInteger BLAdapterErrorVerification = 4;

@interface BLAdapterController ()
@property (nonatomic, copy, readwrite, nullable) NSString *helperPath;
@end

@implementation BLAdapterController

- (instancetype)init {
    self = [super init];
    if (!self) {
        return nil;
    }

    NSArray<NSString *> *candidates = @[
        @"/usr/local/libexec/battery-limit-smc",
        @"/usr/local/co.palokaj.battery/smc",
        @"/usr/local/bin/smc"
    ];
    for (NSString *candidate in candidates) {
        if ([[NSFileManager defaultManager] isExecutableFileAtPath:candidate]) {
            self.helperPath = candidate;
            break;
        }
    }
    return self;
}

- (NSError *)errorWithCode:(NSInteger)code description:(NSString *)description {
    return [NSError errorWithDomain:BLAdapterErrorDomain
                                code:code
                            userInfo:@{NSLocalizedDescriptionKey: description}];
}

- (BOOL)isDedicatedHelper {
    return [self.helperPath.lastPathComponent isEqualToString:@"battery-limit-smc"];
}

- (NSArray<NSString *> *)argumentsForRead:(BOOL)read
                                    value:(nullable NSString *)value {
    if ([self isDedicatedHelper]) {
        return read
            ? @[@"--key", @"CHIE", @"--read"]
            : @[@"--key", @"CHIE", @"--write", value ? value : @""];
    }
    return read
        ? @[@"-k", @"CHIE", @"-r"]
        : @[@"-k", @"CHIE", @"-w", value ? value : @""];
}

- (BOOL)runHelperRead:(BOOL)read
                value:(nullable NSString *)value
               output:(NSString **)output
                error:(NSError **)error {
    if (!self.helperPath) {
        if (error) {
            *error = [self errorWithCode:BLAdapterErrorUnavailable
                              description:@"No CHIE SMC helper is installed. Run install.sh to enable force discharge."];
        }
        return NO;
    }

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/sudo"];
    task.arguments = [@[ @"-n", self.helperPath ] arrayByAddingObjectsFromArray:
                      [self argumentsForRead:read value:value]];
    NSPipe *stdoutPipe = [NSPipe pipe];
    NSPipe *stderrPipe = [NSPipe pipe];
    task.standardOutput = stdoutPipe;
    task.standardError = stderrPipe;

    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (NSException *exception) {
        if (error) {
            *error = [self errorWithCode:BLAdapterErrorCommand
                              description:[NSString stringWithFormat:@"Could not run the CHIE helper: %@", exception.reason ? exception.reason : @"unknown error"]];
        }
        return NO;
    }

    NSData *stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile;
    NSData *stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile;
    NSString *stdoutText = [[NSString alloc] initWithData:stdoutData encoding:NSUTF8StringEncoding];
    if (!stdoutText) {
        stdoutText = @"";
    }
    NSString *stderrText = [[NSString alloc] initWithData:stderrData encoding:NSUTF8StringEncoding];
    if (!stderrText) {
        stderrText = @"";
    }
    NSString *combined = [@[stdoutText, stderrText] componentsJoinedByString:@"\n"];

    if (task.terminationStatus != 0) {
        NSString *detail = stderrText.length > 0 ? stderrText : stdoutText;
        detail = [detail stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (detail.length == 0) {
            detail = @"sudo could not run the CHIE helper without prompting for a password.";
        }
        if (error) {
            *error = [self errorWithCode:BLAdapterErrorCommand
                              description:detail];
        }
        return NO;
    }

    if (output) {
        *output = combined;
    }
    return YES;
}

- (BOOL)readAdapterEnabled:(BOOL *)enabled error:(NSError **)error {
    if (!enabled) {
        if (error) {
            *error = [self errorWithCode:BLAdapterErrorCommand
                              description:@"Missing adapter status output argument."];
        }
        return NO;
    }

    NSString *output = nil;
    if (![self runHelperRead:YES value:nil output:&output error:error]) {
        return NO;
    }

    NSString *hexValue = nil;
    if ([self isDedicatedHelper]) {
        NSArray<NSString *> *lines = [output componentsSeparatedByCharactersInSet:
                                      NSCharacterSet.whitespaceAndNewlineCharacterSet];
        for (NSString *line in lines) {
            if (line.length == 2 && [line rangeOfCharacterFromSet:
                                     [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"] invertedSet]].location == NSNotFound) {
                hexValue = line.lowercaseString;
                break;
            }
        }
    } else {
        NSRange bytesRange = [output rangeOfString:@"bytes "];
        if (bytesRange.location != NSNotFound &&
            bytesRange.location + bytesRange.length + 2 <= output.length) {
            hexValue = [[output substringWithRange:NSMakeRange(bytesRange.location + bytesRange.length, 2)] lowercaseString];
        }
    }

    if (![hexValue isEqualToString:@"00"] && ![hexValue isEqualToString:@"08"]) {
        if (error) {
            *error = [self errorWithCode:BLAdapterErrorUnexpectedValue
                              description:[NSString stringWithFormat:@"CHIE returned an unsupported value: %@", output ? output : @"(empty)"]];
        }
        return NO;
    }

    *enabled = [hexValue isEqualToString:@"00"];
    return YES;
}

- (BOOL)setAdapterEnabled:(BOOL)enabled error:(NSError **)error {
    NSString *value = enabled ? @"00" : @"08";
    if (![self runHelperRead:NO value:value output:NULL error:error]) {
        return NO;
    }

    BOOL readbackEnabled = NO;
    if (![self readAdapterEnabled:&readbackEnabled error:error]) {
        return NO;
    }
    if (readbackEnabled != enabled) {
        if (error) {
            *error = [self errorWithCode:BLAdapterErrorVerification
                              description:[NSString stringWithFormat:@"CHIE write did not verify (wanted %@, read %@).",
                                           enabled ? @"enabled" : @"disabled",
                                           readbackEnabled ? @"enabled" : @"disabled"]];
        }
        return NO;
    }
    return YES;
}

@end
