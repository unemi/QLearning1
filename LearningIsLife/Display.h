//
//  Display.h
//  LearningIsLife
//
//  Created by Tatsuo Unemi on 2022/12/24.
//

@import Cocoa;
@import MetalKit;
@class Agent;
#import "CommonTypes.h"

typedef struct {
	DisplayMode displayMode;
	PTCLColorMode colorMode;
	PTCLShapeMode shapeMode;
	int nPtcls;
} DisplaySetups;
typedef struct {
  simd_float2 p, v;
  int life;
} Particle;
typedef id<MTLRenderCommandEncoder> RCE;

#define N_VECTOR_GRID 5
#define N_VECTORS (nActiveGrids*N_VECTOR_GRID*N_VECTOR_GRID)
#define N_MAX_VECTORS (nGrids*N_VECTOR_GRID*N_VECTOR_GRID)
#define NVERTICES_ARROW 9
// Dimensions of arrow shape
#define AR_TAIL_Y .4
#define AR_HEAD_X 0.

extern int NParticles, LifeSpan;
extern float Mass, Friction, StrokeLength, StrokeWidth, MaxSpeed;
extern NSColor * _Nonnull colBackground, * _Nonnull colObstacles,
	* _Nonnull colAgent, * _Nonnull colGridLines,
	* _Nonnull colSymbols, * _Nonnull colParticles, * _Nonnull colTracking;
extern PTCLColorMode ptclColorMode;
extern PTCLShapeMode ptclShapeMode;
extern void add_observer(NSString * _Nonnull noteName,
	void (^ _Nonnull block)(NSNotification * _Nonnull));
extern void init_default_colors(void);
extern void draw_in_bitmap(NSBitmapImageRep * _Nonnull imgRep,
	void (^ _Nonnull block)(NSBitmapImageRep * _Nonnull bm));
extern simd_float4 ptcl_hsb_color(void);
extern simd_float4 ptcl_rgb_color(Particle * _Nonnull p, simd_float4 hsba, float maxSpeed);
extern simd_float2 particle_size(Particle * _Nonnull p);
extern simd_float3x3 particle_tr_mx(Particle * _Nonnull p);
extern void fill_circle_at(RCE _Nonnull rce, simd_float2 center, float radius, int nEdges);

NS_ASSUME_NONNULL_BEGIN

@interface Display : NSObject<MTKViewDelegate>
@property (readonly) Agent *agent;
@property (readonly) NSMutableData *particleMem;
@property (readonly) simd_float2 *arrowVec;
@property (readonly) simd_float4 *arrowCol;
@property (readonly) CGFloat FPS;
- (instancetype)initWithView:(MTKView *)view agent:(Agent *)a;
- (int)nPtcls;
- (DisplayMode)displayMode;
- (void)setDisplayMode:(DisplayMode)newMode;
- (void)reset;
- (void)oneStep;
- (void)clearObsPCache;
- (NSBitmapImageRep *)imageBitmapWithSize:(NSSize)size scaleFactor:(CGFloat)scaleFactor
	drawBlock:(void (^)(NSBitmapImageRep *bm))block;
@end

NS_ASSUME_NONNULL_END
