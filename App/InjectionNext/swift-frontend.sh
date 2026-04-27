#!/bin/bash

#  swift-frontend.sh
#  InjectionNext
#
#  Created by John Holdsworth on 23/02/2025.
#  Copyright © 2025 John Holdsworth. All rights reserved.
#
#  Compiler interceptor wrapper. Installed in place of swift-frontend (and,
#  on Xcode 26+, in place of swiftc) so that builtin-SwiftDriver compile
#  invocations route through here. Runs the original binary preserving
#  argv[0] (so the multi-mode swift binary picks the right tool) and, on
#  successful compile invocations, feeds the captured command line to
#  InjectionNext.app for later use as a recompile template.

FRONTEND="$0"
SAVE="$FRONTEND.save"

# Run the real binary with argv[0] preserved. The Swift toolchain ships a
# single multi-mode binary (swift-frontend / swiftc / swift / etc.) and
# dispatches by argv[0] basename. Without -a here, when this wrapper is
# installed at swiftc the binary would see itself as "swiftc.save" and the
# dispatch would fall through to the wrong mode.
( exec -a "$FRONTEND" "$SAVE" "$@" )
RC=$?

# Only feed the command if the real compile succeeded and this looks like a
# per-file frontend compile. $2="-c" matches both legacy
# `swift-frontend -frontend -c ...` and Xcode 26 `swiftc -frontend -c ...`.
if [ $RC -eq 0 ] && [ "$2" = "-c" ]; then
    # Always report the canonical original binary path to feedcommands so
    # downstream cache entries are stable regardless of which symlink hit
    # the wrapper.
    CANONICAL="$(dirname "$FRONTEND")/swift-frontend.save"
    "/Applications/InjectionNext.app/Contents/Resources/feedcommands" \
        "2.0" "$(/usr/bin/env)" "$CANONICAL" "$@" >>/tmp/feedcommands.log 2>&1 &
fi

exit $RC
