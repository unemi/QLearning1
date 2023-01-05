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
typedef struct {
  vector_float2 p, v, f;
  int life;
} Particle;

extern int NParticles, LifeSpan;
extern float Mass, Friction, StrokeLength, StrokeWidth, MaxSpeed;
extern NSColor * _Nonnull colBackground, * _Nonnull colObstacles,
	* _Nonnull colAgent, * _Nonnull colGridLines,
	* _Nonnull colSymbols, * _Nonnull colParticles;
extern PTCLColorMode ptclColorMode;
extern PTCLDrawMethod ptclDrawMethod;
extern vector_float4 col_to_vec(NSColor * _Nonnull col);
extern vector_float4 ptcl_hsb_color(void);
extern vector_float4 ptcl_rgb_color(Particle * _Nonnull p, vector_float4 hsba, float maxSpeed);
extern vector_float2 particle_size(Particle * _Nonnull p);
extern simd_float3x3 trans_matrix(Particle * _Nonnull p);

NS_ASSUME_NONNULL_BEGIN

@interface Display : NSObject<MTKViewDelegate>
- (instancetype)initWithView:(MTKView *)view agent:(Agent *)a;
- (void)reset;
- (void)oneStep;
- (Agent *)agent;
- (Particle *)particles;
- (int)nParticles;
@end

NS_ASSUME_NONNULL_END
