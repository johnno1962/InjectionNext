#!/bin/bash

#  swift-frontend.sh
#  InjectionNext
#
#  Created by John Holdsworth on 23/02/2025.
#  Copyright © 2025 John Holdsworth. All rights reserved.

FRONTEND="$0"
"$FRONTEND.save" "$@" &&
("/Applications/InjectionNext.app/Contents/Resources/feedcommands" \
    "1.0" "$PWD" "$FRONTEND.save" "$@" >>/tmp/feedcommands.log 2>&1 &)
