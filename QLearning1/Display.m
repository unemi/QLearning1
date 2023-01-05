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
#define NTHREADS 16

int NParticles = 120000, LifeSpan = 80;
float Mass = 2., Friction = 0.9, StrokeLength = 0.2, StrokeWidth = .01, MaxSpeed = 0.05;
NSColor *colBackground, *colObstacles, *colAgent,
	*colGridLines, *colSymbols, *colParticles;
PTCLColorMode ptclColorMode = PTCLconstColor;
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
	float v = simd_length(p->f);
	if (v < 1e-8) {
		float th = drand48() * M_PI * 2.;
		p->v = (vector_float2){cosf(th), sinf(th)} * .01;
	} else p->v = p->f / v * .01;
	p->life = isRandom? lrand48() % LifeSpan : LifeSpan;
}
static void particle_step(Particle *p) {
	if ((-- p->life) <= 0) particle_reset(p, NO);
	else {
		p->v = (p->v + p->f / Mass) * Friction;
		float v = simd_length(p->v);
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
	id<MTLBuffer> vxBuf, colBuf;
	NSMutableDictionary *symbolAttr;
	NSLock *vxBufLock, *ptclLock;
	vector_uint2 viewportSize;
	float maxSpeed;
	int nPtcls;
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
		[NSFont userFontOfSize:TileSize / 2 * view.sampleCount]
		forKey:NSFontAttributeName];
	symbolAttr[NSForegroundColorAttributeName] = colSymbols;
	StrSTex = [self texFromStr:@"S" attribute:symbolAttr];
	StrGTex = [self texFromStr:@"G" attribute:symbolAttr];
}
static NSColor *color_with_comp(CGFloat *comp) {
	return [NSColor colorWithColorSpace:NSColorSpace.genericRGBColorSpace
		components:comp count:4];
}
- (Particle *)adjustPtclMemory {
	Particle *newMem = particles;
	if (nPtcls != NParticles) {
		newMem = realloc(particles, sizeof(Particle) * NParticles);
		if (newMem == NULL) @throw @0;
		if (nPtcls < NParticles)
			for (int i = nPtcls; i < NParticles; i ++)
				particle_reset(newMem + i, YES);
	}
	return newMem;
}
- (id<MTLBuffer>)adjustColBufferSize {
	id<MTLBuffer> newColBuf = colBuf;
	NSInteger nColBuf = (colBuf == nil)? 0 : colBuf.length / sizeof(vector_float4);
	if (ptclColorMode != PTCLconstColor) {
		if (nColBuf != NParticles) {
			newColBuf = [view.device newBufferWithLength:
				sizeof(vector_float4) * NParticles options:MTLResourceStorageModeShared];
			if (newColBuf == nil) @throw @1;
		}
	} else newColBuf = nil;
	return newColBuf;
}
- (id<MTLBuffer>)adjustVxBufferSize {
	id<MTLBuffer> newVxBuf = vxBuf;
	NSInteger nVertices = (vxBuf == nil)? 0 : vxBuf.length / sizeof(vector_float2);
	int nV4Line = (ptclDrawMethod == PTCLbyRectangles)? 6 :
		(ptclDrawMethod == PTCLbyTriangles)? 3 : 2;
	int newNV = NParticles * nV4Line;
	if (newNV != nVertices) {
		newVxBuf = [view.device newBufferWithLength:
			sizeof(vector_float2) * newNV options:MTLResourceStorageModeShared];
		if (newVxBuf == nil) @throw @2;
	}
	return newVxBuf;
}
- (void)adjustMemoryForNParticles {
	[ptclLock lock];
	[vxBufLock lock];
	@try {
		Particle *newPTCLs = [self adjustPtclMemory];
		id<MTLBuffer> newColBuf = [self adjustColBufferSize];
		id<MTLBuffer> newVxBuf = [self adjustVxBufferSize];
		particles = newPTCLs; nPtcls = NParticles;
		colBuf = newColBuf;
		vxBuf = newVxBuf;
		[self setupVertices];
		[self setupParticleColors];
	} @catch (id x) {}
	[vxBufLock unlock];
	[ptclLock unlock];
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
	colParticles = color_with_comp((CGFloat []){1., 1., 1., .1});

	[NSNotificationCenter.defaultCenter addObserverForName:keyShouldRedraw
		object:NSApp queue:nil usingBlock:^(NSNotification * _Nonnull note) {
		self->view.needsDisplay = YES;
	}];
	[NSNotificationCenter.defaultCenter addObserverForName:@"colorSymbols"
		object:NSApp queue:nil usingBlock:^(NSNotification * _Nonnull note) {
		[self setupSymbolTex];
		self->view.needsDisplay = YES;
	}];
	[NSNotificationCenter.defaultCenter addObserverForName:@"colorParticles"
		object:NSApp queue:nil usingBlock:^(NSNotification * _Nonnull note) {
		[self setupParticleColors];
		self->view.needsDisplay = YES;
	}];
	[NSNotificationCenter.defaultCenter addObserverForName:@"nParticles"
		object:NSApp queue:nil usingBlock:^(NSNotification * _Nonnull note) {
		[self adjustMemoryForNParticles];
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
	[NSNotificationCenter.defaultCenter addObserverForName:keyColorMode
		object:NSApp queue:nil usingBlock:^(NSNotification * _Nonnull note) {
		[self->vxBufLock lock];
		@try {
			id<MTLBuffer> newColBuf = [self adjustColBufferSize];
			self->colBuf = newColBuf;
			[self setupParticleColors];
		} @catch (id x) {}
		[self->vxBufLock unlock];
		self->view.needsDisplay = YES;
	}];
	[NSNotificationCenter.defaultCenter addObserverForName:keyDrawMethod
		object:NSApp queue:nil usingBlock:^(NSNotification * _Nonnull note) {
		[self->vxBufLock lock];
		@try {
			id<MTLBuffer> newVxBuf = [self adjustVxBufferSize];
			self->vxBuf = newVxBuf;
			[self setupVertices];
		} @catch (id x) {}
		[self->vxBufLock unlock];
		self->view.needsDisplay = YES;
	}];
	return self;
}
simd_float3x3 trans_matrix(Particle *p) {
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
vector_float4 ptcl_hsb_color(void) {
	CGFloat h, s, b, a;
	[colParticles getHue:&h saturation:&s brightness:&b alpha:&a];
	return (vector_float4){h, s, b, a};
}
vector_float4 ptcl_rgb_color(Particle * _Nonnull p, vector_float4 hsba, float maxSpeed) {
	return hsb_to_rgb((vector_float4){(ptclColorMode == PTCLangleColor)?
			fmodf(atan2f(p->v.y, p->v.x) / (2 * M_PI) + hsba.x + 1.f, 1.f) :
			grade_to_hue(simd_length(p->v) / maxSpeed),
		(hsba.y + .1) * .5, hsba.z, hsba.w});
}
vector_float2 particle_size(Particle * _Nonnull p) {
	vector_float2 sz = (vector_float2){
		TileSize * StrokeLength / 2., TileSize * StrokeWidth / 2.};
	if (LifeSpan - p->life < 10) sz *= (LifeSpan - p->life) / 9.;
	return sz;
}
- (void)setupParticleColors {
	if (colBuf == nil) return;
	vector_float4 *colors = colBuf.contents, ptclHSB = ptcl_hsb_color();
	for (int i = 0; i < NTHREADS; i ++) {
		Particle *pStart = particles + i * nPtcls / NTHREADS;
		vector_float4 *colorsStart = colors + i * nPtcls / NTHREADS;
		int unit = (i < NTHREADS - 1)? nPtcls / NTHREADS :
			nPtcls - nPtcls * (NTHREADS - 1) / NTHREADS;
		[opeQue addOperationWithBlock:^{
			for (int j = 0; j < unit; j ++)
				colorsStart[j] = ptcl_rgb_color(pStart + j, ptclHSB, self->maxSpeed);
		}];
	}
	[opeQue waitUntilAllOperationsAreFinished];
}
- (void)setupVertices {
	int nVpL = (int)(vxBuf.length / sizeof(vector_float2) / nPtcls);
	vector_float2 *lines = vxBuf.contents;
	float mxSpd[NTHREADS];
	memset(mxSpd, 0, sizeof(mxSpd));
	for (int i = 0; i < NTHREADS; i ++) {
		Particle *pStart = particles + i * nPtcls / NTHREADS;
		vector_float2 *lineStart = lines + i * nPtcls / NTHREADS * nVpL;
		float *mxSpdP = mxSpd + i;
		int unit = (i < NTHREADS - 1)? nPtcls / NTHREADS :
			nPtcls - nPtcls * (NTHREADS - 1) / NTHREADS;
		[opeQue addOperationWithBlock:^{
			for (int j = 0; j < unit; j ++) {
				Particle *p = pStart + j;
				float spd = simd_length(p->v);
				if (*mxSpdP < spd) *mxSpdP = spd;
				vector_float2 sz = particle_size(p);
				switch (nVpL) {
					case 6: {
						simd_float3x3 trs = trans_matrix(p);
						vector_float2 *vp = lineStart + j * nVpL;
						vp[0] = simd_mul(trs, (simd_float3){sz.x, sz.y, 1.}).xy;
						vp[1] = simd_mul(trs, (simd_float3){-sz.x, sz.y, 1.}).xy;
						vp[2] = simd_mul(trs, (simd_float3){sz.x, -sz.y, 1.}).xy;
						vp[3] = simd_mul(trs, (simd_float3){-sz.x, -sz.y, 1.}).xy;
						vp[4] = vp[2]; vp[5] = vp[1];
					} break;
					case 3: {
						simd_float3x3 trs = trans_matrix(p);
						vector_float2 *vp = lineStart + j * nVpL;
						vp[0] = simd_mul(trs, (simd_float3){sz.x, sz.y, 1.}).xy;
						vp[1] = simd_mul(trs, (simd_float3){-sz.x, 0., 1.}).xy;
						vp[2] = simd_mul(trs, (simd_float3){sz.x, -sz.y, 1.}).xy;
					} break;
					case 2: {
						float v = simd_length(p->v);
						vector_float2 *vp = lineStart + j * nVpL;
						vp[0] = p->p + p->v / v * sz.x;
						vp[1] = p->p - p->v / v * sz.x;
					}}
			}
		}];
	}
	[opeQue waitUntilAllOperationsAreFinished];
	maxSpeed = fmaxf(mxSpd[0], TileSize * .005);
	for (int i = 1; i < NTHREADS; i ++) if (maxSpeed < mxSpd[i]) maxSpeed = mxSpd[i];
}
- (void)reset {
	if (particles != NULL) {
		[ptclLock lock];
		for (int i = 0; i < nPtcls; i ++)
			particle_reset(particles + i, YES);
		[vxBufLock lock];
		if (ptclColorMode != PTCLconstColor)
			[self setupParticleColors];
		[self setupVertices];
		[vxBufLock unlock];
		[ptclLock unlock];
	} else [self adjustMemoryForNParticles];
	view.needsDisplay = YES;
}
- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size {
    viewportSize.x = size.width;
    viewportSize.y = size.height;
}
- (void)setColor:(vector_float4)rgba {
	[rndrEnc setVertexBytes:&rgba length:sizeof(rgba) atIndex:IndexColors];
}
- (void)fillRect:(NSRect)rect {
	vector_float2 vertices[4] = {
		{NSMinX(rect), NSMinY(rect)},{NSMaxX(rect), NSMinY(rect)},
		{NSMinX(rect), NSMaxY(rect)},{NSMaxX(rect), NSMaxY(rect)}};
	uint nv = 0;
	[rndrEnc setVertexBytes:vertices length:sizeof(vertices) atIndex:IndexVertices];
	[rndrEnc setVertexBytes:&nv length:sizeof(nv) atIndex:IndexNVforP];
	[rndrEnc drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}
- (void)fillCircleAtCenter:(vector_float2)center radius:(float)radius nEdges:(int)nEdges {
	int nVertices = nEdges * 2 + 1;
	vector_float2 vx[nVertices];
	for (int i = 0; i < nVertices; i ++) vx[i] = center;
	for (int i = 0; i <= nEdges; i ++) {
		float th = i * M_PI * 2. / nEdges;
		vx[i * 2] += (vector_float2){cosf(th) * radius, sinf(th) * radius};
	}
	[rndrEnc setVertexBytes:vx length:sizeof(vx) atIndex:IndexVertices];
	[rndrEnc drawPrimitives:MTLPrimitiveTypeTriangleStrip
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
	vector_float2 geomFactor = {PTCLMaxX, PTCLMaxY};
	[rndrEnc setVertexBytes:&geomFactor length:sizeof(geomFactor) atIndex:IndexGeomFactor];
	[rndrEnc setRenderPipelineState:shapePSO];
	// background
	self.color = col_to_vec(colBackground);
	[self fillRect:(NSRect){0., 0., PTCLMaxX, PTCLMaxY}];
	// Agent
	int ix, iy;
	[agent getPositionX:&ix Y:&iy];
	self.color = col_to_vec(colAgent);
	[self fillCircleAtCenter:(vector_float2){(ix + .5) * TileSize, (iy + .5) * TileSize}
		radius:TileSize * 0.45 nEdges:32];
	// String "S" and "G"
	if (StrSTex == nil) [self setupSymbolTex];
	[rndrEnc setRenderPipelineState:texPSO];
	[self drawTexture:StrSTex at:StartP];
	[self drawTexture:StrGTex at:GoalP];
	// particles
	[rndrEnc setRenderPipelineState:shapePSO];
	uint nv = 0, nVertices = (vxBuf == NULL)? 0 :
		(uint)(vxBuf.length / sizeof(vector_float2));
	if (colBuf != nil) {
		nv = nVertices / nPtcls;
		[rndrEnc setVertexBuffer:colBuf offset:0 atIndex:IndexColors];
	} else self.color = col_to_vec(colParticles);
	[rndrEnc setVertexBytes:&nv length:sizeof(nv) atIndex:IndexNVforP];
	[vxBufLock lock];
	[rndrEnc setVertexBuffer:vxBuf offset:0 atIndex:IndexVertices];
	[rndrEnc drawPrimitives:(ptclDrawMethod == PTCLbyLines)?
		MTLPrimitiveTypeLine : MTLPrimitiveTypeTriangle
		vertexStart:0 vertexCount:nVertices];		
	// Obstables
	self.color = col_to_vec(colObstacles);
	for (int i = 0; i < NObstacles; i ++) [self fillRect:(NSRect)
		{ObsP[i][0] * TileSize, ObsP[i][1] * TileSize, TileSize, TileSize}];
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
//
	[rndrEnc endEncoding];
	[cmdBuf presentDrawable:view.currentDrawable];
	[cmdBuf commit];
//	[cmdBuf waitUntilCompleted];
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
	[vxBufLock lock];
	[self setupVertices];
	[self setupParticleColors];
	[vxBufLock unlock];
	[ptclLock unlock];
	NSView *v = view;
	in_main_thread(^{ v.needsDisplay = YES; });
}
//
- (Agent *)agent { return agent; }
- (Particle *)particles { return particles; }
- (int)nParticles { return nPtcls; }
@end
