//
//  Display.h
//  QLearning1
//
//  Created by Tatsuo Unemi on 2022/12/24.
//

@import Cocoa;
@import MetalKit;
@class Agent;
typedef enum { PTCLconstColor, PTCLangleColor, PTCLspeedColor } PTCLColorMode;
typedef enum { PTCLbyRectangles, PTCLbyTriangles, PTCLbyLines } PTCLDrawMethod;
extern int NParticles, LifeSpan;
extern float Mass, Friction, StrokeLength, StrokeWidth, MaxSpeed;
extern NSColor * _Nonnull colBackground, * _Nonnull colObstacles,
	* _Nonnull colAgent, * _Nonnull colGridLines,
	* _Nonnull colSymbols, * _Nonnull colParticles;
extern PTCLColorMode ptclColorMode;
extern PTCLDrawMethod ptclDrawMethod;
extern vector_float4 col_to_vec(NSColor * _Nonnull col);

NS_ASSUME_NONNULL_BEGIN

@interface Display : NSObject<MTKViewDelegate>
- (instancetype)initWithView:(MTKView *)view agent:(Agent *)a;
- (void)reset;
- (void)oneStep;
@end

NS_ASSUME_NONNULL_END
