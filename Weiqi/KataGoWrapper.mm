#import "KataGoWrapper.h"
#import "KataGoBridge.hpp"

@interface KataGoWrapper() {
    KataGoBridge *bridge;
}
@end

@implementation KataGoWrapper

- (instancetype)init {
    self = [super init];
    if (self) {
        bridge = new KataGoBridge();
    }
    return self;
}

- (void)dealloc {
    delete bridge;
}

- (int)initEngineWithConfig:(NSString *)configPath model:(NSString *)modelPath {
    return bridge->initEngine([configPath UTF8String], [modelPath UTF8String]);
}

- (NSString *)sendGtpCommand:(NSString *)command {
    std::string res = bridge->sendGtpCommand([command UTF8String]);
    return [NSString stringWithUTF8String:res.c_str()];
}

- (void)shutdown {
    bridge->shutdown();
}

@end
