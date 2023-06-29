//
//  InteractionPanel.m
//  Learning is Life
//
//  Created by Tatsuo Unemi on 2023/06/25.
//

#import "InteractionPanel.h"

float minSpeed = 2, maxSpeed = 4, minEffect = 1, maxEffect = 5,
	obsGrow = 20, obsMaxH = 300, obsThrsh = 20, obsMaxSpeed = 1;
InteractionParam interactionParams[] = {
	{ @"handMinSpeed", &minSpeed },
	{ @"HandMaxSpeed", &maxSpeed },
	{ @"handMinEffect", &minEffect },
	{ @"handMaxEffect", &maxEffect },
	{ @"obstacleGrowth", &obsGrow },
	{ @"obstacleMaxHeight", &obsMaxH },
	{ @"obstacleThreshold", &obsThrsh },
	{ @"obstacleMaxHandSpeed", &obsMaxSpeed },
	{ nil }
};
void affect_hand_motion(simd_float4 *qvalues, simd_float2 dp, float len, float speed) {
	if (speed < minSpeed || speed > maxSpeed) return;
	float effect = (speed - minSpeed) / (maxSpeed - minSpeed)
		* (maxEffect - minEffect) + minEffect;
	simd_float2 e = dp * (effect * .01 / len);
	simd_float4 a = (simd_float4){ e.y, e.x, -e.y, -e.x };	// up, right, down, left
	for (NSInteger i = 0; i < 4; i ++) {
		if (a[i] > 0) (*qvalues)[i] += (1. -  (*qvalues)[i]) * a[i];
		else (*qvalues)[i] *= (1. + a[i]);
	}
}
@interface InteractionPanel () {
	NSArray<NSTextField *> *digits;
	NSUndoManager *undoManager;
}
@end
@implementation InteractionPanel
- (NSString *)windowNibName { return @"InteractionPanel"; }
- (void)windowDidLoad {
	[super windowDidLoad];
	if (self.window == nil) return;
	undoManager = NSUndoManager.new;
    digits = @[minSpdDgt, maxSpdDgt, minEfcDgt, maxEfcDgt,
		obsGrwDgt, obsMaxHDgt, obsThrDgt, obsMxSpdDgt];
    for (NSInteger i = 0; i < digits.count; i ++) {
		digits[i].floatValue = *interactionParams[i].var;
		digits[i].target = self;
		digits[i].action = @selector(changeDigits:);
	}
}
+ (void)initParams {
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	NSNumber *num;
	for (InteractionParam *p = interactionParams; p->key; p ++) {
		p->fd = p->ud = *p->var;
		if ((num = [ud objectForKey:p->key])) *p->var = p->ud = num.floatValue;
	}
}
- (IBAction)changeDigits:(NSTextField *)dgt {
	NSInteger idx = [digits indexOfObject:dgt];
	if (idx == NSNotFound) return;
	float orgValue = *interactionParams[idx].var;
	[undoManager registerUndoWithTarget:self handler:^(id _Nullable target) {
		dgt.floatValue = orgValue;
		[dgt sendAction:dgt.action to:dgt.target];
	}];
	*interactionParams[idx].var = dgt.floatValue;
	BOOL isAsUd = YES;
	for (InteractionParam *p = interactionParams; p->key; p ++)
		if (*p->var != p->ud) { isAsUd = NO; break; }
	svAsDfltBtn.enabled = !isAsUd;
}
- (IBAction)saveAsDefaults:(id)sender {
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	for (InteractionParam *p = interactionParams; p->key; p ++)
		[ud setFloat:*p->var forKey:p->key];
	svAsDfltBtn.enabled = NO;
}
//
- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window {
	return undoManager;
}
@end
