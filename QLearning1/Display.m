//
//  Display.m
//  QLearning1
//
//  Created by Tatsuo Unemi on 2022/12/24.
//

#import "Display.h"
#import "Agent.h"
#import "AppDelegate.h"
#import "VecTypes.h"
#define NV_GRID ((NGridW + NGridH - 2) * 2)
#define NTHREADS 8

typedef struct {
  vector_float2 p, v, f;
  int life;
} Particle;

int NParticles = 120000, LifeSpan = 80;
float Mass = 2., Friction = 0.9, StrokeLength = 0.1, StrokeWidth = .01, MaxSpeed = 0.05;
NSColor *colBackground, *colObstacles, *colAgent,
	*colGridLines, *colSymbols, *colParticles;
PTCLDrawMethod ptclDrawMethod = PTCLbyLines;

vector_float4 col_to_vec(NSColor * _Nonnull col) {
	CGFloat c[4] = {0, 0, 0, 1};
	[[col colorUsingColorSpace:NSColorSpace.genericRGBColorSpace]
		getComponents:c];
	return (vector_float4){c[0], c[1], c[2], c[3]};
}
static float particle_addF(Particle *p, int ix, int iy) {
	if (ix < 0 || ix >= NGridW || iy < 0 || iy >= NGridH || Obstacles[iy][ix] != 0) return 0.;
	float w = powf(ix + .5 - p->p.x / TileSize, 2.) + powf(iy + .5 - p->p.y / TileSize, 2);
	vector_float4 Q = QTable[iy][ix];
	vector_float2 v = {Q.y - Q.w, Q.x - Q.z};
	if (w < 1e-12f) {
		p->f = v;
		return 1e12f;
	} else {
		p->f += v / w;
		return 1. / w;
	}
}
static void particle_force(Particle *p) {
	int ix = p->p.x / TileSize, iy = p->p.y / TileSize;
	p->f = (vector_float2){0., 0.};
	float wsum = particle_addF(p, ix, iy);
	if (wsum < 1e12f) {
//		vector_float2 d = p->p / TileSize - (vector_float2){ix, iy};
//		int nx = (d.x > .5)? 1 : -1, ny = (d.y > .5)? 1 : -1;
//		wsum += particle_addF(p, ix + nx, iy);
//		wsum += particle_addF(p, ix, iy + ny);
//		wsum += particle_addF(p, ix + nx, iy + ny);
		for (int nx = -1; nx <= 1; nx ++)
		for (int ny = -1; ny <= 1; ny ++) if (nx != 0 || ny != 0)
			wsum += particle_addF(p, ix + nx, iy + ny);
		p->f /= wsum;
	}
}
static void particle_reset(Particle *p, BOOL isRandom) {
	int *fp = FieldP[lrand48() % (NGridW * NGridH - NObstacles)];
	p->p = (vector_float2){(fp[0] + drand48()) * TileSize, (fp[1] + drand48()) * TileSize};
	particle_force(p);
	float v = hypotf(p->f.y, p->f.x);
	if (v < 1e-8) {
		float th = drand48() * M_PI * 2.;
		p->v = (vector_float2){cosf(th), sinf(th)};
	} else p->v = p->f / v;
	p->life = isRandom? lrand48() % LifeSpan : LifeSpan;
}
static void particle_step(Particle *p) {
	if ((-- p->life) <= 0) particle_reset(p, NO);
	else {
		p->v = (p->v + p->f / Mass) * Friction;
		float v = hypotf(p->v.x, p->v.y);
		if (v > TileSize * .1)
			p->v /= v * TileSize * MaxSpeed;
		p->p += p->v;
		if (p->p.x < 0 || p->p.x >= NGridW * TileSize
		 || p->p.y < 0 || p->p.y >= NGridH * TileSize) particle_reset(p, NO);
	}
}
@implementation Display {
	MTKView *view;
	Agent *agent;
	NSOperationQueue *opeQue;
	id<MTLRenderPipelineState> shapePSO, texPSO;
	id<MTLCommandQueue> commandQueue;
	id<MTLRenderCommandEncoder> rndrEnc;
	id<MTLTexture> StrSTex, StrGTex;
	id<MTLBuffer> vxBuf;
	NSMutableDictionary *symbolAttr;
	NSLock *vxBufLock, *ptclLock;
	vector_uint2 viewportSize;
	vector_float4 geomFactor;
	int nVertices, nVforLine, nPtcls;
	Particle *particles;
}
- (id<MTLTexture>)texFromStr:(NSString *)str attribute:(NSDictionary *)attr {
	NSSize size = [str sizeWithAttributes:attr];
	NSInteger pixW = ceil(size.width), pixH = ceil(size.height);
	NSBitmapImageRep *imgRep = [NSBitmapImageRep.alloc initWithBitmapDataPlanes:NULL
		pixelsWide:pixW pixelsHigh:pixH bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
		isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace
		bitmapFormat:NSBitmapFormatThirtyTwoBitLittleEndian
		bytesPerRow:pixW * 4 bitsPerPixel:32];
	NSGraphicsContext *grCtx = NSGraphicsContext.currentContext;
	NSGraphicsContext.currentContext =
		[NSGraphicsContext graphicsContextWithBitmapImageRep:imgRep];
	[[NSColor colorWithWhite:0. alpha:0.] setFill];
	[NSBezierPath fillRect:(NSRect){0, 0, pixW, pixH}];
	[str drawAtPoint:(NSPoint){0., 0.} withAttributes:attr];
	NSGraphicsContext.currentContext = grCtx;
	MTLTextureDescriptor *texDesc = [MTLTextureDescriptor
		texture2DDescriptorWithPixelFormat:view.colorPixelFormat
		width:pixW height:pixH mipmapped:NO];
	id<MTLTexture> tex = [view.device newTextureWithDescriptor:texDesc];
	[tex replaceRegion:MTLRegionMake2D(0, 0, pixW, pixH)
		mipmapLevel:0 withBytes:imgRep.bitmapData bytesPerRow:imgRep.bytesPerRow];
	return tex;
}
- (void)setupSymbolTex {
	if (symbolAttr == nil) symbolAttr = [NSMutableDictionary dictionaryWithObject:
		[NSFont systemFontOfSize:TileSize / 2 * view.sampleCount]
		forKey:NSFontAttributeName];
	symbolAttr[NSForegroundColorAttributeName] = colSymbols;
	StrSTex = [self texFromStr:@"S" attribute:symbolAttr];
	StrGTex = [self texFromStr:@"G" attribute:symbolAttr];
}
static NSColor *color_with_comp(CGFloat *comp) {
	return [NSColor colorWithColorSpace:NSColorSpace.genericRGBColorSpace
		components:comp count:4];
}
- (void)adjustPtclMemory:(BOOL)lock {
	if (lock) [ptclLock lock];
	particles = realloc(particles, sizeof(Particle) * NParticles);
	if (nPtcls < NParticles)
		for (int i = nPtcls; i < NParticles; i ++)
			particle_reset(particles + i, YES);
	nPtcls = NParticles;
	if (lock) [ptclLock unlock];
}
- (void)adjustBufferSize:(BOOL)lock {
	if (lock) [vxBufLock lock];
	nVforLine = (ptclDrawMethod == PTCLbyRectangles)? 6 :
		(ptclDrawMethod == PTCLbyTriangles)? 3 : 2;
	int newNV = NParticles * nVforLine;
	if (newNV != nVertices) {
		id<MTLBuffer> newBuf = [view.device newBufferWithLength:
			sizeof(vector_float2) * newNV options:MTLResourceStorageModeShared];
		if (newBuf != nil) {
			nVertices = newNV;
			vxBuf = newBuf;
			_lines = vxBuf.contents;
		} else {
			NParticles = nVertices / nVforLine;
			[self adjustPtclMemory:lock];
			NSAssert(newBuf, @"Failed to create shared buffer for vertices.");
		}
	}
	if (lock) [vxBufLock unlock];
}
- (instancetype)initWithView:(MTKView *)mtkView agent:(Agent *)a {
	if (!(self = [super init])) return nil;
	vxBufLock = NSLock.new;
	ptclLock = NSLock.new;
	opeQue = NSOperationQueue.new;
	agent = a;
	view = mtkView;
	view.enableSetNeedsDisplay = YES;
	view.paused = YES;
	id<MTLDevice> device = view.device = MTLCreateSystemDefaultDevice();
	NSAssert(device, @"Metal is not supported on this device");
	NSUInteger smplCnt = 1;
	while ([device supportsTextureSampleCount:smplCnt << 1]) smplCnt <<= 1;
	view.sampleCount = smplCnt;
    [self mtkView:view drawableSizeWillChange:view.drawableSize];
	view.delegate = self;

	NSError *error;
	MTLRenderPipelineDescriptor *pplnStDesc = MTLRenderPipelineDescriptor.new;
	pplnStDesc.label = @"Simple Pipeline";
	id<MTLLibrary> dfltLib = device.newDefaultLibrary;
	pplnStDesc.vertexFunction = [dfltLib newFunctionWithName:@"vertexShader"];
	pplnStDesc.fragmentFunction = [dfltLib newFunctionWithName:@"fragmentShader"];
	pplnStDesc.rasterSampleCount = view.sampleCount;
	MTLRenderPipelineColorAttachmentDescriptor *colAttDesc = pplnStDesc.colorAttachments[0];
	colAttDesc.pixelFormat = view.colorPixelFormat;
	colAttDesc.blendingEnabled = YES;
	colAttDesc.rgbBlendOperation = MTLBlendOperationAdd;
	colAttDesc.sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
	colAttDesc.destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
	shapePSO = [device newRenderPipelineStateWithDescriptor:pplnStDesc error:&error];
	NSAssert(shapePSO, @"Failed to create pipeline state for shape: %@", error);
	pplnStDesc.vertexFunction = [dfltLib newFunctionWithName:@"vertexShaderTex"];
	pplnStDesc.fragmentFunction = [dfltLib newFunctionWithName:@"fragmentShaderTex"];
	texPSO = [device newRenderPipelineStateWithDescriptor:pplnStDesc error:&error];
	NSAssert(texPSO, @"Failed to create pipeline state for texture: %@", error);
	commandQueue = device.newCommandQueue;

	colBackground = color_with_comp((CGFloat []){0., 0., 0., 1.});
	colObstacles = color_with_comp((CGFloat []){.3, .3, .3, 1.});
	colAgent = color_with_comp((CGFloat []){.3, .3, .3, 1.});
	colGridLines = color_with_comp((CGFloat []){.5, .5, .5, 1.});
	colSymbols = color_with_comp((CGFloat []){.7, .7, .7, 1.});
	colParticles = color_with_comp((CGFloat []){1., 1., 1., .2});

	[NSNotificationCenter.defaultCenter addObserverForName:keyShouldRedraw
		object:NSApp queue:nil usingBlock:^(NSNotification * _Nonnull note) {
		self->view.needsDisplay = YES;
	}];
	[NSNotificationCenter.defaultCenter addObserverForName:@"colorSymbols"
		object:NSApp queue:nil usingBlock:^(NSNotification * _Nonnull note) {
		[self setupSymbolTex];
		self->view.needsDisplay = YES;
	}];
	[NSNotificationCenter.defaultCenter addObserverForName:@"nParticles"
		object:NSApp queue:nil usingBlock:^(NSNotification * _Nonnull note) {
		[self->ptclLock lock];
		[self adjustPtclMemory:NO];
		[self->vxBufLock lock];
		[self adjustBufferSize:NO];
		[self setupVertices:NO];
		[self->vxBufLock unlock];
		[self->ptclLock unlock];
		self->view.needsDisplay = YES;
	}];
	[NSNotificationCenter.defaultCenter addObserverForName:@"ptclLifeSpan"
		object:NSApp queue:nil usingBlock:^(NSNotification * _Nonnull note) {
		NSNumber *oldValue = note.userInfo[keyOldValue];
		if (oldValue == nil) return;
		int orgVal = oldValue.intValue;
		for (int i = 0; i < self->nPtcls; i ++)
			self->particles[i].life = self->particles[i].life * LifeSpan / orgVal;
		self->view.needsDisplay = YES;
	}];
	[NSNotificationCenter.defaultCenter addObserverForName:keyChangeDrawMethod
		object:NSApp queue:nil usingBlock:^(NSNotification * _Nonnull note) {
		[self->vxBufLock lock];
		[self adjustBufferSize:NO];
		[self setupVertices:NO];
		[self->vxBufLock unlock];
		self->view.needsDisplay = YES;
	}];
	return self;
}
static simd_float3x3 trans_matrix(Particle *p) {
	float th = atan2f(p->v.y, p->v.x);
	return (simd_float3x3){
		(simd_float3){cosf(th), sinf(th), 0.},
		(simd_float3){-sinf(th), cosf(th), 0.},
		(simd_float3){p->p.x, p->p.y, 1.}};
}
- (void)setupVertices:(BOOL)lock {
	if (lock) [vxBufLock lock];
	int unit = nPtcls / NTHREADS, nVpL = nVforLine;
	for (int i = 0; i < nPtcls; i += unit) {
		Particle *pStart = particles + i;
		vector_float2 *lineStart = _lines + i * nVforLine;
		[opeQue addOperationWithBlock:^{
			for (int j = 0; j < unit; j ++) {
				Particle *p = pStart + j;
				float len = TileSize * StrokeLength / 2.,
					weight = TileSize * StrokeWidth / 2.;
				if (LifeSpan - p->life < 10) {
					float a = (LifeSpan - p->life) / 9.;
					len *= a; weight *= a;
				}
				switch (ptclDrawMethod) {
					case PTCLbyRectangles: {
						simd_float3x3 trs = trans_matrix(p);
						vector_float2 *vp = lineStart + j * nVpL;
						vp[0] = simd_mul(trs, (simd_float3){len, weight, 1.}).xy;
						vp[1] = simd_mul(trs, (simd_float3){-len, weight, 1.}).xy;
						vp[2] = simd_mul(trs, (simd_float3){len, -weight, 1.}).xy;
						vp[3] = simd_mul(trs, (simd_float3){-len, -weight, 1.}).xy;
						vp[4] = vp[2]; vp[5] = vp[1];
					} break;
					case PTCLbyTriangles: {
						simd_float3x3 trs = trans_matrix(p);
						vector_float2 *vp = lineStart + j * nVpL;
						vp[0] = simd_mul(trs, (simd_float3){len, weight, 1.}).xy;
						vp[1] = simd_mul(trs, (simd_float3){-len, 0., 1.}).xy;
						vp[2] = simd_mul(trs, (simd_float3){len, -weight, 1.}).xy;
					} break;
					case PTCLbyLines: {
						float v = hypotf(p->v.y, p->v.x);
						vector_float2 *vp = lineStart + j * nVpL;
						vp[0] = p->p + p->v / v * len;
						vp[1] = p->p - p->v / v * len;
					}}
			}
		}];
	}
	[opeQue waitUntilAllOperationsAreFinished];
	if (lock) [vxBufLock unlock];
	NSView *v = view;
	dispatch_async(dispatch_get_main_queue(), ^{ v.needsDisplay = YES; });
}
- (void)reset {
	[ptclLock lock];
	if (particles == NULL) {
		particles = malloc(sizeof(Particle) * (nPtcls = NParticles));
		[self adjustBufferSize:NO];
	}
	for (int i = 0; i < nPtcls; i ++)
		particle_reset(particles + i, YES);
	[self setupVertices:YES];
	[ptclLock unlock];
}
- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size {
    viewportSize.x = size.width;
    viewportSize.y = size.height;
    CGFloat rReal = size.width / size.height, rIdeal = (CGFloat)PTCLMaxX / PTCLMaxY;
    geomFactor = (rReal > rIdeal)?
		(vector_float4){ (rReal - rIdeal) / 2. * PTCLMaxY, 0., rReal * PTCLMaxY, PTCLMaxY} :
		(vector_float4){ 0., (1. / rReal - 1. / rIdeal) / 2. * PTCLMaxX, PTCLMaxX, PTCLMaxX / rReal};
}
- (void)setColor:(vector_float4)rgba {
	[rndrEnc setFragmentBytes:&rgba length:sizeof(rgba) atIndex:IndexColor];
}
- (void)fillRect:(NSRect)rect {
	vector_float2 vertices[4] = {
		{NSMinX(rect), NSMinY(rect)},{NSMaxX(rect), NSMinY(rect)},
		{NSMinX(rect), NSMaxY(rect)},{NSMaxX(rect), NSMaxY(rect)}};
	[rndrEnc setVertexBytes:vertices length:sizeof(vertices) atIndex:IndexVertices];
	[rndrEnc drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}
- (void)fillCircleAtCenter:(vector_float2)center radius:(float)radius nEdges:(int)nEdges {
	int nVertices = nEdges * 3;
	vector_float2 vx[nVertices];
	for (int i = 0; i < nVertices; i ++) vx[i] = center;
	for (int i = 0; i < nEdges; i ++) {
		float th = i * M_PI * 2. / nEdges;
		vx[(i * 3 - 1 + nVertices) % nVertices] =
		vx[i * 3 + 1] += (vector_float2){cosf(th) * radius, sinf(th) * radius};
	}
	[rndrEnc setVertexBytes:vx length:sizeof(vx) atIndex:IndexVertices];
	[rndrEnc drawPrimitives:MTLPrimitiveTypeTriangle
		vertexStart:0 vertexCount:nVertices];		
}
- (void)drawTexture:(id<MTLTexture>)tex at:(int *)tilePosition {
	[rndrEnc setFragmentTexture:tex atIndex:IndexTexture];
	CGFloat w = (CGFloat)StrSTex.width / view.sampleCount,
		h = (CGFloat)StrSTex.height / view.sampleCount;
	[self fillRect:(NSRect){
		tilePosition[0] * TileSize + (TileSize - w) / 2.,
		tilePosition[1] * TileSize + (TileSize - h) / 2., w, h}];
}
- (void)drawInMTKView:(nonnull MTKView *)view {
	id<MTLCommandBuffer> cmdBuf = commandQueue.commandBuffer;
	cmdBuf.label = @"MyCommand";
	MTLRenderPassDescriptor *rndrPasDesc = view.currentRenderPassDescriptor;
	if(rndrPasDesc == nil) return;
	rndrEnc = [cmdBuf renderCommandEncoderWithDescriptor:rndrPasDesc];
	rndrEnc.label = @"MyRenderEncoder";
	[rndrEnc setViewport:(MTLViewport){0., 0., viewportSize.x, viewportSize.y, 0., 1. }];
	[rndrEnc setVertexBytes:&geomFactor length:sizeof(geomFactor) atIndex:IndexGeomFactor];
	[rndrEnc setRenderPipelineState:shapePSO];
	// background
	self.color = col_to_vec(colBackground);
	[self fillRect:(NSRect){0., 0., PTCLMaxX, PTCLMaxY}];
	// Obstables
	self.color = col_to_vec(colObstacles);
	for (int i = 0; i < NObstacles; i ++) [self fillRect:(NSRect)
		{ObsP[i][0] * TileSize, ObsP[i][1] * TileSize, TileSize, TileSize}];
	// Agent
	int ix, iy;
	[agent getPositionX:&ix Y:&iy];
	self.color = col_to_vec(colAgent);
	[self fillCircleAtCenter:(vector_float2){(ix + .5) * TileSize, (iy + .5) * TileSize}
		radius:TileSize * 0.45 nEdges:16];
	// grid lines
	self.color = col_to_vec(colGridLines);
	vector_float2 vertices[NV_GRID], *vp = vertices;
	for (int i = 1; i < NGridH; i ++, vp += 2) {
		vp[0] = (vector_float2){0., TileSize * i};
		vp[1] = (vector_float2){PTCLMaxX, TileSize * i};
	}
	for (int i = 1; i < NGridW; i ++, vp += 2) {
		vp[0] = (vector_float2){TileSize * i, 0.};
		vp[1] = (vector_float2){TileSize * i, PTCLMaxY};
	}
	[rndrEnc setVertexBytes:vertices length:sizeof(vertices) atIndex:IndexVertices];
	[rndrEnc drawPrimitives:MTLPrimitiveTypeLine vertexStart:0 vertexCount:NV_GRID];
	// String "S" and "G"
	if (StrSTex == nil) [self setupSymbolTex];
	[rndrEnc setRenderPipelineState:texPSO];
	[self drawTexture:StrSTex at:StartP];
	[self drawTexture:StrGTex at:GoalP];
	// particles
	[rndrEnc setRenderPipelineState:shapePSO];
	self.color = col_to_vec(colParticles);
	[vxBufLock lock];
	[rndrEnc setVertexBuffer:vxBuf offset:0 atIndex:IndexVertices];
	[rndrEnc drawPrimitives:(ptclDrawMethod == PTCLbyLines)?
		MTLPrimitiveTypeLine : MTLPrimitiveTypeTriangle
		vertexStart:0 vertexCount:nVertices];		
	[rndrEnc endEncoding];
	[cmdBuf presentDrawable:view.currentDrawable];
	[cmdBuf commit];
	[cmdBuf waitUntilCompleted];
	[vxBufLock unlock];
}
- (void)oneStep {
	[ptclLock lock];
	NSInteger unit = nPtcls / NTHREADS;
	for (int i = 0; i < nPtcls; i += unit) {
		Particle *pStart = particles + i;
		[opeQue addOperationWithBlock:^{
			for (int j = 0; j < unit; j ++) {
				Particle *p = pStart + j;
				int ix = p->p.x / TileSize, iy = p->p.y / TileSize;
				if (ix < NGridW && iy < NGridH && Obstacles[iy][ix] == 0) particle_force(p);
				else particle_reset(p, NO);
				particle_step(p);
			}
		}];
	}
	[opeQue waitUntilAllOperationsAreFinished];
	[self setupVertices:YES];
	[ptclLock unlock];
}
@end
