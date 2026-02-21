#!/bin/bash

#  swift-frontend.sh
#  InjectionNext
#
#  Created by John Holdsworth on 23/02/2025.
#  Copyright © 2025 John Holdsworth. All rights reserved.

FRONTEND="$0"
"$FRONTEND.save" "$@" &&
("/Applications/InjectionNext.app/Contents/Resources/feedcommands" \
    "2.0" "$(/usr/bin/env)" "$FRONTEND.save" "$@" >>/tmp/feedcommands.log 2>&1 &)
