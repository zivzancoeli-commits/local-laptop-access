#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/graphics/IOGraphicsLib.h>
#import <IOKit/pwr_mgt/IOPMLib.h>
#import <dlfcn.h>
#import <stdio.h>
#import <unistd.h>

// Keep a real framebuffer capturing after the lid shuts.
//
// Dim the laptop panel; do not let macOS tear it down. A closed lid with no
// live display makes Sunshine send frozen/black frames while mouse inject still
// works. A same-size virtual display stays the capture target. The built-in
// panel mirrors it while the lid is open, then can go dark without blacking
// out the stream.

@interface CGVirtualDisplayDescriptor : NSObject
@property (nonatomic, strong) NSString *name;
@property (nonatomic, assign) uint32_t maxPixelsWide;
@property (nonatomic, assign) uint32_t maxPixelsHigh;
@property (nonatomic, assign) CGSize sizeInMillimeters;
@property (nonatomic, assign) uint32_t productID;
@property (nonatomic, assign) uint32_t vendorID;
@property (nonatomic, assign) uint32_t serialNum;
@property (nonatomic, assign) CGPoint redPrimary;
@property (nonatomic, assign) CGPoint greenPrimary;
@property (nonatomic, assign) CGPoint bluePrimary;
@property (nonatomic, assign) CGPoint whitePoint;
- (void)setDispatchQueue:(dispatch_queue_t)queue;
@end

@interface CGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(uint32_t)width height:(uint32_t)height refreshRate:(double)refreshRate;
@end

@interface CGVirtualDisplaySettings : NSObject
@property (nonatomic, strong) NSArray *modes;
@property (nonatomic, assign) uint32_t hiDPI;
@end

@interface CGVirtualDisplay : NSObject
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@property (nonatomic, readonly) CGDirectDisplayID displayID;
@end

static NSURL *homeDir(void) {
    return [NSURL fileURLWithPath:NSHomeDirectory()].URLByStandardizingPath;
}

static NSURL *runURL(void) {
    return [homeDir() URLByAppendingPathComponent:@".config/sunshine/keep-lid-awake.run"];
}

static NSURL *pidURL(void) {
    return [homeDir() URLByAppendingPathComponent:@".config/sunshine/keep-lid-awake.pid"];
}

static NSURL *brightnessURL(void) {
    return [homeDir() URLByAppendingPathComponent:@".config/sunshine/keep-lid-awake.brightness"];
}

static pid_t runningPid(void) {
    NSString *text = [NSString stringWithContentsOfURL:pidURL() encoding:NSUTF8StringEncoding error:nil];
    if (text.length == 0) {
        return 0;
    }
    int value = text.intValue;
    if (value <= 1) {
        return 0;
    }
    if (kill((pid_t)value, 0) == 0 || errno == EPERM) {
        return (pid_t)value;
    }
    return 0;
}

static void writePid(pid_t pid) {
    NSString *text = [NSString stringWithFormat:@"%d\n", pid];
    [text writeToURL:pidURL() atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

static BOOL onACPower(void) {
    FILE *pipe = popen("/usr/sbin/ioreg -rn AppleSmartBattery -d 1", "r");
    if (!pipe) {
        return YES;
    }
    BOOL connected = YES;
    char buf[4096];
    NSMutableString *out = [NSMutableString string];
    while (fgets(buf, sizeof(buf), pipe)) {
        [out appendFormat:@"%s", buf];
    }
    pclose(pipe);
    if ([out containsString:@"\"ExternalConnected\" = No"]) {
        connected = NO;
    }
    return connected;
}

static BOOL lidIsClosed(void) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"));
    if (!service) {
        return NO;
    }
    CFTypeRef value = IORegistryEntryCreateCFProperty(service, CFSTR("AppleClamshellState"), kCFAllocatorDefault, 0);
    IOObjectRelease(service);
    BOOL closed = (value == kCFBooleanTrue);
    if (value) {
        CFRelease(value);
    }
    return closed;
}

static void disableClamshellSleep(void) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"));
    if (!service) {
        return;
    }
    IORegistryEntrySetCFProperty(service, CFSTR("DisableClamshellSleep"), kCFBooleanTrue);
    IORegistryEntrySetCFProperty(service, CFSTR("AppleClamshellCausesSleep"), kCFBooleanFalse);
    IORegistryEntrySetCFProperty(service, CFSTR("AppleClamshellCauseSleep"), kCFBooleanFalse);

    io_connect_t connect = IO_OBJECT_NULL;
    if (IOServiceOpen(service, mach_task_self(), 0, &connect) == KERN_SUCCESS) {
        uint64_t input = 1;
        uint32_t selectors[] = { 23, 24, 22 };
        for (size_t i = 0; i < 3; i++) {
            IOConnectCallScalarMethod(connect, selectors[i], &input, 1, NULL, NULL);
        }
        IOServiceClose(connect);
    }
    IOObjectRelease(service);
}

static void wakeDisplayWrangler(void) {
    io_service_t wrangler = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceNameMatching("IODisplayWrangler"));
    if (!wrangler) {
        return;
    }
    IORegistryEntrySetCFProperty(wrangler, CFSTR("IORequestIdle"), kCFBooleanFalse);
    IOObjectRelease(wrangler);
}

typedef int (*DisplayServicesSetBrightnessFn)(CGDirectDisplayID, float);
typedef int (*DisplayServicesGetBrightnessFn)(CGDirectDisplayID, float *);

static void *displayServices(void) {
    static void *handle;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY);
    });
    return handle;
}

static CGDirectDisplayID builtinDisplayID(void) {
    CGDirectDisplayID displays[16] = {0};
    uint32_t count = 0;
    CGGetOnlineDisplayList(16, displays, &count);
    for (uint32_t i = 0; i < count; i++) {
        if (CGDisplayIsBuiltin(displays[i])) {
            return displays[i];
        }
    }
    CGGetActiveDisplayList(16, displays, &count);
    for (uint32_t i = 0; i < count; i++) {
        if (CGDisplayIsBuiltin(displays[i])) {
            return displays[i];
        }
    }
    return CGMainDisplayID();
}

// The real laptop panel only. builtinDisplayID() falls back to whatever
// screen is main, which can be the spare screen.
static CGDirectDisplayID realBuiltinDisplayID(void) {
    CGDirectDisplayID displays[16] = {0};
    uint32_t count = 0;
    CGGetOnlineDisplayList(16, displays, &count);
    for (uint32_t i = 0; i < count; i++) {
        if (CGDisplayIsBuiltin(displays[i])) {
            return displays[i];
        }
    }
    CGGetActiveDisplayList(16, displays, &count);
    for (uint32_t i = 0; i < count; i++) {
        if (CGDisplayIsBuiltin(displays[i])) {
            return displays[i];
        }
    }
    return 0;
}

static BOOL getBrightness(float *outValue) {
    CGDirectDisplayID display = builtinDisplayID();
    void *handle = displayServices();
    if (handle) {
        DisplayServicesGetBrightnessFn getFn = (DisplayServicesGetBrightnessFn)dlsym(handle, "DisplayServicesGetBrightness");
        if (getFn && getFn(display, outValue) == 0) {
            return YES;
        }
    }

    io_iterator_t iterator = 0;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator) != KERN_SUCCESS) {
        return NO;
    }
    BOOL ok = NO;
    io_service_t service;
    while ((service = IOIteratorNext(iterator))) {
        float value = 0;
        if (IODisplayGetFloatParameter(service, kNilOptions, CFSTR(kIODisplayBrightnessKey), &value) == kIOReturnSuccess) {
            *outValue = value;
            ok = YES;
        }
        IOObjectRelease(service);
        if (ok) {
            break;
        }
    }
    IOObjectRelease(iterator);
    return ok;
}

static BOOL setBrightness(float value) {
    if (value < 0) {
        value = 0;
    }
    if (value > 1) {
        value = 1;
    }
    CGDirectDisplayID display = builtinDisplayID();
    void *handle = displayServices();
    if (handle) {
        DisplayServicesSetBrightnessFn setFn = (DisplayServicesSetBrightnessFn)dlsym(handle, "DisplayServicesSetBrightness");
        if (setFn && setFn(display, value) == 0) {
            return YES;
        }
    }

    io_iterator_t iterator = 0;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator) != KERN_SUCCESS) {
        return NO;
    }
    BOOL ok = NO;
    io_service_t service;
    while ((service = IOIteratorNext(iterator))) {
        if (IODisplaySetFloatParameter(service, kNilOptions, CFSTR(kIODisplayBrightnessKey), value) == kIOReturnSuccess) {
            ok = YES;
        }
        IOObjectRelease(service);
    }
    IOObjectRelease(iterator);
    return ok;
}

static void saveBrightness(float value) {
    NSString *text = [NSString stringWithFormat:@"%.4f\n", value];
    [text writeToURL:brightnessURL() atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

static float loadSavedBrightness(void) {
    NSString *text = [NSString stringWithContentsOfURL:brightnessURL() encoding:NSUTF8StringEncoding error:nil];
    if (text.length == 0) {
        return 0.8f;
    }
    float value = text.floatValue;
    if (value <= 0.01f) {
        return 0.8f;
    }
    if (value > 1) {
        return 1;
    }
    return value;
}

static void dimPanel(void) {
    float current = 0.8f;
    if (getBrightness(&current) && current > 0.02f) {
        saveBrightness(current);
    }
    BOOL ok = setBrightness(0.02f);
    fprintf(stderr, "lid closed; laptop panel %s, capture stays on the stream display\n", ok ? "dimmed" : "dim failed");
}

static void restorePanel(void) {
    float value = loadSavedBrightness();
    BOOL ok = setBrightness(value);
    fprintf(stderr, "lid open; panel %s brightness=%.2f\n", ok ? "restored" : "restore failed", value);
    [[NSFileManager defaultManager] removeItemAtURL:brightnessURL() error:nil];
}

static IOPMAssertionID gActivityAssertion = kIOPMNullAssertionID;
static CGVirtualDisplay *gVirtual = nil;
static CGDirectDisplayID gBuiltinID = 0;
static CGDirectDisplayID gVirtualID = 0;
static BOOL gConfiguring = NO;
static NSWindow *gKeepWindow = nil;

static BOOL nearbyLinkWanted(void) {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@".config/moonlight-web/nearby-link.run"];
    return [[NSFileManager defaultManager] fileExistsAtPath:path];
}

static void quietAwdl(void) {
    if (nearbyLinkWanted()) {
        return;
    }
    NSArray<NSArray<NSString *> *> *commands = @[
        @[ @"awdl0", @"down" ],
        @[ @"llw0", @"down" ],
    ];
    for (NSArray<NSString *> *args in commands) {
        NSTask *task = [[NSTask alloc] init];
        task.executableURL = [NSURL fileURLWithPath:@"/sbin/ifconfig"];
        task.arguments = args;
        task.standardInput = [NSFileHandle fileHandleWithNullDevice];
        task.standardOutput = [NSFileHandle fileHandleWithNullDevice];
        task.standardError = [NSFileHandle fileHandleWithNullDevice];
        [task launchAndReturnError:nil];
    }
}

static NSWindow *holdTinyWindow(void) {
    NSRect frame = NSMakeRect(0, 0, 4, 4);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:NSWindowStyleMaskBorderless
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.opaque = NO;
    window.alphaValue = 0.04;
    window.backgroundColor = NSColor.blackColor;
    window.level = NSNormalWindowLevel;
    window.ignoresMouseEvents = YES;
    window.hasShadow = NO;
    window.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces
        | NSWindowCollectionBehaviorStationary
        | NSWindowCollectionBehaviorIgnoresCycle
        | NSWindowCollectionBehaviorFullScreenAuxiliary;
    window.sharingType = NSWindowSharingNone;
    return window;
}

static void placeKeepWindow(void) {
    if (!gKeepWindow) {
        return;
    }
    CGDirectDisplayID target = gVirtualID ? gVirtualID : builtinDisplayID();
    for (NSScreen *screen in NSScreen.screens) {
        NSNumber *number = screen.deviceDescription[@"NSScreenNumber"];
        if (number.unsignedIntValue == target) {
            NSRect frame = NSMakeRect(screen.frame.origin.x, screen.frame.origin.y, 4, 4);
            [gKeepWindow setFrame:frame display:NO];
            break;
        }
    }
    [gKeepWindow orderFrontRegardless];
}

static void pokeDisplayAwake(void) {
    if (gActivityAssertion != kIOPMNullAssertionID) {
        IOPMAssertionRelease(gActivityAssertion);
        gActivityAssertion = kIOPMNullAssertionID;
    }
    // Local, not remote: remote activity lets macOS turn the display off,
    // which is what froze capture last time.
    IOPMAssertionDeclareUserActivity(
        CFSTR("Moonlight stream local session"),
        kIOPMUserActiveLocal,
        &gActivityAssertion);
    wakeDisplayWrangler();
}

static void holdPowerAssertions(IOPMAssertionID *ids, size_t *count) {
    CFStringRef names[] = {
        CFSTR("PreventUserIdleSystemSleep"),
        CFSTR("PreventSystemSleep"),
        CFSTR("PreventUserIdleDisplaySleep"),
        CFSTR("NoDisplaySleepAssertion"),
        CFSTR("NetworkClientActive"),
    };
    CFStringRef labels[] = {
        CFSTR("Moonlight stream keep awake"),
        CFSTR("Moonlight stream lid closed"),
        CFSTR("Moonlight stream display"),
        CFSTR("Moonlight stream no display sleep"),
        CFSTR("Moonlight stream network client"),
    };
    *count = 0;
    for (size_t i = 0; i < 5; i++) {
        IOPMAssertionID assertion = kIOPMNullAssertionID;
        IOReturn status = IOPMAssertionCreateWithName(names[i], kIOPMAssertionLevelOn, labels[i], &assertion);
        if (status == kIOReturnSuccess) {
            ids[(*count)++] = assertion;
        }
    }
}

static void runPmset(NSArray<NSString *> *arguments) {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/pmset"];
    task.arguments = arguments;
    task.standardInput = [NSFileHandle fileHandleWithNullDevice];
    task.standardOutput = [NSFileHandle fileHandleWithNullDevice];
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    [task launchAndReturnError:nil];
}

static void tryPmsetStayAwake(void) {
    runPmset(@[
        @"-c", @"sleep", @"0", @"displaysleep", @"0", @"disksleep", @"0",
        @"powernap", @"0", @"ttyskeepawake", @"1", @"tcpkeepalive", @"1"
    ]);
    runPmset(@[ @"disablesleep", @"1" ]);
}

static void restorePmsetSleep(void) {
    runPmset(@[ @"disablesleep", @"0" ]);
}

static void writeLidState(BOOL closed) {
    NSURL *url = [homeDir() URLByAppendingPathComponent:@".config/moonlight-web/static/lid.json"];
    NSString *json = closed ? @"{\"closed\":true}\n" : @"{\"closed\":false}\n";
    [json writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

static BOOL currentDisplaySize(CGDirectDisplayID displayID, uint32_t *width, uint32_t *height) {
    CGDisplayModeRef mode = CGDisplayCopyDisplayMode(displayID);
    if (!mode) {
        return NO;
    }
    *width = (uint32_t)CGDisplayModeGetWidth(mode);
    *height = (uint32_t)CGDisplayModeGetHeight(mode);
    CGDisplayModeRelease(mode);
    if (*width < 1280) {
        *width = 1440;
    }
    if (*height < 720) {
        *height = 900;
    }
    return YES;
}

static BOOL mirrorBuiltinToVirtual(CGDirectDisplayID builtinID, CGDirectDisplayID virtualID) {
    if (builtinID == 0 || virtualID == 0 || builtinID == virtualID) {
        return NO;
    }
    if (!CGDisplayIsOnline(builtinID) || !CGDisplayIsOnline(virtualID)) {
        return NO;
    }
    if (CGDisplayMirrorsDisplay(builtinID) == virtualID && CGMainDisplayID() == virtualID) {
        return YES;
    }

    gConfiguring = YES;
    CGDisplayConfigRef config = NULL;
    if (CGBeginDisplayConfiguration(&config) != kCGErrorSuccess) {
        gConfiguring = NO;
        return NO;
    }
    CGConfigureDisplayOrigin(config, virtualID, 0, 0);
    CGError mirrorErr = CGConfigureDisplayMirrorOfDisplay(config, builtinID, virtualID);
    if (mirrorErr != kCGErrorSuccess) {
        CGCancelDisplayConfiguration(config);
        gConfiguring = NO;
        fprintf(stderr, "mirror builtin %u -> virtual %u failed (%d); left display layout alone\n",
                builtinID, virtualID, (int)mirrorErr);
        return NO;
    }
    CGError completeErr = CGCompleteDisplayConfiguration(config, kCGConfigureForAppOnly);
    gConfiguring = NO;
    if (completeErr != kCGErrorSuccess) {
        fprintf(stderr, "mirror builtin %u -> virtual %u complete failed (%d)\n", builtinID, virtualID, (int)completeErr);
        return NO;
    }
    fprintf(stderr, "capture display %u; laptop %u mirrors it\n", virtualID, builtinID);
    return YES;
}

static void restoreBuiltinLayout(CGDirectDisplayID builtinID) {
    if (builtinID == 0 || !CGDisplayIsOnline(builtinID)) {
        return;
    }
    if (CGDisplayMirrorsDisplay(builtinID) == kCGNullDirectDisplay && CGMainDisplayID() == builtinID) {
        return;
    }
    gConfiguring = YES;
    CGDisplayConfigRef config = NULL;
    if (CGBeginDisplayConfiguration(&config) != kCGErrorSuccess) {
        gConfiguring = NO;
        return;
    }
    CGError mirrorErr = CGConfigureDisplayMirrorOfDisplay(config, builtinID, kCGNullDirectDisplay);
    CGConfigureDisplayOrigin(config, builtinID, 0, 0);
    if (mirrorErr != kCGErrorSuccess) {
        CGCancelDisplayConfiguration(config);
        gConfiguring = NO;
        return;
    }
    CGCompleteDisplayConfiguration(config, kCGConfigureForAppOnly);
    gConfiguring = NO;
}

static BOOL createCaptureDisplay(uint32_t width, uint32_t height) {
    if (!NSClassFromString(@"CGVirtualDisplay") ||
        !NSClassFromString(@"CGVirtualDisplayDescriptor") ||
        !NSClassFromString(@"CGVirtualDisplaySettings") ||
        !NSClassFromString(@"CGVirtualDisplayMode")) {
        fprintf(stderr, "virtual display API not available\n");
        return NO;
    }

    CGVirtualDisplayDescriptor *descriptor = [[NSClassFromString(@"CGVirtualDisplayDescriptor") alloc] init];
    descriptor.name = @"Moonlight";
    descriptor.maxPixelsWide = width;
    descriptor.maxPixelsHigh = height;
    descriptor.sizeInMillimeters = CGSizeMake(286, 179);
    descriptor.productID = 0x1111;
    descriptor.vendorID = 0x8888;
    descriptor.serialNum = 0x2026;
    [descriptor setDispatchQueue:dispatch_get_main_queue()];
    descriptor.redPrimary = CGPointMake(0.640, 0.330);
    descriptor.greenPrimary = CGPointMake(0.300, 0.600);
    descriptor.bluePrimary = CGPointMake(0.150, 0.060);
    descriptor.whitePoint = CGPointMake(0.3127, 0.3290);

    CGVirtualDisplay *display = [[NSClassFromString(@"CGVirtualDisplay") alloc] initWithDescriptor:descriptor];
    if (!display) {
        fprintf(stderr, "virtual display alloc failed\n");
        return NO;
    }

    Class modeClass = NSClassFromString(@"CGVirtualDisplayMode");
    CGVirtualDisplaySettings *settings = [[NSClassFromString(@"CGVirtualDisplaySettings") alloc] init];
    settings.hiDPI = 0;
    settings.modes = @[ [[modeClass alloc] initWithWidth:width height:height refreshRate:60.0] ];
    if (![display applySettings:settings]) {
        fprintf(stderr, "virtual display applySettings failed\n");
        return NO;
    }

    for (int i = 0; i < 50 && (display.displayID == 0 || !CGDisplayIsOnline(display.displayID)); i++) {
        usleep(20000);
    }
    if (display.displayID == 0) {
        fprintf(stderr, "virtual display id is 0\n");
        return NO;
    }

    gVirtual = display;
    gVirtualID = display.displayID;
    fprintf(stderr, "stream framebuffer %u %ux%u 1x\n", gVirtualID, width, height);
    return YES;
}

static void attachCaptureDisplay(void) {
    if (!gVirtual || gVirtualID == 0) {
        return;
    }
    if (!lidIsClosed()) {
        return;
    }
    CGDirectDisplayID builtinID = builtinDisplayID();
    if (builtinID == 0) {
        builtinID = gBuiltinID;
    }
    if (builtinID != 0) {
        gBuiltinID = builtinID;
    }
    if (gBuiltinID && CGDisplayIsOnline(gBuiltinID)) {
        mirrorBuiltinToVirtual(gBuiltinID, gVirtualID);
    }
    placeKeepWindow();
}

static void destroyCaptureDisplay(void) {
    restoreBuiltinLayout(gBuiltinID ? gBuiltinID : builtinDisplayID());
    if (gVirtual) {
        // This file is compiled without ARC. Assigning nil does not remove
        // the spare screen, so the panel stays empty beside it.
        [gVirtual release];
        gVirtual = nil;
    }
    if (gVirtualID != 0) {
        fprintf(stderr, "removed spare screen %u\n", gVirtualID);
    }
    gVirtualID = 0;
}

static void onDisplayReconfig(CGDirectDisplayID display, CGDisplayChangeSummaryFlags flags, void *userInfo) {
    (void)display;
    (void)userInfo;
    if (gConfiguring || (flags & kCGDisplayBeginConfigurationFlag)) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        // A closed lid keeps this Mac in the same state as an open lid.
        pokeDisplayAwake();
        disableClamshellSleep();
    });
}

static void stopDaemon(void) {
    [[NSFileManager defaultManager] removeItemAtURL:runURL() error:nil];
    pid_t pid = runningPid();
    if (pid > 1) {
        for (int i = 0; i < 50; i++) {
            if (runningPid() == 0) {
                break;
            }
            usleep(50000);
        }
        if (runningPid() > 1) {
            kill(pid, SIGTERM);
            usleep(200000);
        }
        if (runningPid() > 1) {
            kill(pid, SIGKILL);
        }
    }
    [[NSFileManager defaultManager] removeItemAtURL:pidURL() error:nil];
    if ([[NSFileManager defaultManager] fileExistsAtPath:brightnessURL().path]) {
        setBrightness(loadSavedBrightness());
        [[NSFileManager defaultManager] removeItemAtURL:brightnessURL() error:nil];
    }
    restorePmsetSleep();
}

static int runDaemon(void) {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    setbuf(stdout, NULL);
    setbuf(stderr, NULL);

    [[NSFileManager defaultManager] createFileAtPath:runURL().path contents:nil attributes:nil];
    writePid(getpid());

    if (!onACPower()) {
        fprintf(stderr, "warning: plug into power before closing the lid\n");
    }

    disableClamshellSleep();
    tryPmsetStayAwake();
    quietAwdl();

    NSTask *caffeinate = [[NSTask alloc] init];
    caffeinate.executableURL = [NSURL fileURLWithPath:@"/usr/bin/caffeinate"];
    caffeinate.arguments = @[ @"-dimsu", @"-w", [NSString stringWithFormat:@"%d", getpid()] ];
    caffeinate.standardInput = [NSFileHandle fileHandleWithNullDevice];
    caffeinate.standardOutput = [NSFileHandle fileHandleWithNullDevice];
    caffeinate.standardError = [NSFileHandle fileHandleWithNullDevice];
    [caffeinate launchAndReturnError:nil];

    IOPMAssertionID assertions[10] = {0};
    size_t assertionCount = 0;
    holdPowerAssertions(assertions, &assertionCount);

    gBuiltinID = builtinDisplayID();
    // A closed lid used to add a spare screen and dim the panel. The stream
    // then only worked while the lid was open. Keep the laptop screen up
    // and awake, the same as when the lid is open.
    disableClamshellSleep();
    pokeDisplayAwake();
    fprintf(stderr, "lid %s; keeping the laptop on as if the lid were open\n",
            lidIsClosed() ? "closed" : "open");

    gKeepWindow = holdTinyWindow();
    __block BOOL lidWasClosed = lidIsClosed();
    __block NSInteger pokeTick = 0;
    pokeDisplayAwake();
    writeLidState(lidWasClosed);
    fprintf(stderr, "keeping capture alive; builtin %u virtual %u lid %s\n",
            gBuiltinID, gVirtualID, lidWasClosed ? "closed" : "open");

    CGDisplayRegisterReconfigurationCallback(onDisplayReconfig, NULL);

    NSNotificationCenter *workspace = [NSWorkspace sharedWorkspace].notificationCenter;
    [workspace addObserverForName:NSWorkspaceScreensDidSleepNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(__unused NSNotification *note) {
        pokeDisplayAwake();
        disableClamshellSleep();
        quietAwdl();
        fprintf(stderr, "screens slept; woke the session and left the laptop screen on\n");
    }];

    [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer) {
        if (![[NSFileManager defaultManager] fileExistsAtPath:runURL().path]) {
            [timer invalidate];
            if (lidWasClosed) {
                restorePanel();
            }
            writeLidState(NO);
            [NSApp terminate:nil];
            return;
        }

        pokeTick += 1;
        BOOL closed = lidIsClosed();
        disableClamshellSleep();
        pokeDisplayAwake();
        if (pokeTick % 5 == 0) {
            quietAwdl();
        }
        // Drop a spare screen only while the laptop panel itself is still on.
        CGDirectDisplayID panel = realBuiltinDisplayID();
        if (gVirtual && panel != 0) {
            destroyCaptureDisplay();
        }
        if (closed) {
            float brightness = -1;
            if (getBrightness(&brightness) && brightness >= 0 && brightness < 0.15f) {
                restorePanel();
            }
        }

        if (closed == lidWasClosed) {
            return;
        }
        lidWasClosed = closed;
        writeLidState(closed);
        if (closed) {
            fprintf(stderr, "lid closed; leaving the laptop on as if the lid were open\n");
            disableClamshellSleep();
            pokeDisplayAwake();
        } else {
            restorePanel();
            pokeDisplayAwake();
            if (realBuiltinDisplayID() != 0) {
                destroyCaptureDisplay();
            }
        }
    }];

    [NSApp run];

    CGDisplayRemoveReconfigurationCallback(onDisplayReconfig, NULL);
    if (lidWasClosed) {
        restorePanel();
    }
    writeLidState(NO);
    [gKeepWindow orderOut:nil];
    destroyCaptureDisplay();
    restorePmsetSleep();
    if (gActivityAssertion != kIOPMNullAssertionID) {
        IOPMAssertionRelease(gActivityAssertion);
        gActivityAssertion = kIOPMNullAssertionID;
    }
    for (size_t i = 0; i < assertionCount; i++) {
        IOPMAssertionRelease(assertions[i]);
    }
    if (caffeinate.isRunning) {
        [caffeinate terminate];
    }
    [[NSFileManager defaultManager] removeItemAtURL:runURL() error:nil];
    [[NSFileManager defaultManager] removeItemAtURL:pidURL() error:nil];
    return 0;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *command = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"start";
        if ([command isEqualToString:@"stop"]) {
            stopDaemon();
            printf("keep-lid-awake stopped\n");
            return 0;
        }
        if ([command isEqualToString:@"check"]) {
            float brightness = -1;
            getBrightness(&brightness);
            printf("ac-power %s\n", onACPower() ? "yes" : "no");
            printf("lid %s\n", lidIsClosed() ? "closed" : "open");
            printf("brightness %.2f\n", brightness);
            CGDirectDisplayID mainID = CGMainDisplayID();
            CGDirectDisplayID builtinID = builtinDisplayID();
            printf("main-display %u asleep=%s online=%s\n",
                   mainID,
                   CGDisplayIsAsleep(mainID) ? "yes" : "no",
                   CGDisplayIsOnline(mainID) ? "yes" : "no");
            printf("builtin-display %u asleep=%s online=%s\n",
                   builtinID,
                   CGDisplayIsAsleep(builtinID) ? "yes" : "no",
                   CGDisplayIsOnline(builtinID) ? "yes" : "no");
            pid_t pid = runningPid();
            printf("running %s\n", pid > 1 ? [[NSString stringWithFormat:@"%d", pid] UTF8String] : "no");
            return 0;
        }
        if ([command isEqualToString:@"run"]) {
            return runDaemon();
        }

        if (runningPid() > 1) {
            printf("keep-lid-awake already running pid=%d\n", runningPid());
            return 0;
        }

        [[NSFileManager defaultManager] createFileAtPath:runURL().path contents:nil attributes:nil];
        NSTask *task = [[NSTask alloc] init];
        task.executableURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[0]]];
        task.arguments = @[ @"run" ];
        NSURL *logURL = [homeDir() URLByAppendingPathComponent:@".config/sunshine/keep-lid-awake.log"];
        [@"" writeToURL:logURL atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSFileHandle *log = [NSFileHandle fileHandleForWritingToURL:logURL error:nil];
        task.standardInput = [NSFileHandle fileHandleWithNullDevice];
        task.standardOutput = log ?: [NSFileHandle fileHandleWithNullDevice];
        task.standardError = log ?: [NSFileHandle fileHandleWithNullDevice];
        NSError *error = nil;
        if (![task launchAndReturnError:&error]) {
            fprintf(stderr, "failed to start keep-lid-awake: %s\n", error.localizedDescription.UTF8String);
            [[NSFileManager defaultManager] removeItemAtURL:runURL() error:nil];
            return 1;
        }
        writePid(task.processIdentifier);
        usleep(200000);
        printf("keep-lid-awake pid=%d\n", task.processIdentifier);
        return 0;
    }
}
