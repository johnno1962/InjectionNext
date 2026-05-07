//
//  ClientBoot.m
//  
//
//  Created by John H on 31/05/2024.
//

#if DEBUG || !SWIFT_PACKAGE
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#import "InjectionImplC.h"
#import "InjectionClient.h"
#import "SimpleSocket.h"

extern "C" {
const char *_insetting(NSString *name);
}

@interface InjectionNext : SimpleSocket
@end

@implementation NSObject(InjectionNext)

static SimpleSocket *injectionClient;
static dispatch_once_t onlyOneClient;

/// Called on load of image containing this code
+ (void)load {
    if ([InjectionNext InjectionBoot_inPreview]) return;
    #if !TARGET_OS_MAC
    [self performSelectorOnMainThread:@selector(connectInBackground)
                           withObject:nil waitUntilDone:NO];
}

+ (void)connectInBackground {
    #endif
    [self performSelectorInBackground:@selector(connectToInjection:)
                           withObject:[InjectionNext self]];
}

/// Attempt to connect to InjectionNext.app
+ (void)connectToInjection:(Class)clientClass {
    #ifdef INJECTION_HOST_SETTING
    if (!getenv(INJECTION_HOST))
        setenv(INJECTION_HOST, INJECTION_HOST_SETTING, 1);
    #endif
    #ifdef INJECTION_NOSTANDALONE_SETTING
    if (!getenv(INJECTION_NOSTANDALONE))
        setenv(INJECTION_NOSTANDALONE, INJECTION_NOSTANDALONE_SETTING, 1);
    #endif
    const char *hostip = getenv(INJECTION_HOST) ?: "127.0.0.1";

    if (const char *settingsValue = _insetting(@INJECTION_HOST)) {
        NSLog(@APP_PREFIX"Connecting to %s setting %s",
              INJECTION_HOST, settingsValue);
        hostip = settingsValue;
    }
    else
    // Do we need to use broadcasts to find devlepers Mac on the network
    #if !TARGET_IPHONE_SIMULATOR && !TARGET_OS_OSX
    if (@available(iOS 14.0, *)) if (![NSProcessInfo processInfo].isiOSAppOnMac) {
        printf(APP_PREFIX APP_NAME": Locating developer's Mac. Have you selected \"Enable Devices\"?\n");
        hostip = [SimpleSocket getMulticastService:HOTRELOADING_MULTICAST port:HOTRELOADING_PORT
                                           message:APP_PREFIX"Connecting to %s (%s)...\n"].UTF8String;
    }
    #else
    ;
    #endif

    // Have the address to connect to, connect and start local thread.
    NSString *socketAddr = [NSString stringWithFormat:@"%s%s", hostip, INJECTION_ADDRESS];
    for (int retry=0, retrys=1; retry<retrys; retry++) {
        if (retry)
            [NSThread sleepForTimeInterval:1.0];
        if (SimpleSocket *client = [clientClass connectTo:socketAddr]) {
            dispatch_once(&onlyOneClient, ^{
                // Calls to InjectionNext.runInBackground()
                [injectionClient = client run];
            });
            return;
        }
    }

    #if TARGET_IPHONE_SIMULATOR || TARGET_OS_MAC
    // If InjectionLite class present, start it up.
    if (_insetting(@INJECTION_NOSTANDALONE)) return;
    if (Class InjectionLite = objc_getClass("InjectionLite")) {
        printf(APP_PREFIX"Unable to connect to app, running standalone... "
               "Set env var " INJECTION_NOSTANDALONE " to avoid this.\n");
        static NSObject *singleton;
        singleton = [[InjectionLite alloc] init];
    }
    #endif
}

@end
#endif
