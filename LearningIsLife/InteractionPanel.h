//
//  InteractionPanel.h
//  Learning is Life
//
//  Created by Tatsuo Unemi on 2023/06/25.
//

#import <Cocoa/Cocoa.h>
@import simd;

NS_ASSUME_NONNULL_BEGIN
typedef struct { NSString *key; float *var, fd, ud; } InteractionParam;
extern float obsGrow, obsMaxH, obsThrsh, obsMaxSpeed;
extern void affect_hand_motion(simd_float4 *qvalues, simd_float2 dp, float len, float speed);
@interface InteractionPanel : NSWindowController <NSWindowDelegate> {
	IBOutlet NSTextField *minSpdDgt, *maxSpdDgt, *minEfcDgt, *maxEfcDgt,
		*obsGrwDgt, *obsMaxHDgt, *obsThrDgt, *obsMxSpdDgt;
	IBOutlet NSButton *svAsDfltBtn;
}
+ (void)initParams;
@end

NS_ASSUME_NONNULL_END
