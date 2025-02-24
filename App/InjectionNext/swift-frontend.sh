#!/bin/bash

#  swift-frontend.sh
#  InjectionNext
#
#  Created by John Holdsworth on 23/02/2025.
#  Copyright © 2025 John Holdsworth. All rights reserved.

FRONTEND="$(dirname $0)"/swift-frontend.save
"$FRONTEND" "$@" &&
(/Applications/InjectionNext.app/Contents/Resources/feedcommands "$FRONTEND" "$@" >>/tmp/feedcommands.log 2>&1 &)
