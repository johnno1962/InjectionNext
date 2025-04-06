#!/bin/sh -x

#  build_bundle.sh
#  InjectionNext
#
#  Created by John Holdsworth on 22/07/2024.
#  Copyright © 2024 John Holdsworth. All rights reserved.

FAMILY=$1
PLATFORM=$2
SDK="$(echo $PLATFORM | tr "[A-Z]" "[a-z]")"
sleep $3

FIXED_XCODE_DEVELOPER_PATH=/Applications/Xcode.app/Contents/Developer
export SWIFT_ACTIVE_COMPILATION_CONDITIONS=""

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
        # real devices require a copy_bundle.sh build phase
        ADD_INSTALL_NAME="LD_DYLIB_INSTALL_NAME=@rpath/lib${SDK}Injection.dylib"
    fi
    for i in 1 2 3; do if
    "$DEVELOPER_BIN_DIR"/xcodebuild SYMROOT=$SYMROOT ARCHS="$ARCHS" $APP_SANDBOXED PRODUCT_NAME="${FAMILY}Injection" LD_RUNPATH_SEARCH_PATHS="@loader_path/Frameworks @loader_path/${FAMILY}Injection.bundle/Frameworks $SWIFT_DYLIBS_PATH $CONCURRENCY_DYLIBS $XCTEST_FRAMEWORK_PATH $XCTEST_SUPPORT_PATH" $ADD_INSTALL_NAME PLATFORM_DIR="$DEVELOPER_DIR/Platforms/$PLATFORM.platform" -sdk $SDK -config $BUNDLE_CONFIG  -target InjectionBundle; then
#-archivePath "/tmp/Archive.$SDK" -derivedDataPath "/tmp/Derived.$SDK"
            break
        elif [ "$i" = "3" ]; then
            exit 1
        fi
        echo "Retrying...";
    done &&
    
    rsync -au $SYMROOT/$BUNDLE_CONFIG-$SDK/*.bundle "$CODESIGNING_FOLDER_PATH/Contents/Resources" &&
    ln -sf "${FAMILY}Injection.bundle/${FAMILY}Injection" "$CODESIGNING_FOLDER_PATH/Contents/Resources/lib${SDK}Injection.dylib"
