# Type a script or drag a script file from your workspace to insert its path.
if [ "$CONFIGURATION" == "Debug" ]; then
    RESOURCES=${RESOURCES:-"$(dirname "$0")"}
    COPY="$CODESIGNING_FOLDER_PATH"
    STRACE="$COPY/Frameworks/SwiftTrace.framework/SwiftTrace"
    PLIST="$COPY/Info.plist"
    if [ "$PLATFORM_NAME" == "macosx" ]; then
     BUNDLE=${1:-macOSInjection}
     COPY="$CODESIGNING_FOLDER_PATH/Contents/Resources/macOSInjection.bundle"
     STRACE="$COPY/Contents/Frameworks/SwiftTrace.framework/Versions/A/SwiftTrace"
     PLIST="$COPY/Contents/Info.plist"
    elif [ "$PLATFORM_NAME" == "appletvsimulator" ]; then
     BUNDLE=${1:-tvOSInjection}
    elif [ "$PLATFORM_NAME" == "appletvos" ]; then
     BUNDLE=${1:-tvdevOSInjection}
    elif [ "$PLATFORM_NAME" == "xrsimulator" ]; then
     BUNDLE=${1:-xrOSInjection}
    elif [ "$PLATFORM_NAME" == "xros" ]; then
     BUNDLE=${1:-xrdevOSInjection}
    elif [ "$PLATFORM_NAME" == "iphoneos" ]; then
     BUNDLE=${1:-maciOSInjection}
     rsync -a "$PLATFORM_DEVELOPER_LIBRARY_DIR"/{Frameworks,PrivateFrameworks}/XC* "$PLATFORM_DEVELOPER_USR_DIR/lib"/*.dylib "$COPY/Frameworks/" &&
     # Xcode 16's new way of bundling tests
     TESTING="/tmp/Testing.$PLATFORM_NAME.framework"
     if [ -d "$COPY/Frameworks/Testing.framework" ]; then
        rsync -a "$COPY/Frameworks/Testing.framework"/* "$TESTING/"
     elif [ -d "$TESTING" ]; then
        rsync -a "$TESTING"/* "$COPY/Frameworks/Testing.framework/"
        codesign -f --sign "$EXPANDED_CODE_SIGN_IDENTITY" --timestamp\=none --preserve-metadata\=identifier,entitlements,flags --generate-entitlement-der "$COPY/Frameworks/Testing.framework";
     fi
     codesign -f --sign "$EXPANDED_CODE_SIGN_IDENTITY" --timestamp\=none --preserve-metadata\=identifier,entitlements,flags --generate-entitlement-der "$COPY/Frameworks"/{XC*,*.dylib};
    else
     BUNDLE=${1:-iOSInjection}
    fi
fi
