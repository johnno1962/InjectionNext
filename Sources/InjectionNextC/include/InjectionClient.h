//
//  InjectionClient.h
//  InjectionBundle
//
//  Created by John Holdsworth on 06/11/2017.
//  Copyright © 2017 John Holdsworth. All rights reserved.
//
//  $Id: //depot/HotReloading/Sources/HotReloadingGuts/include/InjectionClient.h#60 $
//
//  Shared definitions between server and client.
//

#import <Foundation/Foundation.h>

#define HOTRELOADING_PORT ":8887"
#define HOTRELOADING_MULTICAST "239.255.255.239"

#define INJECTION_VERSION 4001
#define COMMANDS_VERSION 5001
#define COMMANDS_PORT ":8896"
#define INJECTION_ADDRESS HOTRELOADING_PORT
extern NSString *INJECTION_KEY;
#undef APP_NAME
#define APP_NAME "InjectionNext"
#define APP_PREFIX "🔥 "
#define DYLIB_PREFIX "/eval_injection_" // Was expected by DLKit

#define INJECTION_HOST "INJECTION_HOST"
#define INJECTION_DIRECTORIES "INJECTION_DIRECTORIES"
#define INJECTION_PROJECT_ROOT "BUILD_WORKSPACE_DIRECTORY"
#define INJECTION_STANDALONE_INHIBIT "INJECTION_STANDALONE_INHIBIT"

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

    InjectionExit = ~0
};
