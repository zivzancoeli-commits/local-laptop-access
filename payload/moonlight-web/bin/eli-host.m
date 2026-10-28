#import <Foundation/Foundation.h>
#import <CoreWLAN/CoreWLAN.h>
#import <SystemConfiguration/SystemConfiguration.h>

@interface CWWiFiClient (EliHost)
- (CWInterface *)interfaceWithRole:(NSInteger)role;
@end

@interface CWInterface (EliHost)
- (BOOL)startHostAPMode:(NSError **)error;
- (BOOL)startHostAPModeWithSSID:(id)ssid
                    securityType:(NSUInteger)security
                         channel:(id)channel
                        password:(id)password
                           error:(NSError **)error;
- (NSSet *)supportedWLANChannels;
- (void)stopHostAPMode;
- (BOOL)powerOn;
@end

static CWChannel *channel6(CWInterface *iface) {
    for (CWChannel *channel in [iface supportedWLANChannels]) {
        if (channel.channelNumber == 6 && channel.channelBand == kCWChannelBand2GHz && channel.channelWidth == kCWChannelWidth20MHz) {
            return channel;
        }
    }
    return iface.wlanChannel;
}

static void printInterface(NSString *label, CWInterface *iface) {
    if (!iface) {
        printf("%s missing\n", label.UTF8String);
        return;
    }
    printf("%s name=%s mode=%ld power=%d\n",
           label.UTF8String,
           iface.interfaceName.UTF8String ?: "?",
           (long)iface.interfaceMode,
           iface.powerOn ? 1 : 0);
}

static CWInterface *apInterface(void) {
    CWWiFiClient *client = [CWWiFiClient sharedWiFiClient];
    return [client interface] ?: [client interfaceWithRole:1];
}

int main(int argc, char **argv) {
    setbuf(stdout, NULL);
    @autoreleasepool {
        NSString *command = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"roles";
        CWWiFiClient *client = [CWWiFiClient sharedWiFiClient];
        if ([command isEqualToString:@"roles"]) {
            for (NSInteger role = 0; role <= 5; role++) {
                printInterface([NSString stringWithFormat:@"role%ld", (long)role],
                               [client interfaceWithRole:role]);
            }
            printInterface(@"default", client.interface);
            return 0;
        }
        if ([command isEqualToString:@"stop"]) {
            CWInterface *iface = apInterface();
            [iface stopHostAPMode];
            printf("stopped %s mode %ld\n",
                   iface.interfaceName.UTF8String ?: "?",
                   (long)iface.interfaceMode);
            return 0;
        }
        if (![command isEqualToString:@"start"]) {
            printf("usage: eli-host roles|start|stop\n");
            return 2;
        }

        CWInterface *iface = apInterface();
        printInterface(@"using", iface);
        if (!iface) {
            printf("no-ap-interface\n");
            return 1;
        }
        CWChannel *channel = channel6(iface);
        // airportd maps the public value 0x80 to internal WPA2-PSK (0x10).
        // 4 and 0x10 are ignored, so the hosted network stays "Unknown".
        const NSUInteger kHostAPWPA2 = 0x80;
        printf("channel %ld band %ld security %lu\n",
               (long)channel.channelNumber,
               (long)channel.channelBand,
               (unsigned long)kHostAPWPA2);
        NSError *error = nil;
        BOOL ok = NO;
        @try {
            NSString *ssid = argc > 2 ? [NSString stringWithUTF8String:argv[2]] : @"host-internet";
            NSString *pass = argc > 3 ? [NSString stringWithUTF8String:argv[3]] : @"Password123";
            ok = [iface startHostAPModeWithSSID:[ssid dataUsingEncoding:NSUTF8StringEncoding]
                                    securityType:kHostAPWPA2
                                         channel:channel
                                        password:pass
                                           error:&error];
        } @catch (NSException *exception) {
            printf("rejected %s\n", exception.reason.UTF8String ?: "exception");
            return 1;
        }
        printf("start ok=%d mode=%ld err=%ld %s\n",
               ok,
               (long)iface.interfaceMode,
               (long)error.code,
               error.localizedDescription.UTF8String ?: "");
        return ok ? 0 : 1;
    }
}
