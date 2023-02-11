//
//  CommPanel.h
//  Learning is Life
//
//  Created by Tatsuo Unemi on 2023/01/30.
//

@import Cocoa;
@import MetalKit;
#import "Comm.h"
#import "Agent.h"

NS_ASSUME_NONNULL_BEGIN

@interface CommPanel : NSWindowController <NSWindowDelegate>
@end

extern void check_initial_communication(void);
extern BOOL communication_is_running(void);
extern ssize_t send_packet(const char *buf, int length);

typedef enum { TrackRight, TrackFront, TrackLeft, NTrackings } TrackingIndex;

@interface TrackedPoint : NSObject
- (instancetype)initWithPoint:(simd_float2)p;
@property (readonly) simd_float2 point;
@property (readonly) float height;
@end

@interface Tracker : NSObject <CommDelegate>
- (id<MTLBuffer>)trackedPoints:(id<MTLDevice>)device;
- (void)stepTracking;
- (void)addTrackedPoint:(simd_float2)p;
- (void)sendAgentInfo:(AgentStepResult)result;
- (void)sendVectorFieldInfo;
@end

extern Tracker *theTracker;

NS_ASSUME_NONNULL_END
