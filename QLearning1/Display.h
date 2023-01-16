//
//  Display.h
//  QLearning1
//
//  Created by Tatsuo Unemi on 2022/12/24.
//

@import Cocoa;
@import MetalKit;
@class Agent;
typedef enum { DispParticle, DispVector, DispQValues } DisplayMode;
typedef enum { PTCLconstColor, PTCLangleColor, PTCLspeedColor } PTCLColorMode;
typedef enum { PTCLbyRectangles, PTCLbyTriangles, PTCLbyLines } PTCLDrawMethod;
typedef struct {
  vector_float2 p, v, f;
  int life;
} Particle;
typedef id<MTLRenderCommandEncoder> RCE;

#define N_VECTOR_GRID 5
#define N_VECTORS (NActiveGrids*N_VECTOR_GRID*N_VECTOR_GRID)
#define NVERTICES_ARROW 9
// Dimensions of arrow shape
#define AR_TAIL_Y .4
#define AR_HEAD_X 0.

extern int NParticles, LifeSpan;
extern float Mass, Friction, StrokeLength, StrokeWidth, MaxSpeed;
extern NSColor * _Nonnull colBackground, * _Nonnull colObstacles,
	* _Nonnull colAgent, * _Nonnull colGridLines,
	* _Nonnull colSymbols, * _Nonnull colParticles;
extern PTCLColorMode ptclColorMode;
extern PTCLDrawMethod ptclDrawMethod;
extern void init_default_colors(void);
extern void draw_in_bitmap(NSBitmapImageRep * _Nonnull imgRep,
	void (^ _Nonnull block)(NSBitmapImageRep * _Nonnull bm));
extern vector_float4 ptcl_hsb_color(void);
extern vector_float4 ptcl_rgb_color(Particle * _Nonnull p, vector_float4 hsba, float maxSpeed);
extern vector_float2 particle_size(Particle * _Nonnull p);
extern simd_float3x3 particle_tr_mx(Particle * _Nonnull p);
extern void fill_circle_at(RCE _Nonnull rce, vector_float2 center, float radius, int nEdges);

NS_ASSUME_NONNULL_BEGIN

@interface Display : NSObject<MTKViewDelegate>
@property (readonly) Agent *agent;
@property (readonly) Particle *particles;
@property (readonly) int nPtcls;
@property (readonly) vector_float2 *arrowVec;
@property (readonly) vector_float4 *arrowCol;
@property (nonatomic) DisplayMode displayMode;
- (instancetype)initWithView:(MTKView *)view agent:(Agent *)a;
- (void)reset;
- (void)oneStep;
- (NSBitmapImageRep *)imageBitmapWithSize:(NSSize)size scaleFactor:(CGFloat)scaleFactor
	drawBlock:(void (^)(NSBitmapImageRep *bm))block;
@end

NS_ASSUME_NONNULL_END
