//
//  InjectionClient.h
//  InjectionBundle
//
//  Created by John Holdsworth on 06/11/2017.
//  Copyright © 2017 John Holdsworth. All rights reserved.
//
//  $Id: //depot/InjectionNext/Sources/InjectionNextC/include/InjectionClient.h#60 $
//
//  Shared definitions between server and client.
//

#import <Foundation/Foundation.h>

#define HOTRELOADING_PORT ":8887"
#define HOTRELOADING_MULTICAST "239.255.255.239"

#define INJECTION_VERSION 4001
#define COMMANDS_PORT ":8896"
#define INJECTION_ADDRESS HOTRELOADING_PORT
extern NSString *INJECTION_KEY;
#undef APP_NAME
#define APP_NAME "InjectionNext"
#define APP_PREFIX "🔥 "
#define DYLIB_PREFIX "/eval_injection_" // Expected by DLKit.appImages

#define INJECTION_APP_VERSION "INJECTION_APP_VERSION"
#define INJECTION_DLOPEN_MODE "INJECTION_DLOPEN_MODE"
#define UNSETENV_VALUE "__NULL__"

@interface NSObject(HotReloading)
+ (void)runXCTestCase:(Class)aTestCase;
@end

@interface NSProcessInfo(iOSAppOnMac)
@property BOOL isiOSAppOnMac;
@end

typedef NS_ENUM(int, InjectionCommand) {
    // commands to InjectionNext package
    InjectionLog,
    InjectionLoad,
    InjectionInject,
    InjectionXcodePath,
    InjectionSendFile,
    InjectionMetrics,
    InjectionSetenv,
    InjectionEndenv,

    InjectionInvalid = 1000,

    InjectionEOF = ~0
};

typedef NS_ENUM(int, InjectionResponse) {
    // responses from InjectionNext package
    InjectionPlatform,
    InjectionInjected,
    InjectionFailed,
    InjectionTmpPath,
    InjectionUnhide,
    InjectionProjectRoot,
    InjectionDetail,
    InjectionBazelTarget,
    InjectionExecutable,

    InjectionExit = ~0
};
