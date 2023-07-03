//
//  SpeedColPanel.h
//  Learning is Life
//
//  Created by Tatsuo Unemi on 2023/06/29.
//

#import <Cocoa/Cocoa.h>
@import simd;
#import "SheetExtension.h"

NS_ASSUME_NONNULL_BEGIN
typedef struct { float x; simd_float4 hsb; } SpeedColor;
extern NSString *keySpeedColors;
extern NSInteger nSpeedColors;
extern SpeedColor *speedColors;
extern int FDBTSpdCol;
extern NSData *spdColUD, *spdColFD;
extern BOOL spdcol_is_equal_to(NSData *data);
extern simd_float4 grade_to_hsb(float grade);
extern NSData *data_from_spdCols(void);
extern void spdCols_from_data(NSData *data);

@protocol GradientBarDelegate
@end
@interface GradientBar : NSControl {
	IBOutlet NSButton *addBtn, *removeBtn;
	IBOutlet NSSlider *alphaSld;
}
@property IBOutlet id<GradientBarDelegate> delegate;
@end
@interface SpeedColPanel : NSWindowController
	<NSWindowDelegate, GradientBarDelegate> {
	IBOutlet GradientBar *gradientBar;
	IBOutlet NSButton *rvtUDBtn, *rvtFDBtn;
}
- (void)setupControls;
+ (void)initParamDefaults;
+ (NSInteger)initParams:(NSInteger)fdBit fdBits:(UInt64 *)fdB;
@end

NS_ASSUME_NONNULL_END
