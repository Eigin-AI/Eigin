#import "ObjCExceptionCatcher.h"

@implementation ObjCExceptionCatcher

+ (BOOL)tryBlock:(void(NS_NOESCAPE ^)(void))block
           error:(NSError * _Nullable *)error {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            *error = [NSError errorWithDomain:exception.name
                                         code:0
                                     userInfo:@{
                NSLocalizedDescriptionKey: exception.reason ?: @"Unknown Objective-C exception"
            }];
        }
        return NO;
    }
}

@end
