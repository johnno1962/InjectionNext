#!/bin/bash -x
#
#  copy_bundle.sh
#  InjectionIII
#
#  Copies injection bundle for on-device injection.
#  Thanks @oryonatan
#
#  $Id: //depot/HotReloading/copy_bundle.sh#14 $
#

if [ "$CONFIGURATION" == "Debug" ]; then
    RESOURCES=${RESOURCES:-"$(dirname "$0")"}
    COPY="$CODESIGNING_FOLDER_PATH/iOSInjection.bundle"
    PLIST="$COPY/Info.plist"
    if [ "$PLATFORM_NAME" == "macosx" ]; then
     BUNDLE=${1:-macOSInjection}
     COPY="$CODESIGNING_FOLDER_PATH/Contents/Resources/macOSInjection.bundle"
     PLIST="$COPY/Contents/Info.plist"
    elif [ "$PLATFORM_NAME" == "appletvsimulator" ]; then
     BUNDLE=${1:-tvOSInjection}
    elif [ "$PLATFORM_NAME" == "appletvos" ]; then
     BUNDLE=${1:-tvOSDevInjection}
    elif [ "$PLATFORM_NAME" == "xrsimulator" ]; then
     BUNDLE=${1:-xrOSInjection}
    elif [ "$PLATFORM_NAME" == "xros" ]; then
     BUNDLE=${1:-xrOSDevInjection}
    elif [ "$PLATFORM_NAME" == "iphoneos" ]; then
     BUNDLE=${1:-iOSDevInjection}
     rsync -a "$PLATFORM_DEVELOPER_LIBRARY_DIR"/{Frameworks,PrivateFrameworks}/XC* "$PLATFORM_DEVELOPER_USR_DIR/lib"/*.dylib "$COPY/Frameworks/" &&
     codesign -f --sign "$EXPANDED_CODE_SIGN_IDENTITY" --timestamp\=none --preserve-metadata\=identifier,entitlements,flags --generate-entitlement-der "$COPY/Frameworks"/{XC*,*.dylib};
    else
     BUNDLE=${1:-iOSInjection}
    fi
    rsync -a "$RESOURCES/$BUNDLE.bundle"/* "$COPY/" &&
    /usr/libexec/PlistBuddy -c "Add :UserHome string $HOME" "$PLIST" &&
    codesign -f --sign "$EXPANDED_CODE_SIGN_IDENTITY" --timestamp\=none --preserve-metadata\=identifier,entitlements,flags --generate-entitlement-der "$COPY" &&
    defaults write com.johnholdsworth.InjectionNext codesigningIdentity "$EXPANDED_CODE_SIGN_IDENTITY"
fi
