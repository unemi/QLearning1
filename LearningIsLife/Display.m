//
//  Display.m
//  LearningIsLife
//
//  Created by Tatsuo Unemi on 2022/12/24.
//

#include <sys/sysctl.h>
#import "ControlPanel.h"
#import "CommPanel.h"	// for Tracked points
#import "Display.h"
#import "MainWindow.h"
#import "Agent.h"
#import "VecTypes.h"
#import "LogoDrawer.h"
#define NV_GRID ((nGridW + nGridH - 2) * 2)
#define NTHREADS nCores

#define THREADS_PRE(tp,n) tp unit = (n) / NTHREADS,\
	mm = (n) - unit * NTHREADS, nThreads = (unit == 0)? mm : NTHREADS, idxStart = 0;
#define THREADS_ST(tp) tp nn = (i < mm)? unit + 1 : unit;
#define THREADS_DO if (i >= nThreads - 1) block();\
	[opeQue addOperationWithBlock:block];\
	idxStart += nn;

int NParticles = 120000, LifeSpan = 80;
float Mass = 2., Friction = 0.9, StrokeLength = 0.2, StrokeWidth = .01, MaxSpeed = 0.05,
	FadeoutSec = 5.;
NSColor *colBackground, *colObstacles, *colAgent,
	*colGridLines, *colSymbols, *colParticles, *colTracking, *colInfoFG;
PTCLColorMode ptclColorMode = PTCLconstColor;
PTCLShapeMode ptclShapeMode = PTCLbyLines;
enum { FailPtclMem, FailColBuf, FailVxBuf, FailArrowMem };
static int nCores;
static BOOL isARM;
static NSString *keyAdjustmentCorners = @"AdjustmentCorners";
unsigned long current_time_us(void) {
	static long startTime = -1;
	struct timeval tv;
	gettimeofday(&tv, NULL);
	if (startTime < 0) startTime = tv.tv_sec;
	return (tv.tv_sec - startTime) * 1000000L + tv.tv_usec;
}
void add_observer(NSString *noteName, void (^block)(NSNotification * _Nonnull)) {
	[NSNotificationCenter.defaultCenter addObserverForName:noteName
		object:NSApp queue:nil usingBlock:block];
}
static NSColor *color_with_comp(CGFloat *comp) {
	return [NSColor colorWithColorSpace:NSColorSpace.genericRGBColorSpace
		components:comp count:4];
}
void init_default_colors(void) {
	colBackground = color_with_comp((CGFloat []){0., 0., 0., 1.});
	colObstacles = color_with_comp((CGFloat []){.3, .3, .3, 1.});
	colAgent = color_with_comp((CGFloat []){.3, .3, .3, 1.});
	colGridLines = color_with_comp((CGFloat []){.5, .5, .5, 1.});
	colSymbols = color_with_comp((CGFloat []){.7, .7, .7, 1.});
	colParticles = color_with_comp((CGFloat []){1., 1., 1., .1});
	colTracking = color_with_comp((CGFloat []){1., 1., 1., .667});
	colInfoFG = color_with_comp((CGFloat []){1., 1., 1., .8});
}
static simd_float4 col_to_vec(NSColor * _Nonnull col) {
	CGFloat c[4] = {0, 0, 0, 1};
	[[col colorUsingColorSpace:NSColorSpace.genericRGBColorSpace]
		getComponents:c];
	return (simd_float4){c[0], c[1], c[2], c[3]};
}
void draw_in_bitmap(NSBitmapImageRep * _Nonnull imgRep,
	void (^ _Nonnull block)(NSBitmapImageRep * _Nonnull bm)) {
	NSGraphicsContext *orgCtx = NSGraphicsContext.currentContext;
	NSGraphicsContext.currentContext =
		[NSGraphicsContext graphicsContextWithBitmapImageRep:imgRep];
	NSGraphicsContext.currentContext.shouldAntialias = YES;
	block(imgRep);
	NSGraphicsContext.currentContext = orgCtx;
}
static NSBitmapImageRep *create_rgb_bitmap(NSUInteger pixW, NSUInteger pixH,
	unsigned char * _Nullable * _Nullable planes) {
	return [NSBitmapImageRep.alloc initWithBitmapDataPlanes:planes
		pixelsWide:pixW pixelsHigh:pixH bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
		isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace
		bitmapFormat:NSBitmapFormatThirtyTwoBitLittleEndian
		bytesPerRow:pixW * 4 bitsPerPixel:32];
}
#define USE_FORCE_GRID
#ifdef USE_FORCE_GRID
#define FF_N_GRID 20
static simd_float2 *ForceGrid = NULL;
static int idx_of_forceGrid(simd_int2 idx) {
	return idx.y * nGridW * FF_N_GRID + idx.x;
}
//#define INTERPORATE
#ifdef INTERPORATE
static simd_float2 particle_force(Particle *p) {
	simd_float2 q = p->p / simd_float(tileSize) * FF_N_GRID, qF = floor(q);
	simd_int2 idx = simd_int(qF);
	float d = simd_distance_squared(qF + .5, q);
	if (d < 1e-12f) return ForceGrid[idx_of_forceGrid(idx)];
	simd_float2 f = ForceGrid[idx_of_forceGrid(idx)] / d;
	float wSum = 1. / d;
	simd_float2 r = q - qF;
	simd_int2 dx = {1, 0}, dy = {0, 1};
	if (r.y < .5 && idx.y > 0) {
		d = simd_distance_squared(qF + (simd_float2){.5, -.5}, q);
		f += ForceGrid[idx_of_forceGrid(idx - dy)] / d; wSum += 1. / d;
	}
	if (r.y >= .5 && idx.y < nGridH*FF_N_GRID-1) {
		d = simd_distance_squared(qF + (simd_float2){.5, 1.5}, q);
		f += ForceGrid[idx_of_forceGrid(idx + dy)] / d; wSum += 1. / d;
	}
	if (r.x < .5 && idx.x > 0) {
		d = simd_distance_squared(qF + (simd_float2){-.5, .5}, q);
		f += ForceGrid[idx_of_forceGrid(idx - dx)] / d; wSum += 1. / d;
	}
	if (r.x >= .5 && idx.x < nGridW*FF_N_GRID-1) {
		d = simd_distance_squared(qF + (simd_float2){1.5, .5}, q);
		f += ForceGrid[idx_of_forceGrid(idx + dx)] / d; wSum += 1. / d;
	}
	return f / wSum;
}
#else
static simd_float2 particle_force(Particle *p) {
	simd_int2 idx = simd_int(p->p / simd_float(tileSize) * FF_N_GRID);
	return ForceGrid[idx_of_forceGrid(idx)];
}
#endif
#else
static simd_float2 particle_force(Particle *p) {
	simd_float2 q = p->p / simd_float(tileSize), qF = floor(q);
	simd_int2 idx = simd_int(qF);
	float w = simd_distance_squared(qF + .5, q);
	if (w < 1e-12f) {
		simd_float4 Q = QTable[ij_to_idx(idx)];
		return (simd_float2){Q.y - Q.w, Q.x - Q.z};
	}
	float wsum = 0.;
	simd_float2 f = 0.;
	simd_int2 idxF = simd_max(0, idx - 1),
		idxT = simd_min((simd_int2){nGridW, nGridH}, idx + 2);
	for (idx.x = idxF.x; idx.x < idxT.x; idx.x ++)
	for (idx.y = idxF.y; idx.y < idxT.y; idx.y ++)
	if (ObsHeight[ij_to_idx(idx)] == 0) {
		w = simd_distance_squared(simd_float(idx) + .5, q);
		simd_float4 Q = QTable[ij_to_idx(idx)];
		f += (simd_float2){Q.y - Q.w, Q.x - Q.z} / w;
		wsum += 1. / w;
	}
	return f /= wsum;
}
#endif
static void particle_reset(Particle *p, BOOL isRandom) {
	p->p = (simd_float(FieldP[(nGridsInUse == 0)? 0 : lrand48() % nGridsInUse])
		+ (simd_float2){drand48(), drand48()}) * simd_float(tileSize);
	simd_float2 f = particle_force(p);
	float v = simd_length(f);
	if (v < 1e-8) {
		float th = drand48() * M_PI * 2.;
		p->v = (simd_float2){cosf(th), sinf(th)} * .01;
	} else p->v = f / v * .01;
	p->life = isRandom? lrand48() % LifeSpan : LifeSpan;
}
static void particle_step(Particle *p, simd_float2 f) {
	p->v = (p->v + f / Mass) * Friction;
	float v = simd_length(p->v);
	if (v > tileSize.x * MaxSpeed)
		p->v /= v * tileSize.x * MaxSpeed;
	p->p += p->v;
}
@implementation Display {
	MTKView *view;
	NSOperationQueue *opeQue;
	id<MTLRenderPipelineState> shapePSO, texPSO, texColPSO, tpPSO;
	id<MTLCommandQueue> commandQueue;
	id<MTLTexture> StrSTex, StrGTex, equLTex, equPTex, handTex,
		adjustKeysTex, adjustSavedTex, adjustTex;
	id<MTLBuffer> vxBuf, colBuf, vxBufD[2], colBufD[2];
	NSInteger vxBufIndex, colBufIndex;
	NSMutableDictionary *symbolAttr;
	LogoDrawerMTL *logoDrawer;
	NSLock *loopLock;
	simd_uint2 viewportSize;
	DisplaySetups setups;
	float maxSpeed;
	unsigned long time_us, dispCnt, fadeStart;
	void (^fadeEndHandler)(void);
	simd_int2 *obsP, *obsMem;
	int nObs;
// for full screen
	NSView * __weak infoView;
	NSBitmapImageRep *infoViewCacheBM;
	id<MTLTexture> infoViewTex;
	simd_float4x2 corners, savedCorners;
	simd_float3x3 adjustMx, adjustMxI;
	NSTimer *savedMsgTimer;
	BOOL cornersWereModified;
}
- (int)nPtcls { return setups.nPtcls; }
- (void)startFading:(void (^)(void))handler {
	fadeStart = current_time_us();
	fadeEndHandler = handler;
}
- (DisplayMode)displayMode { return setups.displayMode; }
- (id<MTLTexture>)textureDrawnBy:(void (^)(NSBitmapImageRep *bm))block
	size:(NSSize)size scaleFactor:(CGFloat)sclFctr {
//	sclFctr *= view.sampleCount * viewportSize.y / PTCLMaxY;
	sclFctr *= (CGFloat)viewportSize.y / PTCLMaxY;
	NSInteger pixW = ceil(size.width * sclFctr), pixH = ceil(size.height * sclFctr);
	NSBitmapImageRep *imgRep = create_rgb_bitmap(pixW, pixH, NULL);
	draw_in_bitmap(imgRep, block);
	MTLTextureDescriptor *texDesc = [MTLTextureDescriptor
		texture2DDescriptorWithPixelFormat:view.colorPixelFormat
		width:pixW height:pixH mipmapped:NO];
	id<MTLTexture> tex = [view.device newTextureWithDescriptor:texDesc];
	[tex replaceRegion:MTLRegionMake2D(0, 0, pixW, pixH)
		mipmapLevel:0 withBytes:imgRep.bitmapData bytesPerRow:imgRep.bytesPerRow];
	return tex;
}
- (id<MTLTexture>)texFromStr:(NSString *)str attribute:(NSDictionary *)attr {
	NSSize size = [str sizeWithAttributes:attr];
	return [self textureDrawnBy:^(NSBitmapImageRep *bm) {
		[[NSColor colorWithWhite:0. alpha:0.] setFill];
		[NSBezierPath fillRect:(NSRect){0, 0, bm.size}];
		NSAffineTransform *trs = NSAffineTransform.transform;
		[trs scaleBy:bm.size.height / size.height];
		[trs concat];
		[str drawAtPoint:(NSPoint){0., 0.} withAttributes:attr];
	} size:size scaleFactor:1.];
}
- (id<MTLTexture>)texFromImageName:(NSString *)name
	rotate:(BOOL)rotate width:(CGFloat)width {
	NSImage *image = [NSImage imageNamed:name];
	NSSize sz = image.size;
	return [self textureDrawnBy:^(NSBitmapImageRep *bm) {
		NSSize bmSz = bm.size;
		[[NSColor colorWithWhite:0. alpha:0.] setFill];
		[NSBezierPath fillRect:(NSRect){0, 0, bmSz}];
		if (rotate) {
			NSAffineTransform *trs = NSAffineTransform.transform;
			[trs translateXBy:0. yBy:bmSz.height];
			[trs rotateByRadians:M_PI / -2.];
			[trs concat];
			CGFloat w = bmSz.width; bmSz.width = bmSz.height; bmSz.height = w;
		}
		[image drawInRect:(NSRect){0., 0., bmSz}];
#ifdef DEBUG
NSLog(@"texture %@ %ldx%ld pixels", name, bm.pixelsWide, bm.pixelsHigh);
#endif
	} size:(NSSize){sz.height, sz.width} scaleFactor:
		(width == 0)? 1. : width / sz.width];
}
- (id<MTLTexture>)equTexWithName:(NSString *)name {
	return [self texFromImageName:name rotate:YES width:tileSize.x * 2.8];
}
- (id<MTLTexture>)texWithName:(NSString *)name {
	return [self texFromImageName:name rotate:NO width:0];
}
- (void)setupSymbolTex {
	if (symbolAttr == nil) symbolAttr = [NSMutableDictionary dictionaryWithObject:
		[NSFont userFontOfSize:tileSize.x / 2 * view.sampleCount]
		forKey:NSFontAttributeName];
	StrSTex = [self texFromStr:@"S" attribute:symbolAttr];
	StrGTex = [self texFromStr:@"G" attribute:symbolAttr];
}
- (void)setupEquationTex {
	equLTex = [self equTexWithName:@"equationL"];
	equPTex = [self equTexWithName:@"equationP"];
}
- (NSMutableData *)adjustPtclMemory:(DisplaySetups)req {
	NSMutableData *newMem = _particleMem;
	if (setups.nPtcls != req.nPtcls) {
		newMem = [NSMutableData dataWithLength:sizeof(Particle) * req.nPtcls];
		if (newMem == NULL) {
			error_msg(@"Could not allocate memory for particles.", nil);
			@throw @(FailPtclMem);
		}
		if (_particleMem != nil)
			memcpy(newMem.mutableBytes, _particleMem.bytes,
				(setups.nPtcls > req.nPtcls)? newMem.length : _particleMem.length);
		if (setups.nPtcls < req.nPtcls) {
			Particle *p = newMem.mutableBytes;
			for (int i = setups.nPtcls; i < req.nPtcls; i ++)
				particle_reset(p + i, YES);
		}
#ifdef DEBUG
NSLog(@"Ptcl=%ld", newMem.length / sizeof(Particle));
#endif
	}
	return newMem;
}
- (NSArray<id<MTLBuffer>> *)adjustColBufferSize:(DisplaySetups)req {
	id<MTLBuffer> newColBuf[2] = { colBufD[0], colBufD[1] };
	NSInteger nColBuf = (colBufD[0] == nil)? 0 : colBufD[0].length / sizeof(simd_float4);
	NSInteger newNC = (req.displayMode == DispParticle)?
			(req.colorMode == PTCLconstColor)? 0 : req.nPtcls :
		(req.displayMode == DispVector)? N_VECTORS : nGridsInUse * NActs;
	if (nColBuf != newNC) {
		if (newNC > 0) {
			newColBuf[0] = [view.device newBufferWithLength:
				sizeof(simd_float4) * newNC options:isARM? 
				MTLResourceStorageModeShared : MTLResourceStorageModeManaged];
			if (isARM) newColBuf[1] = [view.device newBufferWithLength:
				sizeof(simd_float4) * newNC options:MTLResourceStorageModeShared];
			if (newColBuf[0] == nil || (isARM && newColBuf[1] == nil)) {
				error_msg(@"Could not allocate buffer for colors.", nil);
				@throw @(FailColBuf);
			}
		} else newColBuf[0] = newColBuf[1] = nil;
#ifdef DEBUG
NSLog(@"colBuf=%ld", newColBuf[0].length / sizeof(simd_float4));
#endif
	}
	return (newColBuf[0] == nil)? @[] :
		(newColBuf[1] == nil)? @[newColBuf[0]] : @[newColBuf[0], newColBuf[1]];
}
- (NSArray<id<MTLBuffer>> *)adjustVxBufferSize:(DisplaySetups)req {
	id<MTLBuffer> newVxBuf[2] = { vxBufD[0], vxBufD[1] };
	NSInteger nVertices = (vxBufD[0] == nil)? 0 : vxBufD[0].length / sizeof(simd_float2);
	int newNV = (req.displayMode == DispParticle)?
		req.nPtcls * ((req.shapeMode == PTCLbyRectangles)? 6 :
			(req.shapeMode == PTCLbyTriangles)? 3 : 2) :
		((req.displayMode == DispVector)? N_VECTORS : nGridsInUse * NActs) * NVERTICES_ARROW;
	if (newNV != nVertices) {
		newVxBuf[0] = [view.device newBufferWithLength:
			sizeof(simd_float2) * newNV options:isARM? 
			MTLResourceStorageModeShared : MTLResourceStorageModeManaged];
		if (isARM) newVxBuf[1] = [view.device newBufferWithLength:
			sizeof(simd_float2) * newNV options:MTLResourceStorageModeShared];
		if (newVxBuf[0] == nil || (isARM && newVxBuf[1] == nil)) {
			error_msg(@"Could not allocate buffer for vertices.", nil);
			@throw @(FailVxBuf);
		}
#ifdef DEBUG
NSLog(@"vxBuf=%ld", newVxBuf[0].length / sizeof(simd_float2));
#endif
	}
	if (req.displayMode != DispParticle) {
		_arrowVec = realloc(_arrowVec, sizeof(simd_float2) * N_MAX_VECTORS * NVERTICES_ARROW);
		if (_arrowVec == NULL) {
			error_msg(@"Could not allocate memory for arrow vectors.", nil);
			@throw @(FailArrowMem);
		}
		_arrowCol = realloc(_arrowCol, sizeof(simd_float4) * N_MAX_VECTORS);
		if (_arrowCol == NULL) {
			free(_arrowVec);
			_arrowVec = NULL;
			error_msg(@"Could not allocate memory for arrow colors.", nil);
			@throw @(FailArrowMem);
		}
	}
	return (newVxBuf[0] == nil)? @[] :
		(newVxBuf[1] == nil)? @[newVxBuf[0]] : @[newVxBuf[0], newVxBuf[1]];
}
- (BOOL)adjustMemoryFor:(DisplaySetups)req lock:(BOOL)lock{
	if (lock) [loopLock lock];
	BOOL result = YES;
	@try {
		NSMutableData *newPTCLs = [self adjustPtclMemory:req];
		NSArray<id<MTLBuffer>> *newColBuf = [self adjustColBufferSize:req];
		NSArray<id<MTLBuffer>> *newVxBuf = [self adjustVxBufferSize:req];
		_particleMem = newPTCLs;
		colBufD[0] = (newColBuf.count > 0)? newColBuf[0] : nil;
		colBufD[1] = (newColBuf.count > 1)? newColBuf[1] : nil;
		vxBufD[0] = (newVxBuf.count > 0)? newVxBuf[0] : nil;
		vxBufD[1] = (newVxBuf.count > 1)? newVxBuf[1] : nil;
		BOOL vxRev, colRev;
		if (req.displayMode == DispParticle) {
			if (req.nPtcls != setups.nPtcls) vxRev = colRev = YES;
			else {
				vxRev = (req.shapeMode != setups.shapeMode);
				colRev = (req.colorMode != setups.colorMode);
			}
			setups = req;
			if (vxRev) [self setupVertices];
			if (colRev) [self setupParticleColors];
		} else setups = req;
	} @catch (NSNumber *num) { result = NO; }
	if (lock) [loopLock unlock];
	return result;
}
// for scale and shape adjustment in full screen mode.
- (void)matrixFromCorners {
	simd_float4x4 p;
	simd_float4 y = {}, *z = p.columns;
	simd_float2 *cn = corners.columns;
	for (NSInteger i = 0; i < 4; i ++) y[i] = cn[i].y;
	for (NSInteger i = 0; i < 4; i ++) {
		float x = cn[i].x;
		z[i] = (simd_float4){x, x, x, x} * y;
	}
	float ae_bd = z[0][1]-z[1][0]+z[1][2]-z[2][1]+z[2][3]-z[3][2]+z[3][0]-z[0][3];
	float g = (z[0][1]-z[1][0]+z[2][0]-z[0][2]+z[1][3]-z[3][1]+z[3][2]-z[2][3]) / ae_bd;
	float h = (z[0][2]-z[2][0]+z[2][1]-z[1][2]+z[3][0]-z[0][3]+z[1][3]-z[3][1]) / ae_bd;
	float a = (g*(cn[0].x+cn[3].x)+(h-1.0)*(cn[0].x-cn[3].x)) / 2.;
	float b = ((g-1.0)*(cn[0].x-cn[1].x)+h*(cn[0].x+cn[1].x)) / 2.;
	float c = (cn[0].x+cn[2].x-(g+h)*(cn[0].x-cn[2].x)) / 2.;
	float d = (g*(cn[0].y+cn[3].y)+(h-1.0)*(cn[0].y-cn[3].y)) / 2.;
	float e = ((g-1.0)*(cn[0].y-cn[1].y)+h*(cn[0].y+cn[1].y)) / 2.;
	float f = (cn[0].y+cn[2].y-(g+h)*(cn[0].y-cn[2].y)) / 2.;
	adjustMx.columns[0] = (simd_float3){a, b, c};
	adjustMx.columns[1] = (simd_float3){d, e, f};
	adjustMx.columns[2] = (simd_float3){g, h, 1.0};
	adjustMxI.columns[0] = (simd_float3){e-f*h, c*h-b, b*f-c*e};
	adjustMxI.columns[1] = (simd_float3){f*g-d, a-c*g, c*d-a*f};
	adjustMxI.columns[2] = (simd_float3){d*h-e*g, b*g-a*h, a*e-b*d};
	cornersWereModified = !simd_equal(corners, savedCorners);
}
static simd_float4x2 DefaultCorners = {(simd_float2){-1, -1},
		(simd_float2){-1, 1}, (simd_float2){1, 1}, (simd_float2){1, -1}};
- (void)resetAdjustMatrix {
	corners = DefaultCorners;
	adjustMxI = adjustMx = matrix_identity_float3x3;
	cornersWereModified = !simd_equal(corners, savedCorners);
}
- (void)scaleAdjustMatrix:(float)exp {
	float mag = powf(1.01, exp);
	simd_float2 minv = {-1, -1}, maxv = {1, 1};
	for (NSInteger i = 0; i < 4; i ++)
		corners.columns[i] = simd_clamp(corners.columns[i] * mag, minv, maxv);
	[self matrixFromCorners];
	view.needsDisplay = YES;
}
- (int)cornerIndexAtPosition:(simd_float2)p size:(simd_float2)size {
	int idx;
	for (idx = 0; idx < 4; idx ++)
		if (simd_distance(p, (corners.columns[idx] + 1.) / 2. * size) < CORNER_MK_R) break;
	return (idx >= 4)? -1 : idx;
}
- (void)moveCorner:(int)idx to:(simd_float2)p size:(simd_float2)size {
	corners.columns[idx] = p / size * 2. - 1.;
	[self matrixFromCorners];
	view.needsDisplay = YES;
}
- (void)loadAdjustmentCorners {
	NSArray<NSNumber *> *arr =
		[NSUserDefaults.standardUserDefaults objectForKey:keyAdjustmentCorners];
	@try {
		if (arr == nil || ![arr isKindOfClass:NSArray.class] || arr.count < 8) @throw @0;
		for (NSInteger i = 0; i < 4; i ++) {
			if (![arr[i*2] isKindOfClass:NSNumber.class]) @throw @0;
			if (![arr[i*2+1] isKindOfClass:NSNumber.class]) @throw @0;
			corners.columns[i] = simd_clamp(
				(simd_float2){arr[i*2].floatValue, arr[i*2+1].floatValue},
				(simd_float2){-1, -1}, (simd_float2){1, 1});
		}
		[self matrixFromCorners];
	} @catch (id _) { [self resetAdjustMatrix]; }
}
- (BOOL)saveAdjustmentCorners {
	if (!cornersWereModified) return NO;
	if (!simd_equal(corners, DefaultCorners)) {
		NSNumber *nums[8];
		for (NSInteger i = 0; i < 8; i ++) nums[i] = @(corners.columns[i / 2][i % 2]);
		[NSUserDefaults.standardUserDefaults setObject:
			[NSArray arrayWithObjects:nums count:8] forKey:keyAdjustmentCorners];
	} else [NSUserDefaults.standardUserDefaults removeObjectForKey:keyAdjustmentCorners];
	if (adjustSavedTex == nil) adjustSavedTex =
		[self texFromImageName:@"AdjustSaved" rotate:NO width:view.bounds.size.width / 2.];
	savedCorners = corners;
	cornersWereModified = NO;
	adjustTex = adjustSavedTex;
	if (savedMsgTimer != nil && savedMsgTimer.valid) [savedMsgTimer invalidate];
	savedMsgTimer = [NSTimer scheduledTimerWithTimeInterval:2. repeats:NO block:
	^(NSTimer * _Nonnull timer) {
		self->adjustTex = self->adjustKeysTex;
		self->view.needsDisplay = YES;
	}];
	view.needsDisplay = YES;
	return YES;
}
- (void)setInfoView:(NSView * _Nullable)iview { infoView = iview; }
#define MAKE_PSO(vs,fs,var)\
 	pplnStDesc.vertexFunction = fnDict[vs];\
	pplnStDesc.fragmentFunction = fnDict[fs];\
	var = [device newRenderPipelineStateWithDescriptor:pplnStDesc error:&error];\
	if (var == nil) err_msg(error.localizedDescription, (OSStatus)error.code, YES);
- (instancetype)initWithView:(MTKView *)mtkView agent:(Agent *)a {
	if (!(self = [super init])) return nil;
	int mib[2] = { CTL_HW, HW_MACHINE };
	size_t dataSize = 128;
	char archName[128];
	memset(archName, 0, 128);
	if (sysctl(mib, 2, archName, &dataSize, NULL, 0) < 0)
		err_msg(@"Couldn't get architecture type.", errno, YES);
	isARM = strcmp(archName, "x86_64") != 0;
	nCores = (int)NSProcessInfo.processInfo.activeProcessorCount;
	if (nCores > 8) nCores -= 2;
	else if (nCores > 5) nCores --;
	loopLock = NSLock.new;
	loopLock.name = @"Display Loop";
	opeQue = NSOperationQueue.new;
	_agent = a;
	view = mtkView;
	view.enableSetNeedsDisplay = YES;
	view.paused = YES;
	[self loadAdjustmentCorners];
	savedCorners = corners;
	cornersWereModified = NO;
	id<MTLDevice> device = view.device = MTLCreateSystemDefaultDevice();
	NSAssert(device, @"Metal is not supported on this device");
	NSUInteger smplCnt = 1;
	while ([device supportsTextureSampleCount:smplCnt << 1]) smplCnt <<= 1;
	view.sampleCount = smplCnt;
	[self mtkView:view drawableSizeWillChange:view.drawableSize];
	view.delegate = self;
#ifdef DEBUG
	NSLog(@"%d Cores, Sample count = %ld, %@.", nCores, smplCnt,
		isARM? @"ARM_64" : @"x86_64" );
#endif
	NSError *error;
	id<MTLLibrary> dfltLib = device.newDefaultLibrary;
	NSMutableDictionary<NSString *, id<MTLFunction>> *fnDict = NSMutableDictionary.new;
	NSArray<NSString *> *fnNames = @[@"vertexShader", @"fragmentShader",
		@"vertexShaderTex", @"fragmentShaderTex", @"fragmentShaderColorTex",
		@"vertexShaderTP", @"fragmentShaderTP"];
	for (NSString *name in fnNames)
		fnDict[name] = [dfltLib newFunctionWithName:name];
	MTLRenderPipelineDescriptor *pplnStDesc = MTLRenderPipelineDescriptor.new;
	pplnStDesc.label = @"Simple Pipeline";
	pplnStDesc.rasterSampleCount = view.sampleCount;
	MTLRenderPipelineColorAttachmentDescriptor *colAttDesc = pplnStDesc.colorAttachments[0];
	colAttDesc.pixelFormat = view.colorPixelFormat;
	colAttDesc.blendingEnabled = YES;
	colAttDesc.rgbBlendOperation = MTLBlendOperationAdd;
	colAttDesc.sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
	colAttDesc.destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
	MAKE_PSO(@"vertexShader", @"fragmentShader", shapePSO)
	MAKE_PSO(@"vertexShaderTex", @"fragmentShaderTex", texPSO)
	MAKE_PSO(@"vertexShaderTex", @"fragmentShaderColorTex", texColPSO)
	MAKE_PSO(@"vertexShaderTP", @"fragmentShaderTP", tpPSO)
	commandQueue = device.newCommandQueue;
	add_observer(keyShouldRedraw,
		^(NSNotification * _Nonnull note) { self->view.needsDisplay = YES; });
	add_observer(@"colorParticles", ^(NSNotification * _Nonnull note) {
		if (self->setups.displayMode != DispParticle) return;
		[self->loopLock lock];
		[self setupParticleColors];
		[self->loopLock unlock];
		self->view.needsDisplay = YES; });
	add_observer(@"nParticles", ^(NSNotification * _Nonnull note) {
		DisplaySetups req = self->setups;
		req.nPtcls = NParticles;
		if (![self adjustMemoryFor:req lock:YES]) {
			[(ControlPanel *)note.userInfo[keyCntlPnl] adjustNParticleDgt];
		}
		else if (self->setups.displayMode == DispParticle) self->view.needsDisplay = YES;
	});
	add_observer(@"ptclLifeSpan", ^(NSNotification * _Nonnull note) {
		NSNumber *oldValue = note.userInfo[keyOldValue];
		if (oldValue == nil) return;
		int orgVal = oldValue.intValue;
		Particle *p = self.particleMem.mutableBytes;
		for (int i = 0; i < self.nPtcls; i ++)
			p[i].life = p[i].life * LifeSpan / orgVal;
		if (self->setups.displayMode == DispParticle) self->view.needsDisplay = YES;
	});
	add_observer(keyColorMode, ^(NSNotification * _Nonnull note) {
		if (self->setups.displayMode != DispParticle) return;
		[self->loopLock lock];
		@try {
			DisplaySetups req = self->setups;
			req.colorMode = ptclColorMode;
			NSArray<id<MTLBuffer>> *newColBuf = [self adjustColBufferSize:req];
			self->colBufD[0] = (newColBuf.count > 0)? newColBuf[0] : nil;
			self->colBufD[1] = (newColBuf.count > 1)? newColBuf[1] : nil;
			self->setups.colorMode = req.colorMode;
			[self setupParticleColors];
		} @catch (id x) {
			[(ControlPanel *)note.userInfo[keyCntlPnl] adjustColorMode:note.userInfo];
		}
		[self->loopLock unlock];
		self->view.needsDisplay = YES;
	});
	add_observer(keyShapeMode, ^(NSNotification * _Nonnull note) {
		if (self->setups.displayMode != DispParticle) return;
		[self->loopLock lock];
		@try {
			DisplaySetups req = self->setups;
			req.shapeMode = ptclShapeMode;
			NSArray<id<MTLBuffer>> *newVxBuf = [self adjustVxBufferSize:req];
			self->vxBufD[0] = (newVxBuf.count > 0)? newVxBuf[0] : nil;
			self->vxBufD[1] = (newVxBuf.count > 1)? newVxBuf[1] : nil;
			self->setups.shapeMode = req.shapeMode;
			[self setupVertices];
		} @catch (id x) {
			[(ControlPanel *)note.userInfo[keyCntlPnl] adjustShapeMode:note.userInfo];
		}
		[self->loopLock unlock];
		self->view.needsDisplay = YES;
	});
	add_observer(keyShouldReviseVertices, ^(NSNotification * _Nonnull note) {
		if (self->setups.displayMode != DispParticle) return;
		[self->loopLock lock];
		[self setupVertices];
		[self->loopLock unlock];
		self->view.needsDisplay = YES;
	});
	return self;
}
simd_float3x3 particle_tr_mx(Particle *p) {
	float th = atan2f(p->v.y, p->v.x);
	return (simd_float3x3){
		(simd_float3){cosf(th), sinf(th), 0.},
		(simd_float3){-sinf(th), cosf(th), 0.},
		(simd_float3){p->p.x, p->p.y, 1.}};
}
#define EASY_HSB
#ifdef EASY_HSB
static simd_float4 hsb_to_rgb(simd_float4 hsba) {
	float h = hsba.x * 6.f;
	simd_float3 rgb = ((h < 1.)? (simd_float3){1., h, 0.} :
		(h < 2.)? (simd_float3){2. - h, 1., 0.} :
		(h < 3.)? (simd_float3){0., 1., h - 2.} :
		(h < 4.)? (simd_float3){0., 4. - h, 1.} :
		(h < 5.)? (simd_float3){h - 4., 0., 1.} :
			(simd_float3){1., 0., 6. - h}) * hsba.z;
	float g = simd_reduce_add(rgb) / 3.;
	rgb += ((simd_float3){g, g, g} - rgb) * (1. - hsba.y);
	return (simd_float4){rgb.r, rgb.g, rgb.b, hsba.w};
}
#else
static simd_float3 cmp(simd_float3 a, simd_float3 b, simd_float3 c) {
	return simd_make_float3(
		(a.x < 0.)? b.x : c.x, (a.y < 0.)? b.y : c.y, (a.z < 0.)? b.z : c.z);
}
static simd_float4 hsb_to_rgb(simd_float4 hsba) {
	float h=hsba.x*6.2831853;
	float x=hsba.y * cosf(h) / 3., y = hsba.y * sinf(h) / 1.73205080757;
	simd_float3 v = fmod(simd_abs(
		simd_make_float3(hsba.z + x + y, hsba.z - x - x, hsba.z + x - y)) / 2., 2.);
	v = cmp(v-1., v, 2.-v);
	v = cmp(v, 0., pow(v, 1.2415));
	float gr=(v.x + v.y + v.z) / 3., gm = 0.5881;
	v = cmp(v - gr, pow(v / gr, gm) * gr, 1. - pow((1. - v) / (1. - gr), gm) * (1. - gr));
	simd_float3 p1 = cmp(v - simd_make_float3(v.g, v.b, v.r), 0., simd_make_float3(4., 2., 1.));
	x = p1.x + p1.y + p1.z;
	simd_float3 p2 = (x == 6.)? simd_make_float3(v.g - v.b, v.b, v.r) :
		(x == 2.)? simd_make_float3(v.g - v.r, v.b, v.g) :
		(x == 3.)? simd_make_float3(v.b - v.r, v.r, v.g) :
		(x == 1.)? simd_make_float3(v.b - v.g, v.r, v.b) :
		(x == 5.)? simd_make_float3(v.r - v.g, v.g, v.b) : simd_make_float3(v.r - v.b, v.g, v.r);
	p2.x = p2.x / (p2.z - p2.y);
	x = fmod(h, 1.);
	p1 = simd_make_float3(p2.y, p2.z - x * (p2.z - p2.y), p2.z - (1. - x) * (p2.z - p2.y));
	v = (p2.z == p2.y)? simd_make_float3(p2.z) :
		(h < 1.)? simd_make_float3(p2.z, p1.z, p1.x) :
		(h < 2.)? simd_make_float3(p1.y, p2.z, p1.x) :
		(h < 3.)? simd_make_float3(p1.x, p2.z, p1.z) :
		(h < 4.)? simd_make_float3(p1.x, p1.y, p2.z) :
		(h < 5.)? simd_make_float3(p1.z, p1.x, p2.z) : simd_make_float3(p2.z, p1.x, p1.y);
	return simd_make_float4(v.x, v.y, v.z, hsba.w);
}
#endif
static float grade_to_hue(float grade) {
	static struct { float hue; float x; } G[] = {
		{2./3., 0.},	// blue
		{1./3., .3}, // green
		{1./6., .6}, // yellow
		{0., 1.} // red
	};
	for (int i = 1; i < 4; i ++) if (grade < G[i].x) {
		float a = (grade - G[i - 1].x) / (G[i].x - G[i - 1].x);
		return G[i - 1].hue * (1.f - a) + G[i].hue * a;
	}
	return 5./6.;
}
simd_float4 ptcl_hsb_color(void) {
	CGFloat h, s, b, a;
	[colParticles getHue:&h saturation:&s brightness:&b alpha:&a];
	return (simd_float4){h, s, b, a};
}
simd_float4 ptcl_rgb_color(Particle * _Nonnull p, simd_float4 hsba, float maxSpeed) {
	return hsb_to_rgb((simd_float4){(ptclColorMode == PTCLangleColor)?
			fmodf(atan2f(p->v.y, p->v.x) / (2 * M_PI) + hsba.x + 1.f, 1.f) :
			grade_to_hue(simd_length(p->v) / maxSpeed),
		(hsba.y + .1) * .5, hsba.z, hsba.w});
}
simd_float2 particle_size(Particle * _Nonnull p) {
	simd_float2 sz = (simd_float2){
		tileSize.x * StrokeLength / 2., tileSize.x * StrokeWidth / 2.};
	if (LifeSpan - p->life < 10) sz *= (LifeSpan - p->life) / 9.;
	return sz;
}
- (void)setupParticleColors {
	if (colBufD[colBufIndex] == nil) { colBuf = nil; return; }
	simd_float4 *colors = colBufD[colBufIndex].contents,
		ptclHSB = ptcl_hsb_color();
	Particle *p = _particleMem.mutableBytes;
	THREADS_PRE(long, setups.nPtcls)
	for (int i = 0; i < nThreads; i ++) {
		THREADS_ST(long)
		void (^block)(void) = ^{
			for (int j = 0; j < nn; j ++) colors[idxStart + j] =
				ptcl_rgb_color(p + idxStart + j, ptclHSB, self->maxSpeed);
		};
		THREADS_DO
	}
	[opeQue waitUntilAllOperationsAreFinished];
	id<MTLBuffer> buf = colBufD[colBufIndex];
	in_main_thread(^{ self->colBuf = buf; }); 
	if (isARM) colBufIndex = 1 - colBufIndex;
	else [colBuf didModifyRange:(NSRange){0, colBuf.length}];
}
- (void)setupVertices {
	int nVpL = (int)(vxBufD[vxBufIndex].length / sizeof(simd_float2) / setups.nPtcls);
	simd_float2 *lines = vxBufD[vxBufIndex].contents;
	Particle *p = _particleMem.mutableBytes;
	float mxSpd[(NTHREADS <= 0)? 1 : NTHREADS];
	memset(mxSpd, 0, sizeof(mxSpd));
	THREADS_PRE(long, setups.nPtcls)
	for (int i = 0; i < nThreads; i ++) {
		THREADS_ST(long)
		Particle *pStart = p + idxStart;
		simd_float2 *lineStart = lines + idxStart * nVpL;
		float *mxSpdP = mxSpd + i;
		void (^block)(void) = ^{
			for (int j = 0; j < nn; j ++) {
				Particle *p = pStart + j;
				float spd = simd_length(p->v);
				if (*mxSpdP < spd) *mxSpdP = spd;
				simd_float2 sz = particle_size(p), *vp = lineStart + j * nVpL;
				switch (nVpL) {
					case 6: { // rectangle (two triangles)
						simd_float3x3 trs = particle_tr_mx(p);
						vp[0] = simd_mul(trs, (simd_float3){sz.x, sz.y, 1.}).xy;
						vp[1] = simd_mul(trs, (simd_float3){-sz.x, sz.y, 1.}).xy;
						vp[2] = simd_mul(trs, (simd_float3){sz.x, -sz.y, 1.}).xy;
						vp[3] = simd_mul(trs, (simd_float3){-sz.x, -sz.y, 1.}).xy;
						vp[4] = vp[2]; vp[5] = vp[1];
					} break;
					case 3: { // triangle
						simd_float3x3 trs = particle_tr_mx(p);
						vp[0] = simd_mul(trs, (simd_float3){sz.x, sz.y, 1.}).xy;
						vp[1] = simd_mul(trs, (simd_float3){-sz.x, 0., 1.}).xy;
						vp[2] = simd_mul(trs, (simd_float3){sz.x, -sz.y, 1.}).xy;
					} break;
					case 2: { // line segment
						float v = simd_length(p->v);
						vp[0] = p->p + p->v / v * sz.x;
						vp[1] = p->p - p->v / v * sz.x;
		}}} };
		THREADS_DO
	}
	[opeQue waitUntilAllOperationsAreFinished];
	id<MTLBuffer> buf = vxBufD[vxBufIndex];
	in_main_thread(^{ self->vxBuf = buf; }); 
	if (isARM) vxBufIndex = 1 - vxBufIndex;
	else [vxBuf didModifyRange:(NSRange){0, vxBuf.length}];
	maxSpeed = fmaxf(mxSpd[0], tileSize.x * .005);
	for (int i = 1; i < NTHREADS; i ++) if (maxSpeed < mxSpd[i]) maxSpeed = mxSpd[i];
}
#ifdef USE_FORCE_GRID
- (void)calcForceGrids {
	THREADS_PRE(int, nGridsInUse)
	for (int i = 0; i < nThreads; i ++) {
		THREADS_ST(int)
		void (^block)(void) = ^{
			for (int j = 0; j < nn; j ++) {
				simd_int2 idx = FieldP[idxStart + j],
					rngT = simd_min((simd_int2){nGridW, nGridH}, idx + 2),
					rngF = simd_max(0, idx - 1), jdx, kdx;
				for (kdx.y = 0; kdx.y < FF_N_GRID; kdx.y ++)
				for (kdx.x = 0; kdx.x < FF_N_GRID; kdx.x ++) {
					simd_float2 v = 0.,
						p = simd_float(idx) + (simd_float(kdx) + .5) / FF_N_GRID;
					float dSum = 0.;
					for (jdx.y = rngF.y; jdx.y < rngT.y; jdx.y ++)
					for (jdx.x = rngF.x; jdx.x < rngT.x; jdx.x ++)
					if (obstaclesMode >= ObsPointer || ObsHeight[ij_to_idx(jdx)] == 0) {
						simd_float4 Q = QTable[ij_to_idx(jdx)];
						float d = simd_distance_squared(p, simd_float(jdx) + .5);
						v += (simd_float2){Q.y - Q.w, Q.x - Q.z} / d;
						dSum += 1. / d;
					}
					ForceGrid[idx_of_forceGrid(idx * FF_N_GRID + kdx)] = v / dSum;
		}}};
		THREADS_DO
	}
	[opeQue waitUntilAllOperationsAreFinished];
}
#endif
static void set_arrow_shape(simd_float2 *v, simd_float3x3 *trs) {
	static simd_float3 v3[NVERTICES_ARROW] = {
		{-1., AR_TAIL_Y, 1.}, {-1., -AR_TAIL_Y, 1.}, {AR_HEAD_X, AR_TAIL_Y, 1.},
		{-1., -AR_TAIL_Y, 1.}, {AR_HEAD_X, AR_TAIL_Y, 1.}, {AR_HEAD_X, -AR_TAIL_Y, 1.},
		{1., 0., 1.}, {AR_HEAD_X, 1., 1.}, {AR_HEAD_X, -1., 1.}
	};
	for (int i = 0; i < NVERTICES_ARROW; i ++)
		v[i] = simd_mul(*trs, v3[i]).xy;
}
- (void)setupArrowInfo:(int)n {
	int nv = NVERTICES_ARROW;
	vxBuf = vxBufD[vxBufIndex];
	colBuf = colBufD[colBufIndex];
	memcpy(vxBuf.contents, _arrowVec, sizeof(simd_float2) * n * nv);
	memcpy(colBuf.contents, _arrowCol, sizeof(simd_float4) * n);
	if (!isARM) {
		[vxBuf didModifyRange:(NSRange){0, sizeof(simd_float2) * n * nv}];
		[colBuf didModifyRange:(NSRange){0, sizeof(simd_float4) * n}];
	} else { vxBufIndex = 1 - vxBufIndex; colBufIndex = 1 - colBufIndex; }
}
- (void)setupArrowsForVecFld {
#ifdef USE_FORCE_GRID
	[self calcForceGrids];
#endif
	simd_float4 vec[N_VECTORS];
	Particle ptcl;
	for (int i = 0, vIdx = 0; i < nActiveGrids; i ++) {
		simd_float2 ixy = simd_float(FieldP[i]);
		simd_int2 jk;
		for (jk.y = 0; jk.y < N_VECTOR_GRID; jk.y ++)
		for (jk.x = 0; jk.x < N_VECTOR_GRID; jk.x ++, vIdx ++) {
			vec[vIdx].xy = ptcl.p =
				(ixy + (simd_float(jk) + .5) / N_VECTOR_GRID) * simd_float(tileSize);
			simd_float2 f = particle_force(&ptcl);
			vec[vIdx].z = simd_length(f);
			vec[vIdx].w = atan2f(f.y, f.x);
		}
	}
	float maxV = -1e10;
	for (int i = 0; i < N_VECTORS; i ++)
		if (maxV < vec[i].z) maxV = vec[i].z;
	simd_float4 bgCol = col_to_vec(colBackground),
		maxCol = (simd_reduce_add(bgCol.rgb) > 1.5)?
			(simd_float4){0., 0., 0., 1.} : (simd_float4){1., 1., 1., 1.};
	for (int i = 0; i < N_VECTORS; i ++) {
		simd_float2 cs = {cosf(vec[i].w), sinf(vec[i].w)};
		cs *= simd_float(tileSize) / N_VECTOR_GRID / 2.;
		simd_float3x3 trs = {
			(simd_float3){cs.x, cs.y, 0.},
			(simd_float3){-cs.y * .5, cs.x * .5, 0.},
			(simd_float3){vec[i].x, vec[i].y, 1.}};
		set_arrow_shape(_arrowVec + i * NVERTICES_ARROW, &trs);
		float grade = .1 + vec[i].z / maxV * .9;
		_arrowCol[i] = bgCol * (1. - grade) + maxCol * grade;
	}
	[self setupArrowInfo:N_VECTORS];
}
- (void)setupArrowsForQValues {
	float minQ = 1e10, maxQ = -1e10;
	for (int i = 0; i < nActiveGrids; i ++) {
		simd_float4 Q = QTable[ij_to_idx(FieldP[i])];
		float minq = simd_reduce_min(Q), maxq = simd_reduce_max(Q);
		if (minQ > minq) minQ = minq;
		if (maxQ < maxq) maxQ = maxq;
	}
	float (^getGrade)(float) = ((maxQ - minQ) < 1.)?
		(minQ < 0.)? ^(float q) { return q - minQ; } : ^(float q) { return q; } :
		(minQ < 0.)? ^(float q) { return (q - minQ) / (maxQ - minQ); } :
			^(float q) { return q / maxQ; };
	simd_float4 bgCol = col_to_vec(colBackground),
		maxCol = (simd_reduce_add(bgCol.rgb) > 1.5)?
			(simd_float4){0., 0., 0., 1.} : (simd_float4){1., 1., 1., 1.};
	for (int i = 0, vIdx = 0; i < nActiveGrids; i ++) {
		simd_float4 Q = QTable[ij_to_idx(FieldP[i])];
		simd_float2 center = (simd_float(FieldP[i]) + .5) * simd_float(tileSize);
		for (int j = 0; j < NActs; j ++, vIdx ++) {
			float th = (1 - j) * M_PI / 2.;
			simd_float2 cs = {cosf(th), sinf(th)}; cs *= simd_float(tileSize) / 6.;
			simd_float3x3 trs = {
				(simd_float3){cs.x, cs.y, 0.},
				(simd_float3){-cs.y, cs.x, 0.},
				(simd_float3){center.x + cs.x * 2., center.y + cs.y * 2., 1.}};
			set_arrow_shape(_arrowVec + vIdx * NVERTICES_ARROW, &trs);
			float grade = .1 + getGrade(Q[j]) * .9;
			_arrowCol[vIdx] = bgCol * (1. - grade) + maxCol * grade;
		}
	}
	[self setupArrowInfo:nActiveGrids * NActs];
}
- (void)setDisplayMode:(DisplayMode)newMode {
	if (setups.displayMode == newMode) return;
	DisplaySetups req = { newMode, ptclColorMode, ptclShapeMode, NParticles };
	[loopLock lock];
	if ([self adjustMemoryFor:req lock:NO]) {
		setups.displayMode = newMode;
		switch (newMode) {
			case DispParticle:
			[self setupVertices];
			[self setupParticleColors]; break;
			case DispVector: [self setupArrowsForVecFld]; break;
			case DispQValues: [self setupArrowsForQValues];
			default: break;
		}
		view.needsDisplay = YES;
	}
	[loopLock unlock];
}
- (void)reset {
#ifdef USE_FORCE_GRID
	NSInteger gSz = sizeof(simd_float2) * nGrids * FF_N_GRID * FF_N_GRID;
	ForceGrid = realloc(ForceGrid, gSz);
	memset(ForceGrid, 0, gSz);
#endif
	if (_particleMem != nil) {
		[loopLock lock];
		Particle *p = _particleMem.mutableBytes;
		for (int i = 0; i < setups.nPtcls; i ++) particle_reset(p + i, YES);
		if (setups.displayMode == DispParticle && setups.colorMode != PTCLconstColor)
			[self setupParticleColors];
		[self setupVertices];
		[loopLock unlock];
	} else {
		DisplaySetups req = { DispParticle, ptclColorMode, ptclShapeMode, NParticles };
		setups.displayMode = DispNone;
		if (![self adjustMemoryFor:req lock:NO]) {
			int NpFDv = 100;
			for (IntVarInfo *p = IntVars; p->key != nil; p ++)
				if (p->v == &NParticles) { NpFDv = p->fd; break; }
			if (NParticles <= NpFDv) [NSApp terminate:nil];
			req.nPtcls = NParticles = NpFDv;
			if (![self adjustMemoryFor:req lock:NO]) [NSApp terminate:nil];
	}}
	view.needsDisplay = YES;
}
- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size {
	viewportSize.x = size.width;
	viewportSize.y = size.height;
	if (StrSTex != nil) {
		[self setupSymbolTex];
		[self setupEquationTex];
	}
	view.needsDisplay = YES;
#ifdef DEBUG
	NSLog(@"Drawable size = %.1f x %.1f", size.width, size.height);
	size = view.superview.frame.size;
	NSLog(@"%@ size = %.1f x %.1f", view.superview.class, size.width, size.height);
#endif
}
static void set_color(RCE rce, simd_float4 rgba) {
	[rce setVertexBytes:&rgba length:sizeof(rgba) atIndex:IndexColors];
}
static void set_fragment_color(RCE rce, simd_float4 rgba) {
	[rce setFragmentBytes:&rgba length:sizeof(rgba) atIndex:IndexFrgColor];
}
static void fill_rect(RCE rce, NSRect rect) {
	simd_float2 vertices[4] = {
		{NSMinX(rect), NSMinY(rect)},{NSMaxX(rect), NSMinY(rect)},
		{NSMinX(rect), NSMaxY(rect)},{NSMaxX(rect), NSMaxY(rect)}};
	uint nv = 0;
	[rce setVertexBytes:vertices length:sizeof(vertices) atIndex:IndexVertices];
	[rce setVertexBytes:&nv length:sizeof(nv) atIndex:IndexNVforP];
	[rce drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}
void fill_circle_at(RCE rce, simd_float2 center, float radius, int nEdges) {
	int nVertices = nEdges * 2;
	simd_float2 vx[nVertices];
	for (int i = 0; i < nVertices; i ++) vx[i] = center;
	for (int i = 0; i <= nEdges; i ++) {
		float th = i * M_PI * 2. / nEdges;
		vx[(i < nEdges)? i * 2 : nVertices - 1] +=
			(simd_float2){cosf(th), sinf(th)} * radius;
	}
	[rce setVertexBytes:vx length:sizeof(vx) atIndex:IndexVertices];
	[rce drawPrimitives:MTLPrimitiveTypeTriangleStrip
		vertexStart:0 vertexCount:nVertices];
}
static void draw_texture(RCE rce, id<MTLTexture> tex, simd_int2 tilePosition) {
	[rce setFragmentTexture:tex atIndex:IndexTexture];
	CGFloat h = tileSize.x * .667, w = h * tex.width / tex.height;
	simd_float2 org = simd_float(tilePosition * tileSize) +
		simd_float(tileSize) / 2.f - (simd_float2){w, h} / 2.f;
	fill_rect(rce, (NSRect){org.x, org.y, w, h});
}
static void draw_equtex(RCE rce, id<MTLTexture> tex, simd_int2 tileP, int nTiles) {
	[rce setFragmentTexture:tex atIndex:IndexTexture];
	simd_float2 org = (simd_float(tileP) + .1) * simd_float(tileSize);
	NSRect rect = {org.x, org.y, tileSize.x * .8, tileSize.y * (nTiles - .2)};
	CGFloat newW = rect.size.height * tex.width / tex.height;
	rect.origin.x += (rect.size.width - newW) / 2.;
	rect.size.width = newW;
	fill_rect(rce, rect);
}
- (void)setupArrows:(RCE)rce n:(int)n {
	uint nv = NVERTICES_ARROW;
	[rce setVertexBytes:&nv length:sizeof(nv) atIndex:IndexNVforP];
	[rce setVertexBuffer:vxBuf offset:0 atIndex:IndexVertices];
	[rce setVertexBuffer:colBuf offset:0 atIndex:IndexColors];
	[rce drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:n * nv];
}
- (void)clearObsPCache {
	if (obsMem == NULL) return;
	free(obsMem);
	obsMem = NULL;
}
- (void)drawScene:(nonnull MTKView *)view
	commandBuffer:(id<MTLCommandBuffer>)cmdBuf adjustment:(BOOL)adjust {
	float obsHeight[nGrids];
	switch (obstaclesMode) {
		case ObsFixed: case ObsRandom:
		nObs = nObstacles; obsP = ObsP;
		break;
		case ObsPointer: case ObsExternal:
		if (obsMem == NULL) obsMem = malloc(sizeof(simd_int2) * nGrids);
		obsP = obsMem;
		[theMainWindow.agentEnvLock lock];
		nObs = nObstacles;
		memcpy(obsP, ObsP, sizeof(simd_int2) * nGrids);
		memcpy(obsHeight, ObsHeight, sizeof(float) * nGrids);
		[theMainWindow.agentEnvLock unlock];
	}
	MTLRenderPassDescriptor *rndrPasDesc = view.currentRenderPassDescriptor;
	if(rndrPasDesc == nil) return;
	RCE rce = [cmdBuf renderCommandEncoderWithDescriptor:rndrPasDesc];
	rce.label = @"MyRenderEncoder";
	[rce setViewport:(MTLViewport){0., 0., viewportSize.x, viewportSize.y, 0., 1. }];
	simd_float2 geomFactor = {PTCLMaxX, PTCLMaxY};
	[rce setVertexBytes:&geomFactor length:sizeof(geomFactor) atIndex:IndexGeomFactor];
	[rce setVertexBytes:adjust? &adjustMx : &matrix_identity_float3x3
		length:sizeof(simd_float3x3) atIndex:IndexAdjustMatrix];
	[rce setRenderPipelineState:shapePSO];
	uint nv = 0;
	// background
	simd_float4 bgCol = col_to_vec(colBackground);
	set_color(rce, bgCol);
	fill_rect(rce, (NSRect){0., 0., PTCLMaxX, PTCLMaxY});
	// Agent
	set_color(rce, col_to_vec(colAgent));
	fill_circle_at(rce, (simd_float(_agent.position) + .5f) * simd_float(tileSize),
		simd_reduce_min(tileSize) * 0.45, 32);
	// String "S" and "G"
	simd_float4 symCol = col_to_vec(colSymbols);
	if (symCol.a > 0.) {
		if (StrSTex == nil) [self setupSymbolTex];
		[rce setRenderPipelineState:texColPSO];
		set_fragment_color(rce, symCol);
		draw_texture(rce, StrSTex, StartP);
		draw_texture(rce, StrGTex, GoalP);
	}
	// particles, vectors, or Q values
	[rce setRenderPipelineState:shapePSO];
	switch (setups.displayMode) {
		case DispParticle: if (_particleMem != nil) {
			uint nVertices = (vxBuf == NULL)? 0 :
				(uint)(vxBuf.length / sizeof(simd_float2));
			if (colBuf != nil) {
				nv = nVertices / setups.nPtcls;
				[rce setVertexBuffer:colBuf offset:0 atIndex:IndexColors];
			} else set_color(rce, col_to_vec(colParticles));
			[rce setVertexBytes:&nv length:sizeof(nv) atIndex:IndexNVforP];
			[rce setVertexBuffer:vxBuf offset:0 atIndex:IndexVertices];
			[rce drawPrimitives:(ptclShapeMode == PTCLbyLines)?
				MTLPrimitiveTypeLine : MTLPrimitiveTypeTriangle
				vertexStart:0 vertexCount:nVertices];
		} break;
		case DispVector: [self setupArrows:rce n:N_VECTORS]; break;
		case DispQValues: [self setupArrows:rce n:nActiveGrids * NActs];
		default: break;
	}
	// grid lines
	simd_float4 gridCol = col_to_vec(colGridLines);
	if (gridCol.a > 0.) {
		nv = 0; [rce setVertexBytes:&nv length:sizeof(nv) atIndex:IndexNVforP];
		set_color(rce, gridCol);
		simd_float2 vertices[NV_GRID], *vp = vertices;
		for (int i = 1; i < nGridH; i ++, vp += 2) {
			vp[0] = (simd_float2){0., tileSize.y * i};
			vp[1] = (simd_float2){PTCLMaxX, tileSize.y * i};
		}
		for (int i = 1; i < nGridW; i ++, vp += 2) {
			vp[0] = (simd_float2){tileSize.x * i, 0.};
			vp[1] = (simd_float2){tileSize.x * i, PTCLMaxY};
		}
		[rce setVertexBytes:vertices length:sizeof(vertices) atIndex:IndexVertices];
		[rce drawPrimitives:MTLPrimitiveTypeLine vertexStart:0 vertexCount:NV_GRID];
	}
	// Obstables
	simd_float4 obsCol = col_to_vec(colObstacles);
	if (obsCol.a > 0.) {
		if (obstaclesMode >= ObsPointer) {
			float maxA = obsCol.a;
			for (int i = 0; i < nObs; i ++) {
				obsCol.a = maxA * fmin(1., obsHeight[ij_to_idx(obsP[i])]);
				set_color(rce, obsCol);
				fill_rect(rce, (NSRect)
					{obsP[i].x * tileSize.x, obsP[i].y * tileSize.y, tileSize.x, tileSize.y});
			}
		} else {
			set_color(rce, obsCol);
			for (int i = 0; i < nObs; i ++) fill_rect(rce, (NSRect)
				{obsP[i].x * tileSize.x, obsP[i].y * tileSize.y, tileSize.x, tileSize.y});
	}}
	if (obstaclesMode >= ObsPointer) {
		id<MTLBuffer> info = [theTracker trackedPoints:view.device];
		if (info != nil) {
			[rce setRenderPipelineState:tpPSO];
			uint nPoints = (uint)(info.length / sizeof(simd_float3));
			simd_float4 tpColor = col_to_vec(colTracking);
			simd_float2 vertices[4] =
				{{0., 0.}, {PTCLMaxX, 0.}, {0., PTCLMaxY}, {PTCLMaxX, PTCLMaxY}};
			[rce setVertexBytes:vertices length:sizeof(vertices) atIndex:IndexVertices];
			[rce setFragmentBuffer:info offset:0 atIndex:IndexTPInfo];
			[rce setFragmentBytes:&tpColor length:sizeof(tpColor) atIndex:IndexTPColor];
			[rce setFragmentBytes:&nPoints length:sizeof(nPoints) atIndex:IndexTPN];
			[rce setFragmentBytes:&geomFactor length:sizeof(geomFactor) atIndex:IndexTPGeoFactor];
			[rce setFragmentBytes:&adjustMxI length:sizeof(adjustMxI) atIndex:IndexInvAdjMx];
			[rce drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
			if (DRAW_HAND) {
				if (handTex == nil) handTex = [self texWithName:@"Hand"];
				[rce setRenderPipelineState:texPSO];
				[rce setFragmentTexture:handTex atIndex:IndexTexture];
				simd_float3 *dp = info.contents;
				fill_rect(rce, (NSRect){dp[nPoints - 1].x - tileSize.x / 2.,
					dp[nPoints - 1].y - tileSize.y, tileSize.x, tileSize.y});
			}
		}
	} else if (symCol.a > 0.) {
	// project logo
		set_color(rce, symCol);
		if (logoDrawer == nil) logoDrawer = LogoDrawerMTL.new;
		float logoDim = simd_reduce_min(tileSize);
		simd_float2 logoP = (simd_float(obsP[3]) + .5) * simd_float(tileSize) - logoDim / 2.;
		[logoDrawer drawByMTL:rce inRect:(NSRect){logoP.x, logoP.y, logoDim, logoDim}];
	// equations
		if (equLTex == nil) [self setupEquationTex];
		[rce setRenderPipelineState:texColPSO];
		set_fragment_color(rce, col_to_vec(colSymbols));
		draw_equtex(rce, equLTex, obsP[0], 3);
		draw_equtex(rce, equPTex, obsP[4], 3);
	}
	// information view
	simd_float4 infoCol = col_to_vec(colInfoFG);
	if (infoCol.a > 0. && adjust && infoView != nil) {
		if (infoViewCacheBM == nil) {
			infoViewCacheBM = [infoView bitmapImageRepForCachingDisplayInRect:infoView.bounds];
			MTLTextureDescriptor *texDesc = [MTLTextureDescriptor
				texture2DDescriptorWithPixelFormat:view.colorPixelFormat
				width:infoViewCacheBM.pixelsWide height:infoViewCacheBM.pixelsHigh mipmapped:NO];
			infoViewTex = [view.device newTextureWithDescriptor:texDesc];
			infoView.hidden = YES;
		}
		memset(infoViewCacheBM.bitmapData, 0,
			infoViewCacheBM.bytesPerRow * infoViewCacheBM.pixelsHigh);
		infoView.hidden = NO;
		[infoView cacheDisplayInRect:infoView.bounds toBitmapImageRep:infoViewCacheBM];
		infoView.hidden = YES;
		[infoViewTex replaceRegion:
			MTLRegionMake2D(0, 0, infoViewCacheBM.pixelsWide, infoViewCacheBM.pixelsHigh)
			mipmapLevel:0 withBytes:infoViewCacheBM.bitmapData
			bytesPerRow:infoViewCacheBM.bytesPerRow];
		[rce setRenderPipelineState:texPSO];
		[rce setFragmentTexture:infoViewTex atIndex:IndexTexture];
		NSRect texRct = infoView.frame;
		CGFloat scale = PTCLMaxX / view.frame.size.width;
		for (NSInteger i = 0; i < 4; i ++) ((CGFloat *)(&texRct))[i] *= scale;
		fill_rect(rce, texRct);
	} else if (infoViewCacheBM != nil) {
		infoViewCacheBM = nil; infoViewTex = nil;
	}
	// display adjustment in full screen mode
	if (_dispAdjust && adjust) {
		if (adjustKeysTex == nil) adjustKeysTex = adjustTex =
			[self texFromImageName:@"AdjustKeys" rotate:NO width:view.bounds.size.width / 2.];
		[rce setRenderPipelineState:texPSO];
		[rce setFragmentTexture:adjustTex atIndex:IndexTexture];
		CGFloat txh = PTCLMaxY / 4.,
			txw = txh * adjustKeysTex.height / adjustKeysTex.width;
		NSRect texRct = {(PTCLMaxX - txw) / 2., (PTCLMaxY - txh) / 2., txw, txh};
		fill_rect(rce, texRct);
		[rce setRenderPipelineState:shapePSO];
		simd_float2 vertices[5];
		if (adjustTex == adjustKeysTex && !cornersWereModified) {
		// (14.0,91.4) 88.2 x 24.2 / 400 x 128
			set_color(rce, (simd_float4){0.,0.,0.,.75});
			NSRect strikes = {14./400., 1.-91.4/128., 88.2/400., 24.2/128.};
			vertices[0].x = vertices[2].x = strikes.origin.x * txw + texRct.origin.x;
			vertices[0].y = vertices[1].y = strikes.origin.y * txh + texRct.origin.y;
			vertices[1].x = vertices[3].x = NSMaxX(strikes) * txw + texRct.origin.x;
			vertices[2].y = vertices[3].y = NSMaxY(strikes) * txh + texRct.origin.y;
			[rce setVertexBytes:vertices length:sizeof(simd_float2) * 4 atIndex:IndexVertices];
			[rce drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
		}
		float v = (simd_reduce_add(bgCol.rgb) / 3. * bgCol.a < .5)? 1. : .333;
		set_color(rce, (simd_float4){v, v, v, 1.});
		float radius = CORNER_MK_R * PTCLMaxX / view.bounds.size.width;
		for (NSInteger i = 0; i < 4; i ++) {
			vertices[i] = (simd_float2){PTCLMaxX * (i / 2), PTCLMaxY * ((i % 2) ^ (i / 2))};
			fill_circle_at(rce, vertices[i], radius, 32);
		}
		vertices[4] = vertices[0];
		[rce setVertexBytes:vertices length:sizeof(simd_float2) * 5 atIndex:IndexVertices];
		[rce drawPrimitives:MTLPrimitiveTypeLineStrip vertexStart:0 vertexCount:5];
	} else if (adjustKeysTex != nil) {
		if (savedMsgTimer != nil && savedMsgTimer.valid) [savedMsgTimer invalidate];
		adjustKeysTex = adjustSavedTex = adjustTex = nil;
	} else if (fadeEndHandler != nil) {
		unsigned long tm = current_time_us();
		float darkness = (FadeoutSec <= 0.)? 1. : fmin(1., (tm - fadeStart) / (FadeoutSec * 1e6));
		[rce setRenderPipelineState:shapePSO];
		set_color(rce, (simd_float4){0., 0., 0., darkness});
		fill_rect(rce, (NSRect){0., 0., PTCLMaxX, PTCLMaxY});
		if (darkness == 1.) { fadeEndHandler(); fadeEndHandler = nil; }
	}
	[rce endEncoding];
}
- (void)drawInMTKView:(nonnull MTKView *)view {
	id<MTLCommandBuffer> cmdBuf = commandQueue.commandBuffer;
	cmdBuf.label = @"MyCommand";
	[self drawScene:view commandBuffer:cmdBuf adjustment:view.superview.inFullScreenMode];
	[cmdBuf presentDrawable:view.currentDrawable];
	[cmdBuf commit];
	[cmdBuf waitUntilCompleted];
	unsigned long tm = current_time_us(), elapsed_us = tm - time_us;
	if (elapsed_us > 1000000) dispCnt = 0;
	else if (elapsed_us > 10000)
		_FPS += (1e6 / elapsed_us - _FPS) * fmax(.05, 1. / (++ dispCnt));
	time_us = tm;
}
- (void)oneStepForParticles {
//#define MEASURE_TIME
#ifdef MEASURE_TIME
static NSUInteger s[5] = {0,0,0,0,0}, cnt = 0;
int ns = 0;
NSUInteger tm1, tm0 = current_time_us();
#endif
#ifdef USE_FORCE_GRID
	[self calcForceGrids];
//#ifdef MEASURE_TIME
//tm1 = current_time_us(); s[ns ++] += tm1-tm0; tm0 = tm1;
//#endif
#endif
	static int *idxMem = NULL, memSz = 0;
	if (memSz < setups.nPtcls)
		idxMem = realloc(idxMem, (memSz = setups.nPtcls) * sizeof(int));
	Particle *p = _particleMem.mutableBytes;
	THREADS_PRE(int, setups.nPtcls);
	for (int i = 0; i < nThreads; i ++) {
		THREADS_ST(int)
		Particle *pStart = p + idxStart;
		int *idxs = idxMem + idxStart;
		void (^block)(void) = ^{
			int k0 = 0, k1 = nn;
			for (int j = 0; j < nn; j ++) {
				Particle *p = pStart + j;
				if (p->p.x > 0. && p->p.x < PTCLMaxX
				 && p->p.y > 0. && p->p.y < PTCLMaxY
				 && (-- p->life) > 0 &&
				 (obstaclesMode >= ObsPointer || ObsHeight[p_to_idx(p->p)] == 0)
				 ) idxs[k0 ++] = j;
				else idxs[-- k1] = j;
			}
			for (int j = 0; j < k0; j ++)
				particle_step(pStart + idxs[j], particle_force(pStart + idxs[j]));
			for (int j = k1; j < nn; j ++)
				particle_reset(pStart + idxs[j], NO);
		};
		THREADS_DO
	}
	[opeQue waitUntilAllOperationsAreFinished];
#ifdef MEASURE_TIME
tm1 = current_time_us(); s[ns ++] += tm1-tm0; tm0 = tm1;
#endif
	[self setupVertices];
#ifdef MEASURE_TIME
tm1 = current_time_us(); s[ns ++] += tm1-tm0; tm0 = tm1;
#endif
	[self setupParticleColors];
#ifdef MEASURE_TIME
tm1 = current_time_us(); s[ns ++] += tm1-tm0; tm0 = tm1;
if ((++ cnt) >= 60) { cnt = 0; for (int i = 0; i < ns; i ++)
{ printf("%d:%ld ", i, s[i]); s[i] = 0; } printf("\n");}
#endif
}
- (void)oneStep {
	[loopLock lock];
	switch (setups.displayMode) {
		case DispParticle: [self oneStepForParticles]; break;
		case DispVector: [self setupArrowsForVecFld]; break;
		case DispQValues: [self setupArrowsForQValues];
		default: break;
	}
	in_main_thread(^{ self->view.needsDisplay = YES; });
	[loopLock unlock];
}
- (NSBitmapImageRep *)imageBitmapWithSize:(NSSize)size scaleFactor:(CGFloat)sclFactor
	drawBlock:(void (^)(NSBitmapImageRep *bm))block {
	view.framebufferOnly = NO;
	id<MTLCommandBuffer> cmdBuf = commandQueue.commandBuffer;
	cmdBuf.label = @"OffScreenCommand";
	[self drawScene:view commandBuffer:cmdBuf adjustment:NO];
	id<MTLTexture> tex = view.currentDrawable.texture;
	NSAssert(tex, @"Failed to get texture from MTKView.");
	NSUInteger texW = tex.width, texH = tex.height;
	id<MTLBuffer> buf = [tex.device newBufferWithLength:texW * texH * 4
		options:MTLResourceStorageModeShared];
	NSAssert(buf, @"Failed to create buffer for %ld bytes.", texW * texH * 4);
	id<MTLBlitCommandEncoder> blitEnc = cmdBuf.blitCommandEncoder;
	[blitEnc copyFromTexture:tex sourceSlice:0 sourceLevel:0
		sourceOrigin:(MTLOrigin){0, 0, 0} sourceSize:(MTLSize){texW, texH, 1}
		toBuffer:buf destinationOffset:0
		destinationBytesPerRow:texW * 4 destinationBytesPerImage:texW * texH * 4];
	[blitEnc endEncoding];
	[cmdBuf commit];
	[cmdBuf waitUntilCompleted];
	view.framebufferOnly = YES;

	NSUInteger wide = ceil(size.width * sclFactor), high = ceil(size.height * sclFactor);
	NSBitmapImageRep *srcImgRep =
		create_rgb_bitmap(texW, texH, (unsigned char *[]){buf.contents}),
		*dstImgRep = create_rgb_bitmap(wide, high, NULL);
	dstImgRep.size = size;
	draw_in_bitmap(dstImgRep, ^(NSBitmapImageRep * _Nonnull bm) {
		[srcImgRep drawInRect:(NSRect){0., 0., bm.size}];
		if (block != nil) block(bm);
	});
	// BGRA -> RGBA
	unsigned char *bytes = dstImgRep.bitmapData;
	for (NSInteger i = 0; i < wide * high; i ++, bytes += 4) {
		unsigned char c = bytes[0]; bytes[0] = bytes[2]; bytes[2] = c;
	}
	return dstImgRep;
}
@end
