#!/bin/bash

#  swift-frontend.sh
#  InjectionNext
#
#  Created by John Holdsworth on 23/02/2025.
#  Copyright © 2025 John Holdsworth. All rights reserved.

FRONTEND="$0"
RESOURCES="$(dirname "$(readlink "$FRONTEND")")"
"$FRONTEND.save" "$@" &&
("$RESOURCES/feedcommands" "$FRONTEND.save" "$@" >>/tmp/feedcommands.log 2>&1 &)
