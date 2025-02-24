//
//  main.m
//  feedcommands
//
//  Created by John Holdsworth on 23/02/2025.
//  Copyright © 2025 John Holdsworth. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "../../../InjectionNext/Sources/InjectionNextC/include/SimpleSocket.h"
#import "../../../InjectionNext/Sources/InjectionNextC/include/InjectionClient.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // insert code here...
        if (SimpleSocket *app = [SimpleSocket connectTo:@HOTRELOADING_PORT]) {
            [app writeInt:COMMANDS_VERSION];
            [app writeString:NSHomeDirectory()];
            for (int i=1; i<argc; i++)
                [app writeCStr:argv[i]];
            [app writeCStr:COMMANDS_END];
        }
    }
    return 0;
}
