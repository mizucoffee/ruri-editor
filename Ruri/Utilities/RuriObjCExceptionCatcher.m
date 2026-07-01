#import "RuriObjCExceptionCatcher.h"

static NSString * const RuriObjCExceptionCatcherErrorDomain = @"net.mizucoffee.ruri.objc-exception";

@implementation RuriObjCExceptionCatcher

+ (BOOL)tryBlock:(void (NS_NOESCAPE ^)(void))block error:(NSError **)error
{
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (error != NULL) {
            NSMutableDictionary<NSErrorUserInfoKey, id> *userInfo = [NSMutableDictionary dictionary];
            userInfo[NSLocalizedDescriptionKey] = exception.reason.length > 0
                ? exception.reason
                : exception.name;
            userInfo[@"RuriObjCExceptionName"] = exception.name;
            if (exception.reason != nil) {
                userInfo[@"RuriObjCExceptionReason"] = exception.reason;
            }

            *error = [NSError errorWithDomain:RuriObjCExceptionCatcherErrorDomain
                                         code:1
                                     userInfo:userInfo];
        }
        return NO;
    }
}

@end
