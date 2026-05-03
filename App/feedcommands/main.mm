//
//  main.mm
//  feedcommands
//
//  Created by John Holdsworth on 23/02/2025.
//  Copyright © 2025 John Holdsworth. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "/tmp/InjectionNextSalt.h"
#import "../../../InjectionNext/Sources/InjectionNextC/include/SimpleSocket.h"
#import "../../../InjectionNext/Sources/InjectionNextC/include/InjectionClient.h"

@interface FeedSocket: SimpleSocket
@end
@implementation FeedSocket {
    FILE *out;
}
+ (int)error:(NSString *)message {
    if (isatty(STDIN_FILENO))
        printf([NSString stringWithFormat:@"%@/%@\n",
                self, message].UTF8String, strerror(errno));
    return 1;
}
- (BOOL)writeBytes:(const void *)buffer length:(size_t)length cmd:(SEL)cmd {
    if (!out)
        out = [self fdopenForMode:"w"];
    return fwrite(buffer, 1, length, out) == length;
}
- (void)dealloc {
    if (out)
        fclose(out);
}
@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // insert code here...
        if (SimpleSocket *app = [FeedSocket connectTo:@COMMANDS_PORT]) {
            [app writeInt:COMMANDS_VERSION];
            [app writeString:NSHomeDirectory()];
            for (int i=1; i<argc; i++)
                [app writeCStr:argv[i]];
        }
        else
            exit(EXIT_FAILURE);
    }
    return 0;
}
