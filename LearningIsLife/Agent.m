//
//  Agent.m
//  LearningIsLife
//
//  Created by Tatsuo Unemi on 2022/12/24.
//

#import "Agent.h"

int MemSize = 256, MemTrials = 32;
float T0 = 0.5, T1 = 0.02, CoolingRate = 0.05,
	InitQValue = 0.5, Gamma = 0.96, Alpha = 0.05, StepsPerSec = 60.;
vector_float4 QTable[NGridH][NGridW];

typedef struct {
	int action;
	simd_int2 s1, s2;
	float reward;
} MemoryStruct;
@interface Memory : NSObject {
	MemoryStruct m;
}
@end
@implementation Memory
- (instancetype)initWithMemory:(MemoryStruct)mem {
	if (!(self = [super init])) return nil;
	m = mem;
	return self;
}
- (MemoryStruct)memoryValue { return m; }
@end

@implementation Agent {
	NSMutableArray<Memory *> *mem;
	float T;
	int steps;
	simd_int2 p;
}
- (instancetype)init {
	if (!(self = [super init])) return nil;
	mem = NSMutableArray.new;
	return self;
}
- (simd_int2)position { return p; }
- (void)restart { p = StartP; }
- (void)reset {
	[mem removeAllObjects];
	for (int i = 0; i < NGridH; i ++)
	for (int j = 0; j < NGridW; j ++)
	for (int k = 0; k < NActs; k ++)
		QTable[i][j][k] = InitQValue;
	T = T0;
	steps = 0;
}
- (int)policy {
	float roulette[NActs], pSum = 0.;
	for (int i = 0; i < NActs; i ++)
		roulette[i] = (pSum += expf(QTable[p.y][p.x][i] / T));
	float r = drand48() * pSum;
	int action;
	for (action = 0; action < NActs; action ++)
		if (r < roulette[action]) break;
	return action;
}
- (float)rewardAt:(simd_int2)pos {
	return (simd_equal(pos, GoalP))? 1.0 : 0.0;
}
- (void)learn:(Memory *)memory {
	float maxQ = -1e10f;
	MemoryStruct mem = memory.memoryValue;
	for (int k = 0; k < NActs; k ++)
		if (maxQ < QTable[mem.s2.y][mem.s2.x][k])
			maxQ = QTable[mem.s2.y][mem.s2.x][k];
	QTable[mem.s1.y][mem.s1.x][mem.action] +=
		(mem.reward + Gamma * maxQ - QTable[mem.s1.y][mem.s1.x][mem.action]) * Alpha;
}
- (AgentStepResult)oneStep {
	if (simd_equal(p, GoalP)) {
		[self restart];
		return AgentReached;
	}
	if (MAX_STEPS > 0)
		T = T0 * powf(T1 / T0, (float)(++ steps) / MAX_STEPS);
	else T += (T1 - T) * CoolingRate / 100;
	AgentStepResult result = AgentStepped;
	int action = [self policy];
	simd_int2 newp = p + Move[action];
	if (newp.x < 0 || newp.x >= NGridW || newp.y < 0 || newp.y >= NGridH
	 || Obstacles[newp.y][newp.x] != 0) { newp = p; result = AgentBumped; }
	float reward = [self rewardAt:newp];
	[mem addObject:[Memory.alloc initWithMemory:(MemoryStruct){action, p, newp, reward}]];
	if (mem.count > MemSize) [mem removeObjectsInRange:(NSRange){0, mem.count - MemSize}];
	for (int i = 0; i < MemTrials; i ++)
		[self learn:mem[lrand48() % mem.count]];
	p = newp;
	return result;
}
@end
