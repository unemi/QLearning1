//
//  Comm.h
//  Learning is Life
//
//  Created by Tatsuo Unemi on 2023/01/28.
//

@import Cocoa;
@import simd;

NS_ASSUME_NONNULL_BEGIN

#define OSC_PORT 5000
#define SND_STEPS_PER_PKT 1

extern unsigned long current_time_us(void);
extern void in_main_thread(void (^block)(void));
extern void error_msg(NSObject *obj, NSWindow * _Nullable window);
extern void err_msg(NSString *msg, OSStatus err, BOOL isFatal);

@protocol CommDelegate
- (void)receive:(char *)buf length:(ssize_t)length;
@end

@interface Comm : NSObject
@property (readonly) BOOL valid;
@property (readonly) NSString *myAddress, *myBroadcastAddress, *senderAddress;
@property NSString *destinationAddress;
@property in_port_t destinationPort;
@property (readonly) in_port_t receiverPort;
- (void)setStatHandlersSnd:(void (^ _Nullable)(CGFloat pps, CGFloat bps))sndHdl
	rcv:(void (^ _Nullable)(CGFloat pps, CGFloat bps))rcvHdl;
- (ssize_t)send:(const char *)buf length:(int)len;
- (BOOL)startReceiverWithPort:(in_port_t)rcvPort delegate:(id<CommDelegate>)dlgt;
- (void)invalidate;
@end

NS_ASSUME_NONNULL_END
