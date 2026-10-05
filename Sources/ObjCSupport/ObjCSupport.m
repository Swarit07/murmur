#import "ObjCSupport.h"

BOOL MurmurCatchException(NS_NOESCAPE void (^block)(void), NSError **error) {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            NSMutableDictionary *info = [NSMutableDictionary dictionary];
            info[NSLocalizedDescriptionKey] = exception.reason ?: exception.name;
            info[@"MurmurExceptionName"] = exception.name;
            *error = [NSError errorWithDomain:@"MurmurObjCException" code:1 userInfo:info];
        }
        return NO;
    }
}
