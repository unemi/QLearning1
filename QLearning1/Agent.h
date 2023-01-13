//
//  Agent.h
//  QLearning1
//
//  Created by Tatsuo Unemi on 2022/12/24.
//

#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"

NS_ASSUME_NONNULL_BEGIN

typedef enum {
	AgentStepped, AgentReached, AgentBumped
} AgentStepResult;

extern int MemSize, MemTrials;
extern float T0, T1, CoolingRate, InitQValue, Gamma, Alpha;
extern vector_float4 QTable[NGridH][NGridW];

@interface Agent : NSObject
- (void)getPositionX:(int *)xp Y:(int *)yp;
- (void)reset;
- (void)restart;
- (AgentStepResult)oneStep;
@end

NS_ASSUME_NONNULL_END
