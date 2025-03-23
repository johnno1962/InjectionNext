#!/bin/sh

#  build_bundles.sh
#  InjectionNext
#
#  Created by John Holdsworth on 22/07/2024.
#  Copyright © 2024 John Holdsworth. All rights reserved.

FIXED_XCODE_DEVELOPER_PATH=/Applications/Xcode.app/Contents/Developer
export SWIFT_ACTIVE_COMPILATION_CONDITIONS=""

function build_bundle () {
    FAMILY=$1
    PLATFORM=$2
    SDK=$3
    SWIFT_DYLIBS_PATH="$FIXED_XCODE_DEVELOPER_PATH/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/$SDK"
    CONCURRENCY_DYLIBS="$FIXED_XCODE_DEVELOPER_PATH/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift-5.5/$SDK"
    XCODE_PLATFORM_PATH="$FIXED_XCODE_DEVELOPER_PATH/Platforms/$PLATFORM.platform"
    XCTEST_FRAMEWORK_PATH="$XCODE_PLATFORM_PATH/Developer/Library/Frameworks"
    XCTEST_SUPPORT_PATH="$XCODE_PLATFORM_PATH/Developer/usr/lib"
    BUNDLE_CONFIG=Debug

    if [ ! -d "$SWIFT_DYLIBS_PATH" -o ! -d "${XCTEST_FRAMEWORK_PATH}/XCTest.framework" ]; then
        echo "Missing RPATH $SWIFT_DYLIBS_PATH $XCTEST_FRAMEWORK_PATH"
        exit 1
    fi
    
    ADD_INSTALL_NAME=""
    if [[ ${FAMILY} =~ Dev ]]; then
        ADD_INSTALL_NAME="LD_DYLIB_INSTALL_NAME=@rpath/lib${SDK}Injection.dylib"
    fi
    "$DEVELOPER_BIN_DIR"/xcodebuild SYMROOT=$SYMROOT ARCHS="$ARCHS" $APP_SANDBOXED PRODUCT_NAME="${FAMILY}Injection" LD_RUNPATH_SEARCH_PATHS="@loader_path/Frameworks @loader_path/${FAMILY}Injection.bundle/Frameworks $SWIFT_DYLIBS_PATH $CONCURRENCY_DYLIBS $XCTEST_FRAMEWORK_PATH $XCTEST_SUPPORT_PATH" $ADD_INSTALL_NAME PLATFORM_DIR="$DEVELOPER_DIR/Platforms/$PLATFORM.platform" -sdk $SDK -config $BUNDLE_CONFIG -target InjectionBundle &&
    
    rsync -au $SYMROOT/$BUNDLE_CONFIG-$SDK/*.bundle "$CODESIGNING_FOLDER_PATH/Contents/Resources" &&
    ln -sf "${FAMILY}Injection.bundle/${FAMILY}Injection" "$CODESIGNING_FOLDER_PATH/Contents/Resources/lib${SDK}Injection.dylib"
}

ln -sf "macOSInjection.bundle/Contents/MacOS/macOSInjection" "$CODESIGNING_FOLDER_PATH/Contents/Resources/libmacosxInjection.dylib" &&

build_bundle iOS iPhoneSimulator iphonesimulator &&
build_bundle tvOS AppleTVSimulator appletvsimulator &&
build_bundle xrOS XRSimulator xrsimulator &&
build_bundle iOSDev iPhoneOS iphoneos &&
build_bundle tvOSDev AppleTVOS appletvos &&
build_bundle xrOSDev XROS xros &&

exit 0
