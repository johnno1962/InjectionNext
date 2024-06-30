//
//  ClientBoot.m
//  
//
//  Created by John H on 31/05/2024.
//

#if DEBUG
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#import "InjectionClient.h"
#import "SimpleSocket.h"

@implementation NSObject(InjectionNext)

static SimpleSocket *injectionClient;
static dispatch_once_t onlyOneClient;

/// Called on load of image containing this code
+ (void)load {
    if (Class clientClass = objc_getClass("InjectionNext"))
        [self performSelectorInBackground:@selector(tryConnect:)
                               withObject:clientClass];
}

/// Attempt to connect to InjectionNext.app
+ (void)tryConnect:(Class)clientClass {
    const char *hostip = getenv("INJECTION_HOST") ?: "127.0.0.1";
    
    // Do we need to use broadcasts to find devlepers Mac on the network
    #if !TARGET_IPHONE_SIMULATOR && !TARGET_OS_OSX
    if (!(@available(iOS 14.0, *) && [NSProcessInfo processInfo].isiOSAppOnMac)) {
        printf(APP_PREFIX APP_NAME": Locating developer's Mac. Have you selected \"Enable Devices\"?\n");
        hostip = [SimpleSocket getBroadcastService:HOTRELOADING_MULTICAST port:HOTRELOADING_PORT
                                           message:APP_PREFIX"Connecting to %s (%s)...\n"].UTF8String;
    }
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
}

@end
#endif
