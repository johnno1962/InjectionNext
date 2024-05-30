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
//NSString *injectionHost = @"127.0.0.1";
static dispatch_once_t onlyOneClient;

+ (void)load {
    if (Class clientClass = objc_getClass("InjectionNext"))
        [self performSelectorInBackground:@selector(tryConnect:)
                               withObject:clientClass];
}

+ (void)tryConnect:(Class)clientClass {
    const char *hostip = getenv("INJECTION_HOST") ?: "127.0.0.1";
    
    #if !TARGET_IPHONE_SIMULATOR && !TARGET_OS_OSX
    if (!(@available(iOS 14.0, *) && [NSProcessInfo processInfo].isiOSAppOnMac)) {
        printf(APP_PREFIX APP_NAME": Locating developer's Mac. Have you selected \"Enable Devices\"?\n");
        hostip = [SimpleSocket getBroadcastService:HOTRELOADING_MULTICAST port:HOTRELOADING_PORT
                                           message:APP_PREFIX"Connecting to %s (%s)...\n"].UTF8String;
    }
    #endif
    
    NSString *socketAddr = [NSString stringWithFormat:@"%s%s", hostip, INJECTION_ADDRESS];
    for (int retry=0, retrys=1; retry<retrys; retry++) {
        if (retry)
            [NSThread sleepForTimeInterval:1.0];
        if (SimpleSocket *client = [clientClass connectTo:socketAddr]) {
            dispatch_once(&onlyOneClient, ^{
                [injectionClient = client run];
            });
            return;
        }
    }
}

@end
#endif
