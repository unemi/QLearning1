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
simd_float4 *QTable = NULL;

int ij_to_idx(simd_int2 ij) {
	return ij.y * nGridW + ij.x;
}
int p_to_idx(simd_float2 p) {
	simd_int2 ij = simd_int(p / simd_float(tileSize));
	return ij_to_idx(ij);
}
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
	QTable = realloc(QTable, sizeof(simd_float4) * nGrids);
	[mem removeAllObjects];
	for (int i = 0; i < nGridH; i ++)
	for (int j = 0; j < nGridW; j ++)
	for (int k = 0; k < NActs; k ++)
		QTable[i * nGridW + j][k] = InitQValue;
	T = T0;
	steps = 0;
}
- (int)policy {
	float roulette[NActs], pSum = 0.;
	for (int i = 0; i < NActs; i ++)
		roulette[i] = (pSum += expf(QTable[ij_to_idx(p)][i] / T));
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
	MemoryStruct mem = memory.memoryValue;
	float maxQ = simd_reduce_max(QTable[ij_to_idx(mem.s2)]);
	int idx = ij_to_idx(mem.s1);
	QTable[idx][mem.action] +=
		(mem.reward + Gamma * maxQ - QTable[idx][mem.action]) * Alpha;
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
	if (newp.x < 0 || newp.x >= nGridW || newp.y < 0 || newp.y >= nGridH
	 || Obstacles[ij_to_idx(newp)] != 0) { newp = p; result = AgentBumped; }
	float reward = [self rewardAt:newp];
	[mem addObject:[Memory.alloc initWithMemory:(MemoryStruct){action, p, newp, reward}]];
	if (mem.count > MemSize) [mem removeObjectsInRange:(NSRange){0, mem.count - MemSize}];
	for (int i = 0; i < MemTrials; i ++)
		[self learn:mem[lrand48() % mem.count]];
	p = newp;
	return result;
}
@end
