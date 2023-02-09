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
#define DST_PKT_PER_SEC 1

extern void in_main_thread(void (^block)(void));
extern void error_msg(NSObject *obj, NSWindow * _Nullable window);
extern void err_msg(NSString *msg, OSStatus err, BOOL isFatal);

@protocol CommDelegate
- (void)receive:(char *)buf length:(ssize_t)length;
@end

@interface Comm : NSObject
@property (readonly) BOOL valid, rcvRunning;
@property (readonly) NSString *myAddress, *myBroadcastAddress, *senderAddress;
@property NSString *destinationAddress;
@property UInt16 destinationPort;
@property (readonly) in_port_t receiverPort;
- (void)setStatHandlersSnd:(void (^ _Nullable)(ssize_t nBytes))sndHdl
	rcv:(void (^ _Nullable)(ssize_t nBytes))rcvHdl;
- (ssize_t)send:(const char *)buf length:(int)len;
- (BOOL)startReceiverWithPort:(UInt16)rcvPort delegate:(id<CommDelegate>)dlgt;
- (void)stopReceiver;
- (void)invalidate;
@end

NS_ASSUME_NONNULL_END
