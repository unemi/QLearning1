//
//  MyViewForCG.h
//  LearningIsLife
//
//  Created by Tatsuo Unemi on 2023/01/05.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN
@class Display, RecordView;
@interface MyViewForCG : NSView
- (instancetype)initWithFrame:(NSRect)frameRect display:(Display *)disp
	infoView:(NSView *)iview recordView:(RecordView *)recordView;
@end

NS_ASSUME_NONNULL_END
