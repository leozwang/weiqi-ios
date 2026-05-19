#import <Foundation/Foundation.h>

@interface KataGoWrapper : NSObject
- (int)initEngineWithConfig:(NSString *)configPath model:(NSString *)modelPath;
- (NSString *)sendGtpCommand:(NSString *)command;
- (void)shutdown;
@end
