//
//  LogoDrawer.h
//  QLearning1
//
//  Created by Tatsuo Unemi on 2023/01/10.
//
@import MetalKit;

@interface LogoDrawerCG : NSObject
- (void)drawByCGinRect:(NSRect)rect;
@end
@interface LogoDrawerMTL : NSObject
- (void)drawByMTL:(id<MTLRenderCommandEncoder>)rce inRect:(NSRect)rect;
@end
