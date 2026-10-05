#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block` and converts an Objective-C exception into an NSError. AVAudioEngine reports some
/// failures (no input device, a format it cannot connect) by raising, which Swift cannot catch.
BOOL MurmurCatchException(NS_NOESCAPE void (^block)(void), NSError * _Nullable * _Nullable error);

NS_ASSUME_NONNULL_END
