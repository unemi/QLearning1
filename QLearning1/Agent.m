//
//  Agent.m
//  QLearning1
//
//  Created by Tatsuo Unemi on 2022/12/24.
//

#import "Agent.h"

int MemSize = 256, MemTrials = 32;
float T0 = 0.5, T1 = 0.02, CoolingRate = 0.05,
	InitQValue = 0.5, Gamma = 0.96, Alpha = 0.05;
vector_float4 QTable[NGridH][NGridW];

typedef struct {
    int x, y, action, newx, newy;
    float reward;
} Memory;
@implementation NSValue (MemoryExtension)
+ (instancetype)valueWithMemory:(Memory)value {
	return [self valueWithBytes:&value objCType:@encode(Memory)];
}
- (Memory)memoryValue {
	Memory value;
    [self getValue:&value];
    return value;
}
@end

@implementation Agent {
	NSMutableArray<NSValue *> *mem;
	float T;
	int x, y;
}
- (instancetype)init {
	if (!(self = [super init])) return nil;
	mem = NSMutableArray.new;
	return self;
}
- (void)getPositionX:(int *)xp Y:(int *)yp {
	*xp = x; *yp = y;
}
- (void)restart {
	x = StartP[0]; y = StartP[1];
}
- (void)reset {
	[mem removeAllObjects];
	for (int i = 0; i < NGridH; i ++)
	for (int j = 0; j < NGridW; j ++)
	for (int k = 0; k < NActs; k ++)
		QTable[i][j][k] = InitQValue;
	T = T0;
}
- (int)policy {
	float roulette[NActs], pSum = 0.;
	for (int i = 0; i < NActs; i ++)
		roulette[i] = (pSum += expf(QTable[y][x][i] / T));
	float r = drand48() * pSum;
	int action;
	for (action = 0; action < NActs; action ++)
		if (r < roulette[action]) break;
	return action;
}
- (float)rewardAtX:(int)xx Y:(int)yy {
	return (xx == GoalP[0] && yy == GoalP[1])? 1.0 :
//		(xx == x && yy == y)? -0.01 : 0.0;
	0.0;
}
- (void)learn:(Memory)mem {
	float maxQ = -1e10f;
	for (int k = 0; k < NActs; k ++)
		if (maxQ < QTable[mem.newy][mem.newx][k])
			maxQ = QTable[mem.newy][mem.newx][k];
	QTable[mem.y][mem.x][mem.action] +=
		(mem.reward + Gamma * maxQ - QTable[mem.y][mem.x][mem.action]) * Alpha;
}
- (void)oneStep {
	if (x == GoalP[0] && y == GoalP[1]) {
		T += (T1 - T) * CoolingRate;
		[self restart];
		return;
	}
	int action = [self policy];
	int newx = x + Move[action][0];
	int newy = y + Move[action][1];
	if (newx < 0 || newx >= NGridW || newy < 0 || newy >= NGridH
	 || Obstacles[newy][newx] != 0) { newx = x; newy = y; }
	float reward = [self rewardAtX:newx Y:newy];
	[mem addObject:[NSValue valueWithMemory:(Memory){x, y, action, newx, newy, reward}]];
	if (mem.count > MemSize) [mem removeObjectsInRange:(NSRange){0, mem.count - MemSize}];
	for (int i = 0; i < MemTrials; i ++)
		[self learn:mem[lrand48() % mem.count].memoryValue];
	x = newx; y = newy;
}
@end
