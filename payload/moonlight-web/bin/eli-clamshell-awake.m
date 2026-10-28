#import <CoreFoundation/CoreFoundation.h>
#import <IOKit/IOKitLib.h>
#import <stdio.h>
#import <unistd.h>
int main(void) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"));
    if (!service) {
        fprintf(stderr, "no power service\n");
        return 1;
    }
    kern_return_t disabled = IORegistryEntrySetCFProperty(service, CFSTR("DisableClamshellSleep"), kCFBooleanTrue);
    kern_return_t causes = IORegistryEntrySetCFProperty(service, CFSTR("AppleClamshellCausesSleep"), kCFBooleanFalse);
    io_connect_t connect = IO_OBJECT_NULL;
    kern_return_t opened = IOServiceOpen(service, mach_task_self(), 0, &connect);
    kern_return_t method = KERN_FAILURE;
    if (opened == KERN_SUCCESS) {
        uint64_t input = 0;
        method = IOConnectCallScalarMethod(connect, 12, &input, 1, NULL, NULL);
        IOServiceClose(connect);
    }
    printf("clamshell-awake uid=%d disable=%d causes=%d method=%d\n", getuid(), disabled, causes, method);
    IOObjectRelease(service);
    return 0;
}
