//
//  InteractionPanel.h
//  Learning is Life
//
//  Created by Tatsuo Unemi on 2023/06/25.
//

#import <Cocoa/Cocoa.h>
@import simd;

NS_ASSUME_NONNULL_BEGIN
extern float HandMinSpeed, HandMaxSpeed, HandMinEffect, HandMaxEffect,
	ConfidenceLow, ConfidenceHigh,
	obsGrow, obsMaxH, obsThrsh, obsMaxSpeed;
extern void affect_hand_motion(simd_float4 *qvalues, simd_float2 dp, float len, float speed);
@interface InteractionPanel : NSWindowController <NSWindowDelegate> {
	IBOutlet NSTextField *minSpdDgt, *maxSpdDgt, *minEfcDgt, *maxEfcDgt,
		*cnfdncLowDgt, *cnfdncHighDgt,
		*obsGrwDgt, *obsMaxHDgt, *obsThrDgt, *obsMxSpdDgt;
	IBOutlet NSButton *svAsDfltBtn;
}
- (void)setupControls;
+ (NSInteger)initParams:(NSInteger)fdBit fdBits:(UInt64 *)fd;
@end

NS_ASSUME_NONNULL_END
