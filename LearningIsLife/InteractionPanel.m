//
//  InteractionPanel.m
//  Learning is Life
//
//  Created by Tatsuo Unemi on 2023/06/25.
//

#import "InteractionPanel.h"
#import "SheetExtension.h"
#import "AppDelegate.h"
#import "ControlPanel.h"

float HandMinSpeed = 2, HandMaxSpeed = 4, HandMinEffect = 1, HandMaxEffect = 5,
	ConfidenceLow = 75, ConfidenceHigh = 90,
	obsGrow = 20, obsMaxH = 300, obsThrsh = 20, obsMaxSpeed = 1;
int FDBTInteract = 0;
#define NIntrctParams 8
FloatVarInfo *fVarInfo;
void affect_hand_motion(simd_float4 *qvalues, simd_float2 dp, float len, float speed) {
	if (speed < HandMinSpeed || speed > HandMaxSpeed) return;
	float confdnc = simd_length(qvalues->xy - qvalues->zw);
	if (confdnc > ConfidenceHigh * .01) return;
	float effect = (speed - HandMinSpeed) / (HandMaxSpeed - HandMinSpeed)
		* (HandMaxEffect - HandMinEffect) + HandMinEffect;
	simd_float2 e = dp * (effect * .01 / len);
	if (confdnc > ConfidenceLow * .01)
		e *= (ConfidenceHigh -  confdnc * 100.) / (ConfidenceHigh - ConfidenceLow);
	simd_float4 a = (simd_float4){ e.y, e.x, -e.y, -e.x };	// up, right, down, left
	for (NSInteger i = 0; i < 4; i ++) {
		if (a[i] > 0) (*qvalues)[i] += (1. -  (*qvalues)[i]) * a[i];
		else (*qvalues)[i] *= (1. + a[i]);
	}
}
@interface InteractionPanel () {
	NSArray<NSTextField *> *digits;
	NSUndoManager *undoManager;
	ControlPanel *ctrlPnl;
}
@end
@implementation InteractionPanel
- (NSString *)windowNibName { return @"InteractionPanel"; }
- (void)setupControls {
    for (NSInteger i = 0; i < digits.count; i ++)
		digits[i].floatValue = *fVarInfo[i].v;
}
- (void)windowDidLoad {
	[super windowDidLoad];
	if (self.window == nil) return;
	undoManager = NSUndoManager.new;
    digits = @[minSpdDgt, maxSpdDgt, minEfcDgt, maxEfcDgt,
		cnfdncLowDgt, cnfdncHighDgt,
		obsGrwDgt, obsMaxHDgt, obsThrDgt, obsMxSpdDgt];
    for (NSInteger i = 0; i < digits.count; i ++) {
		digits[i].target = self;
		digits[i].action = @selector(changeDigits:);
	}
}
+ (NSInteger)initParams:(NSInteger)fdBit fdBits:(UInt64 *)fdB {
	for (fVarInfo = FloatVars; fVarInfo->key != nil; fVarInfo ++)
		if (fVarInfo->v == &HandMinSpeed) break;
	FDBTInteract = (int)fdBit;
	for (NSInteger i = 0; i < NIntrctParams; i ++) {
		if (*fVarInfo[i].v != fVarInfo[i].fd) *fdB |= 1 << (fdBit + i);
	}
	return fdBit + NIntrctParams;
}
- (IBAction)changeDigits:(NSTextField *)dgt {
	NSInteger idx = [digits indexOfObject:dgt];
	if (idx == NSNotFound) return;
	FloatVarInfo *info = fVarInfo + idx;
	float orgValue = *info->v, newValue = dgt.floatValue;
	if (orgValue == newValue) return;
	[undoManager registerUndoWithTarget:self handler:^(id _Nullable target) {
		dgt.floatValue = orgValue;
		[dgt sendAction:dgt.action to:dgt.target];
	}];
	*info->v = newValue;
	if (ctrlPnl == nil) ctrlPnl = (ControlPanel *)self.window.sheetParent.delegate;
	[ctrlPnl checkFDBits:FDBTInteract + idx
		fd:newValue == info->fd ud:newValue == info->ud];
}
//
- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window {
	return undoManager;
}
@end
