//
//  Agent.h
//  LearningIsLife
//
//  Created by Tatsuo Unemi on 2022/12/24.
//

@import Cocoa;
#import "AppDelegate.h"

NS_ASSUME_NONNULL_BEGIN

typedef enum {
	AgentStepped, AgentReached, AgentBumped
} AgentStepResult;

extern int MemSize, MemTrials;
extern float T0, T1, CoolingRate, InitQValue, Gamma, Alpha, StepsPerSec;
extern vector_float4 QTable[NGridH][NGridW];

@interface Agent : NSObject
- (simd_int2)position;
- (void)reset;
- (void)restart;
- (AgentStepResult)oneStep;
@end

NS_ASSUME_NONNULL_END
