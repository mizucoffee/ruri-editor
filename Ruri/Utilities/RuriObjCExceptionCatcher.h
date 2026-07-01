#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RuriObjCExceptionCatcher : NSObject

+ (BOOL)tryBlock:(void (NS_NOESCAPE ^)(void))block error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
