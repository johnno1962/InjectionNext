//
//  main.mm
//  feedcommands
//
//  Created by John Holdsworth on 23/02/2025.
//  Copyright © 2025 John Holdsworth. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "../../../InjectionNext/Sources/InjectionNextC/include/SimpleSocket.h"
#import "../../../InjectionNext/Sources/InjectionNextC/include/InjectionClient.h"

@interface FeedSocket: SimpleSocket
@end
@implementation FeedSocket
+ (int)error:(NSString *)message {
    if (isatty(STDIN_FILENO))
        printf([NSString stringWithFormat:@"%@/%@\n",
                self, message].UTF8String, strerror(errno));
    return 1;
}
@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // insert code here...
        if (SimpleSocket *app = [FeedSocket connectTo:@HOTRELOADING_PORT]) {
            [app writeInt:COMMANDS_VERSION];
            [app writeString:NSHomeDirectory()];
            for (int i=1; i<argc; i++)
                [app writeCStr:argv[i]];
        }
    }
    return 0;
}
