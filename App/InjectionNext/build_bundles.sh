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
    XCTEST_FRAMEWORK_PATH="$FIXED_XCODE_DEVELOPER_PATH/Platforms/$PLATFORM.platform/Developer/Library/Frameworks"
    BUNDLE_CONFIG=Debug

    if [ ! -d "$SWIFT_DYLIBS_PATH" -o ! -d "${XCTEST_FRAMEWORK_PATH}/XCTest.framework" ]; then
        echo "Missing RPATH $SWIFT_DYLIBS_PATH $XCTEST_FRAMEWORK_PATH"
        exit 1
    fi
    "$DEVELOPER_BIN_DIR"/xcodebuild SYMROOT=$SYMROOT ARCHS="arm64" $APP_SANDBOXED PRODUCT_NAME="${FAMILY}Injection" LD_RUNPATH_SEARCH_PATHS="@loader_path/Frameworks $SWIFT_DYLIBS_PATH $CONCURRENCY_DYLIBS" PLATFORM_DIR="$DEVELOPER_DIR/Platforms/$PLATFORM.platform" -sdk $SDK -config $BUNDLE_CONFIG -target InjectionBundle &&

    rsync -au $SYMROOT/$BUNDLE_CONFIG-$SDK/*.bundle "$CODESIGNING_FOLDER_PATH/Contents/Resources"
}

build_bundle iOS iPhoneSimulator iphonesimulator &&
build_bundle iOSDev iPhoneOS iphoneos &&
build_bundle tvOS AppleTVSimulator appletvsimulator &&
build_bundle tvOSDev AppleTVOS appletvos &&
build_bundle xrOS XRSimulator xrsimulator &&
build_bundle xrOSDev XROS xros &&
exit 0
