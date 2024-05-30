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
#define INJECTION_ADDRESS HOTRELOADING_PORT
extern NSString *INJECTION_KEY;
#define APP_NAME "InjectionNext"
#define APP_PREFIX "🔥 "
#define DYLIB_PREFIX "/eval_injection_" // Was expected by DLKit

@interface NSObject(HotReloading)
+ (void)runXCTestCase:(Class)aTestCase;
@end

@interface NSProcessInfo(iOSAppOnMac)
@property BOOL isiOSAppOnMac;
@end

typedef NS_ENUM(int, InjectionCommand) {
    // commands to InjectionNext package
//    InjectionConnected,
//    InjectionWatching,
    InjectionLog,
//    InjectionSigned,
    InjectionLoad,
    InjectionInject,
//    InjectionIdeProcPath,
//    InjectionXprobe,
//    InjectionEval,
//    InjectionVaccineSettingChanged,

//    InjectionTrace,
//    InjectionUntrace,
//    InjectionTraceUI,
//    InjectionTraceUIKit,
//    InjectionTraceSwiftUI,
//    InjectionTraceFramework,
//    InjectionQuietInclude,
//    InjectionInclude,
//    InjectionExclude,
//    InjectionStats,
//    InjectionCallOrder,
//    InjectionFileOrder,
//    InjectionFileReorder,
//    InjectionUninterpose,
//    InjectionFeedback,
//    InjectionLookup,
//    InjectionCounts,
//    InjectionCopy,
//    InjectionPseudoUnlock,
//    InjectionPseudoInject,
//    InjectionObjcClassRefs,
//    InjectionDescriptorRefs,
//    InjectionSetXcodeDev,
//    InjectionAppVersion,
//    InjectionProfileUI,
    InjectionXcodePath,

    InjectionInvalid = 1000,

    InjectionEOF = ~0
};

typedef NS_ENUM(int, InjectionResponse) {
    // responses from InjectionNext package
//    InjectionComplete,
//    InjectionPause,
//    InjectionSign,
//    InjectionError,
//    InjectionFrameworkList,
//    InjectionCallOrderList,
//    InjectionScratchPointer,
//    InjectionTestInjection,
//    InjectionLegacyUnhide,
//    InjectionForceUnhide,
//    InjectionProjectRoot,
//    InjectionGetXcodeDev,
//    InjectionBuildCache,
//    InjectionDerivedData,
    InjectionPlatform,
    InjectionInjected,
    InjectionFailed,
    InjectionTmpPath,

    InjectionExit = ~0
};
