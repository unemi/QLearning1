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
#define NTHREADS nCores

int NParticles = 120000, LifeSpan = 80;
float Mass = 2., Friction = 0.9, StrokeLength = 0.2, StrokeWidth = .01, MaxSpeed = 0.05;
NSColor *colBackground, *colObstacles, *colAgent,
	*colGridLines, *colSymbols, *colParticles;
PTCLColorMode ptclColorMode = PTCLconstColor;
PTCLDrawMethod ptclDrawMethod = PTCLbyLines;
NSInteger nCores;
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
}
vector_float4 col_to_vec(NSColor * _Nonnull col) {
	CGFloat c[4] = {0, 0, 0, 1};
	[[col colorUsingColorSpace:NSColorSpace.genericRGBColorSpace]
		getComponents:c];
	return (vector_float4){c[0], c[1], c[2], c[3]};
}
void draw_in_bitmap(NSBitmapImageRep * _Nonnull imgRep,
	void (^ _Nonnull block)(NSBitmapImageRep * _Nonnull bm)) {
	NSGraphicsContext *orgCtx = NSGraphicsContext.currentContext;
	NSGraphicsContext.currentContext =
		[NSGraphicsContext graphicsContextWithBitmapImageRep:imgRep];
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
	int *fp = FieldP[lrand48() % NActiveGrids];
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
	NSOperationQueue *opeQue;
	id<MTLRenderPipelineState> shapePSO, texPSO;
	id<MTLCommandQueue> commandQueue;
	id<MTLTexture> StrSTex, StrGTex, equLTex, equPTex;
	id<MTLBuffer> vxBuf, colBuf;
	NSMutableDictionary *symbolAttr;
	NSLock *vxBufLock, *ptclLock;
	vector_uint2 viewportSize;
	float maxSpeed;
}
- (id<MTLTexture>)textureDrawnBy:(void (^)(NSBitmapImageRep *bm))block
	size:(NSSize)size scaleFactor:(CGFloat)sclFctr {
	NSInteger pixW = ceil(size.width * sclFctr), pixH = ceil(size.height * sclFctr);
	NSBitmapImageRep *imgRep = create_rgb_bitmap(pixW, pixH, NULL);
	imgRep.size = size;
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
	return [self textureDrawnBy:^(NSBitmapImageRep *bm) {
		[[NSColor colorWithWhite:0. alpha:0.] setFill];
		[NSBezierPath fillRect:(NSRect){0, 0, bm.size}];
		[str drawAtPoint:(NSPoint){0., 0.} withAttributes:attr];
	} size:[str sizeWithAttributes:attr] scaleFactor:1.];
}
- (id<MTLTexture>)texFromImageName:(NSString *)name {
	NSImage *image = [NSImage imageNamed:name];
	NSSize sz = image.size;
	return [self textureDrawnBy:^(NSBitmapImageRep *bm) {
		[[NSColor colorWithWhite:0. alpha:0.] setFill];
		[NSBezierPath fillRect:(NSRect){0, 0, bm.size}];
		NSAffineTransform *trs = NSAffineTransform.transform;
		[trs translateXBy:0. yBy:sz.width];
		[trs rotateByRadians:M_PI / -2.];
		[trs concat];
		[image drawInRect:(NSRect){0., 0., sz}];
	} size:(NSSize){sz.height, sz.width} scaleFactor:300./72.];
}
- (void)setupSymbolTex {
	if (symbolAttr == nil) symbolAttr = [NSMutableDictionary dictionaryWithObject:
		[NSFont userFontOfSize:TileSize / 2 * view.sampleCount]
		forKey:NSFontAttributeName];
	symbolAttr[NSForegroundColorAttributeName] = colSymbols;
	StrSTex = [self texFromStr:@"S" attribute:symbolAttr];
	StrGTex = [self texFromStr:@"G" attribute:symbolAttr];
}
- (Particle *)adjustPtclMemory {
	Particle *newMem = _particles;
	if (_nPtcls != NParticles) {
		newMem = realloc(_particles, sizeof(Particle) * NParticles);
		if (newMem == NULL) @throw @0;
		if (_nPtcls < NParticles)
			for (int i = _nPtcls; i < NParticles; i ++)
				particle_reset(newMem + i, YES);
	}
	return newMem;
}
- (id<MTLBuffer>)adjustColBufferSize {
	id<MTLBuffer> newColBuf = colBuf;
	NSInteger nColBuf = (colBuf == nil)? 0 : colBuf.length / sizeof(vector_float4);
	NSInteger newNC = (_displayMode == DispParticle)?
			(ptclColorMode == PTCLconstColor)? 0 : NParticles :
		(_displayMode == DispVector)? N_VECTORS : NActiveGrids * NActs;
	if (nColBuf != newNC) {
		if (newNC > 0) {
			newColBuf = [view.device newBufferWithLength:
				sizeof(vector_float4) * newNC options:MTLResourceStorageModeShared];
			if (newColBuf == nil) @throw @1;
		} else colBuf = newColBuf = nil;
	}
	return newColBuf;
}
- (id<MTLBuffer>)adjustVxBufferSize {
	id<MTLBuffer> newVxBuf = vxBuf;
	NSInteger nVertices = (vxBuf == nil)? 0 : vxBuf.length / sizeof(vector_float2);
	int newNV = (_displayMode == DispParticle)?
		NParticles * ((ptclDrawMethod == PTCLbyRectangles)? 6 :
			(ptclDrawMethod == PTCLbyTriangles)? 3 : 2) :
		((_displayMode == DispVector)? N_VECTORS : NActiveGrids * NActs) * NVERTICES_ARROW;
	if (newNV != nVertices) {
		newVxBuf = [view.device newBufferWithLength:
			sizeof(vector_float2) * newNV options:MTLResourceStorageModeShared];
		if (newVxBuf == nil) @throw @2;
	}
	if (_displayMode != DispParticle && _arrowVec == NULL) {
		_arrowVec = malloc(sizeof(vector_float2) * N_VECTORS * NVERTICES_ARROW);
		_arrowCol = malloc(sizeof(vector_float4) * N_VECTORS);
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
		_particles = newPTCLs; _nPtcls = NParticles;
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
	nCores = NSProcessInfo.processInfo.activeProcessorCount;
	vxBufLock = NSLock.new;
	ptclLock = NSLock.new;
	opeQue = NSOperationQueue.new;
	_agent = a;
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
#ifdef DEBUG
	NSLog(@"%ld CPUs, Sample count = %ld", nCores, smplCnt);
#endif

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
		for (int i = 0; i < self.nPtcls; i ++)
			self.particles[i].life = self.particles[i].life * LifeSpan / orgVal;
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
		Particle *pStart = _particles + i * _nPtcls / NTHREADS;
		vector_float4 *colorsStart = colors + i * _nPtcls / NTHREADS;
		int unit = (i < NTHREADS - 1)? _nPtcls / NTHREADS :
			_nPtcls - (int)(_nPtcls * (NTHREADS - 1) / NTHREADS);
		[opeQue addOperationWithBlock:^{
			for (int j = 0; j < unit; j ++)
				colorsStart[j] = ptcl_rgb_color(pStart + j, ptclHSB, self->maxSpeed);
		}];
	}
	[opeQue waitUntilAllOperationsAreFinished];
}
- (void)setupVertices {
	int nVpL = (int)(vxBuf.length / sizeof(vector_float2) / _nPtcls);
	vector_float2 *lines = vxBuf.contents;
	float mxSpd[NTHREADS];
	memset(mxSpd, 0, sizeof(mxSpd));
	for (int i = 0; i < NTHREADS; i ++) {
		Particle *pStart = _particles + i * _nPtcls / NTHREADS;
		vector_float2 *lineStart = lines + i * _nPtcls / NTHREADS * nVpL;
		float *mxSpdP = mxSpd + i;
		int unit = (i < NTHREADS - 1)? _nPtcls / NTHREADS :
			_nPtcls - (int)(_nPtcls * (NTHREADS - 1) / NTHREADS);
		[opeQue addOperationWithBlock:^{
			for (int j = 0; j < unit; j ++) {
				Particle *p = pStart + j;
				float spd = simd_length(p->v);
				if (*mxSpdP < spd) *mxSpdP = spd;
				vector_float2 sz = particle_size(p);
				switch (nVpL) {
					case 6: {
						simd_float3x3 trs = particle_tr_mx(p);
						vector_float2 *vp = lineStart + j * nVpL;
						vp[0] = simd_mul(trs, (simd_float3){sz.x, sz.y, 1.}).xy;
						vp[1] = simd_mul(trs, (simd_float3){-sz.x, sz.y, 1.}).xy;
						vp[2] = simd_mul(trs, (simd_float3){sz.x, -sz.y, 1.}).xy;
						vp[3] = simd_mul(trs, (simd_float3){-sz.x, -sz.y, 1.}).xy;
						vp[4] = vp[2]; vp[5] = vp[1];
					} break;
					case 3: {
						simd_float3x3 trs = particle_tr_mx(p);
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
static void set_arrow_shape(vector_float2 *v, simd_float3x3 *trs) {
	static vector_float3 v3[NVERTICES_ARROW] = {
		{-1., AR_TAIL_Y, 1.}, {-1., -AR_TAIL_Y, 1.}, {AR_HEAD_X, AR_TAIL_Y, 1.},
		{-1., -AR_TAIL_Y, 1.}, {AR_HEAD_X, AR_TAIL_Y, 1.}, {AR_HEAD_X, -AR_TAIL_Y, 1.},
		{1., 0., 1.}, {AR_HEAD_X, 1., 1.}, {AR_HEAD_X, -1., 1.}
	};
	for (int i = 0; i < NVERTICES_ARROW; i ++)
		v[i] = simd_mul(*trs, v3[i]).xy;
}
- (void)setupArrowsForVecFld {
	vector_float4 vec[N_VECTORS];
	Particle ptcl;
	for (int i = 0, vIdx = 0; i < NActiveGrids; i ++) {
		int ix = FieldP[i][0], iy = FieldP[i][1];
		for (int j = 0; j < N_VECTOR_GRID; j ++)
		for (int k = 0; k < N_VECTOR_GRID; k ++, vIdx ++) {
			vec[vIdx].x = ptcl.p.x = (ix + (k + .5) / N_VECTOR_GRID) * TileSize;
			vec[vIdx].y = ptcl.p.y = (iy + (j + .5) / N_VECTOR_GRID) * TileSize;
			particle_force(&ptcl);
			vec[vIdx].z = simd_length(ptcl.f);
			vec[vIdx].w = atan2f(ptcl.f.y, ptcl.f.x);
		}
	}
	float maxV = -1e10;
	for (int i = 0; i < N_VECTORS; i ++)
		if (maxV < vec[i].z) maxV = vec[i].z;
	vector_float4 bgCol = col_to_vec(colBackground),
		maxCol = (simd_reduce_add(bgCol.rgb) > 1.5)?
			(vector_float4){0., 0., 0., 1.} : (vector_float4){1., 1., 1., 1.};
	for (int i = 0; i < N_VECTORS; i ++) {
		vector_float2 cs = {cosf(vec[i].w), sinf(vec[i].w)};
		cs *= (float)TileSize / N_VECTOR_GRID / 2.;
		simd_float3x3 trs = {
			(simd_float3){cs.x, cs.y, 0.},
			(simd_float3){-cs.y * .5, cs.x * .5, 0.},
			(simd_float3){vec[i].x, vec[i].y, 1.}};
		set_arrow_shape(_arrowVec + i * NVERTICES_ARROW, &trs);
		float grade = vec[i].z / maxV;
		_arrowCol[i] = bgCol * (1. - grade) + maxCol * grade;
	}
}
- (void)setupArrowsForQValues {
	float minQ = 1e10, maxQ = -1e10;
	for (int i = 0; i < NActiveGrids; i ++) {
		vector_float4 Q = QTable[FieldP[i][1]][FieldP[i][0]];
		float minq = simd_reduce_min(Q), maxq = simd_reduce_max(Q);
		if (minQ > minq) minQ = minq;
		if (maxQ < maxq) maxQ = maxq;
	}
	float (^getGrade)(float) = ((maxQ - minQ) < 1.)?
		(minQ < 0.)? ^(float q) { return q - minQ; } : ^(float q) { return q; } :
		(minQ < 0.)? ^(float q) { return (q - minQ) / (maxQ - minQ); } :
			^(float q) { return q / maxQ; };
	vector_float4 bgCol = col_to_vec(colBackground),
		maxCol = (simd_reduce_add(bgCol.rgb) > 1.5)?
			(vector_float4){0., 0., 0., 1.} : (vector_float4){1., 1., 1., 1.};
	for (int i = 0, vIdx = 0; i < NActiveGrids; i ++) {
		int ix = FieldP[i][0], iy = FieldP[i][1];
		vector_float4 Q = QTable[iy][ix];
		vector_float2 center = {(ix + .5) * TileSize, (iy + .5) * TileSize};
		for (int j = 0; j < NActs; j ++, vIdx ++) {
			float th = (1 - j) * M_PI / 2.;
			vector_float2 cs = {cosf(th), sinf(th)}; cs *= TileSize / 6.;
			simd_float3x3 trs = {
				(simd_float3){cs.x, cs.y, 0.},
				(simd_float3){-cs.y, cs.x, 0.},
				(simd_float3){center.x + cs.x * 2., center.y + cs.y * 2., 1.}};
			set_arrow_shape(_arrowVec + vIdx * NVERTICES_ARROW, &trs);
			float grade = getGrade(Q[j]);
			_arrowCol[vIdx] = bgCol * (1. - grade) + maxCol * grade;
		}
	}
}
- (void)setDisplayMode:(DisplayMode)newMode {
	if (_displayMode == newMode) return;
	_displayMode = newMode;
	[self adjustColBufferSize];
	[self adjustVxBufferSize];
	switch (_displayMode) {
		case DispParticle:
		[self setupVertices];
		[self setupParticleColors]; break;
		case DispVector: [self setupArrowsForVecFld]; break;
		case DispQValues: [self setupArrowsForQValues];
	}
	view.needsDisplay = YES;
}
- (void)reset {
	if (_particles != NULL) {
		[ptclLock lock];
		for (int i = 0; i < _nPtcls; i ++)
			particle_reset(_particles + i, YES);
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
#ifdef DEBUG
	NSLog(@"Drawable size = %.1f x %.1f", size.width, size.height);
#endif
}
typedef id<MTLRenderCommandEncoder> RCE;
static void set_color(RCE rce, vector_float4 rgba) {
	[rce setVertexBytes:&rgba length:sizeof(rgba) atIndex:IndexColors];
}
static void fill_rect(RCE rce, NSRect rect) {
	vector_float2 vertices[4] = {
		{NSMinX(rect), NSMinY(rect)},{NSMaxX(rect), NSMinY(rect)},
		{NSMinX(rect), NSMaxY(rect)},{NSMaxX(rect), NSMaxY(rect)}};
	uint nv = 0;
	[rce setVertexBytes:vertices length:sizeof(vertices) atIndex:IndexVertices];
	[rce setVertexBytes:&nv length:sizeof(nv) atIndex:IndexNVforP];
	[rce drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}
static void fill_circle_at(RCE rce, vector_float2 center, float radius, int nEdges) {
	int nVertices = nEdges * 2 + 1;
	vector_float2 vx[nVertices];
	for (int i = 0; i < nVertices; i ++) vx[i] = center;
	for (int i = 0; i <= nEdges; i ++) {
		float th = i * M_PI * 2. / nEdges;
		vx[i * 2] += (vector_float2){cosf(th) * radius, sinf(th) * radius};
	}
	[rce setVertexBytes:vx length:sizeof(vx) atIndex:IndexVertices];
	[rce drawPrimitives:MTLPrimitiveTypeTriangleStrip
		vertexStart:0 vertexCount:nVertices];
}
static void draw_texture(RCE rce, id<MTLTexture> tex,
	int *tilePosition, NSUInteger sampleCount) {
	[rce setFragmentTexture:tex atIndex:IndexTexture];
	CGFloat w = (CGFloat)tex.width / sampleCount,
		h = (CGFloat)tex.height / sampleCount;
	fill_rect(rce, (NSRect){
		tilePosition[0] * TileSize + (TileSize - w) / 2.,
		tilePosition[1] * TileSize + (TileSize - h) / 2., w, h});
}
static void draw_equtex(RCE rce, id<MTLTexture> tex,
	int *tileP, NSUInteger sampleCount) {
	[rce setFragmentTexture:tex atIndex:IndexTexture];
	NSRect rect = {(tileP[0] + .1) * TileSize, (tileP[1] + .1) * TileSize,
		TileSize * .8, TileSize * 2.8};
	CGFloat newW = rect.size.height * tex.width / tex.height;
	rect.origin.x += (rect.size.width - newW) / 2.;
	rect.size.width = newW;
	fill_rect(rce, rect);
}
- (void)setupArrows:(RCE)rce n:(int)n {
	uint nv = NVERTICES_ARROW;
	memcpy(vxBuf.contents, _arrowVec, sizeof(vector_float2) * n * nv);
	memcpy(colBuf.contents, _arrowCol, sizeof(vector_float4) * n);
	[rce setVertexBytes:&nv length:sizeof(nv) atIndex:IndexNVforP];
	[rce setVertexBuffer:vxBuf offset:0 atIndex:IndexVertices];
	[rce setVertexBuffer:colBuf offset:0 atIndex:IndexColors];
	[rce drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:n * nv];
}
- (void)drawScene:(nonnull MTKView *)view commandBuffer:(id<MTLCommandBuffer>)cmdBuf {
	MTLRenderPassDescriptor *rndrPasDesc = view.currentRenderPassDescriptor;
	if(rndrPasDesc == nil) return;
	RCE rce = [cmdBuf renderCommandEncoderWithDescriptor:rndrPasDesc];
	rce.label = @"MyRenderEncoder";
	[rce setViewport:(MTLViewport){0., 0., viewportSize.x, viewportSize.y, 0., 1. }];
	vector_float2 geomFactor = {PTCLMaxX, PTCLMaxY};
	[rce setVertexBytes:&geomFactor length:sizeof(geomFactor) atIndex:IndexGeomFactor];
	[rce setRenderPipelineState:shapePSO];
	// background
	set_color(rce, col_to_vec(colBackground));
	fill_rect(rce, (NSRect){0., 0., PTCLMaxX, PTCLMaxY});
	// Agent
	int ix, iy;
	[_agent getPositionX:&ix Y:&iy];
	set_color(rce, col_to_vec(colAgent));
	fill_circle_at(rce,
		(vector_float2){(ix + .5) * TileSize, (iy + .5) * TileSize}, TileSize * 0.45, 32);
	// String "S" and "G"
	if (StrSTex == nil) [self setupSymbolTex];
	[rce setRenderPipelineState:texPSO];
	draw_texture(rce, StrSTex, StartP, view.sampleCount);
	draw_texture(rce, StrGTex, GoalP, view.sampleCount);
	// particles, vectors, or Q values
	[rce setRenderPipelineState:shapePSO];
	switch (_displayMode) {
		case DispParticle: {
			uint nv = 0, nVertices = (vxBuf == NULL)? 0 :
				(uint)(vxBuf.length / sizeof(vector_float2));
			if (colBuf != nil) {
				nv = nVertices / _nPtcls;
				[rce setVertexBuffer:colBuf offset:0 atIndex:IndexColors];
			} else set_color(rce, col_to_vec(colParticles));
			[rce setVertexBytes:&nv length:sizeof(nv) atIndex:IndexNVforP];
			[rce setVertexBuffer:vxBuf offset:0 atIndex:IndexVertices];
			[rce drawPrimitives:(ptclDrawMethod == PTCLbyLines)?
				MTLPrimitiveTypeLine : MTLPrimitiveTypeTriangle
				vertexStart:0 vertexCount:nVertices];
		} break;
		case DispVector: [self setupArrows:rce n:N_VECTORS]; break;
		case DispQValues: [self setupArrows:rce n:NActiveGrids * NActs];
	}
	// Obstables
	set_color(rce, col_to_vec(colObstacles));
	for (int i = 0; i < NObstacles; i ++) fill_rect(rce, (NSRect)
		{ObsP[i][0] * TileSize, ObsP[i][1] * TileSize, TileSize, TileSize});
	// grid lines
	set_color(rce, col_to_vec(colGridLines));
	vector_float2 vertices[NV_GRID], *vp = vertices;
	for (int i = 1; i < NGridH; i ++, vp += 2) {
		vp[0] = (vector_float2){0., TileSize * i};
		vp[1] = (vector_float2){PTCLMaxX, TileSize * i};
	}
	for (int i = 1; i < NGridW; i ++, vp += 2) {
		vp[0] = (vector_float2){TileSize * i, 0.};
		vp[1] = (vector_float2){TileSize * i, PTCLMaxY};
	}
	[rce setVertexBytes:vertices length:sizeof(vertices) atIndex:IndexVertices];
	[rce drawPrimitives:MTLPrimitiveTypeLine vertexStart:0 vertexCount:NV_GRID];
	// equations
	if (equLTex == nil) {
		equLTex = [self texFromImageName:@"equationL"];
		equPTex = [self texFromImageName:@"equationP"];
	}
	[rce setRenderPipelineState:texPSO];
	draw_equtex(rce, equLTex, (int []){2, 2}, view.sampleCount);
	draw_equtex(rce, equPTex, (int []){7, 3}, view.sampleCount);
	[rce endEncoding];
}
- (void)drawInMTKView:(nonnull MTKView *)view {
	id<MTLCommandBuffer> cmdBuf = commandQueue.commandBuffer;
	cmdBuf.label = @"MyCommand";
	[self drawScene:view commandBuffer:cmdBuf];
	[cmdBuf presentDrawable:view.currentDrawable];
	[cmdBuf commit];
}
- (void)oneStepForParticles {
	[ptclLock lock];
	NSInteger unit = _nPtcls / NTHREADS;
	for (int i = 0; i < _nPtcls; i += unit) {
		Particle *pStart = _particles + i;
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
}
- (void)oneStep {
	switch (_displayMode) {
		case DispParticle: [self oneStepForParticles]; break;
		case DispVector: [self setupArrowsForVecFld]; break;
		case DispQValues: [self setupArrowsForQValues];
	}
	in_main_thread(^{ self->view.needsDisplay = YES; });
}
- (NSBitmapImageRep *)imageBitmapWithSize:(NSSize)size scaleFactor:(CGFloat)sclFactor
	drawBlock:(void (^)(NSBitmapImageRep *bm))block {
	view.framebufferOnly = NO;
	id<MTLCommandBuffer> cmdBuf = commandQueue.commandBuffer;
	cmdBuf.label = @"OffScreenCommand";
	[self drawScene:view commandBuffer:cmdBuf];
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
