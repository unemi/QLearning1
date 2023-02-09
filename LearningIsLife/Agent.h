//
//  Agent.h
//  LearningIsLife
//
//  Created by Tatsuo Unemi on 2022/12/24.
//

@import Cocoa;
#import "AppDelegate.h"

NS_ASSUME_NONNULL_BEGIN

extern int ij_to_idx(simd_int2 ij);
extern int p_to_idx(simd_float2 p);

typedef enum {
	AgentStepped, AgentReached, AgentBumped
} AgentStepResult;

extern int MemSize, MemTrials;
extern float T0, T1, CoolingRate, InitQValue, Gamma, Alpha, StepsPerSec;
extern simd_float4 *QTable;

@interface Agent : NSObject
- (simd_int2)position;
- (void)reset;
- (void)restart;
- (AgentStepResult)oneStep;
@end

NS_ASSUME_NONNULL_END
