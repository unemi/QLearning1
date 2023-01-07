//
//  MyViewForCG.h
//  QLearning1
//
//  Created by Tatsuo Unemi on 2023/01/05.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN
@class Display;
@interface MyViewForCG : NSView
- (instancetype)initWithFrame:(NSRect)frameRect display:(Display *)disp;
@end

NS_ASSUME_NONNULL_END
