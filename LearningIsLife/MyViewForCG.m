//
//  MyViewForCG.m
//  LearningIsLife
//
//  Created by Tatsuo Unemi on 2023/01/05.
//

#import "MyViewForCG.h"
#import "MainWindow.h"
#import "Display.h"
#import "Agent.h"
#import "LogoDrawer.h"
#import "RecordView.h"

@implementation MyViewForCG {
	Display __weak *display;
	NSView __weak *infoView;
	RecordView __weak *recordView;
	NSBitmapImageRep *imgCache;
	LogoDrawerCG *logoDrawer;
}
- (instancetype)initWithFrame:(NSRect)frameRect display:(Display *)disp
	infoView:(NSView *)iview recordView:(RecordView *)recView {
	if (!(self = [super initWithFrame:frameRect])) return nil;
	display = disp;
	infoView = iview;
	recordView = recView;
	return self;
}
static void draw_symbol(NSString *str, NSDictionary *attr, simd_int2 p) {
	NSSize size = [str sizeWithAttributes:attr];
	simd_float2 fp = simd_float(p * tileSize) +
		simd_float(tileSize) / 2.f - (simd_float2){size.width, size.height} / 2.f;
	[str drawAtPoint:(NSPoint){fp.x, fp.y} withAttributes:attr];
}
static NSPoint trans_point(simd_float3x3 trs, float x, float y) {
	simd_float3 p = simd_mul(trs, (simd_float3){x, y, 1.});
	return (NSPoint){p.x, p.y};
}
static void set_particle_path(Particle *p, NSBezierPath *path) {
	simd_float2 sz = particle_size(p);
	[path removeAllPoints];
	switch (ptclShapeMode) {
		case PTCLbyLines: {
			simd_float2 vv = p->v / simd_length(p->v) * sz.x, pp = p->p - vv;
			[path moveToPoint:(NSPoint){pp.x, pp.y}];
			pp = p->p + p->v / simd_length(p->v) * sz.x;
			[path lineToPoint:(NSPoint){pp.x, pp.y}];
		} break;
		case PTCLbyTriangles: {
			simd_float3x3 trs = particle_tr_mx(p);
			[path moveToPoint:trans_point(trs, sz.x, sz.y)];
			[path lineToPoint:trans_point(trs, -sz.x, 0.)];
			[path lineToPoint:trans_point(trs, sz.x, -sz.y)];
		} break;
		case PTCLbyRectangles: {
			simd_float3x3 trs = particle_tr_mx(p);
			[path moveToPoint:trans_point(trs, sz.x, sz.y)];
			[path lineToPoint:trans_point(trs, -sz.x, sz.y)];
			[path lineToPoint:trans_point(trs, -sz.x, -sz.y)];
			[path lineToPoint:trans_point(trs, sz.x, -sz.y)];
		}
	}
}
static void draw_particle(NSColor *color, NSBezierPath *path) {
	if (ptclShapeMode == PTCLbyLines) { [color setStroke]; [path stroke]; }
	else { [color setFill]; [path fill]; }
}
static NSColor *col_from_vec(simd_float4 vc) {
	return [NSColor colorWithRed: vc.x green:vc.y blue:vc.z alpha:vc.w];
}
- (void)drawParticles {
	NSBezierPath *path = NSBezierPath.new;
	Particle *particles = display.particleMem.mutableBytes;
	int np = display.nPtcls;
	float maxSpeed = tileSize.x * .005;
	switch (ptclColorMode) {
		case PTCLconstColor:
		for (int i = 0; i < np; i ++) {
			set_particle_path(particles + i, path);
			draw_particle(colParticles, path);
		} break;
		case PTCLspeedColor:
		for (int i = 0; i < np; i ++) {
			float spd = simd_length(particles[i].v);
			if (maxSpeed < spd) maxSpeed = spd;
		}
		case PTCLangleColor: {
			simd_float4 ptclHSB = ptcl_hsb_color();
			for (int i = 0; i < np; i ++) {
				Particle *p = particles + i;
				set_particle_path(p, path);
				draw_particle(col_from_vec(ptcl_rgb_color(p, ptclHSB, maxSpeed)), path);
		}}}
}
- (void)drawVectors:(NSInteger)n {
	static int vIndices[] = {1, 5, 8, 6, 7, 2};
	NSBezierPath *path = NSBezierPath.new;
	for (NSInteger i = 0; i < n; i ++) {
		simd_float2 *vec = display.arrowVec + i * NVERTICES_ARROW;
		[path removeAllPoints];
		[path moveToPoint:(NSPoint){vec[0].x, vec[0].y}];
		for (NSInteger j = 0; j < 6; j ++) {
			simd_float2 v = vec[vIndices[j]];
			[path lineToPoint:(NSPoint){v.x, v.y}];
		}
		[path closePath];
		[col_from_vec(display.arrowCol[i]) setFill];
		[path fill];
	}
}
- (void)drawEqu:(NSString *)name at:(NSPoint)p {
	NSImage *img = [NSImage imageNamed:name];
	NSRect imgRect = {0., 0, tileSize.y * 2.8, };
	NSSize imgSz = img.size;
	imgRect.size.height = imgRect.size.width * imgSz.height / imgSz.width;
	NSBitmapImageRep *imgRep = [self bitmapImageRepForCachingDisplayInRect:imgRect];
	if (imgRep.bitsPerPixel != 32) {
		error_msg(@"Bits per pixel of chache image is not 32.", nil);
		return;
	}
	union { unsigned long ul; unsigned char c[4]; } c;
	c.ul = EndianU32_NtoB(col_to_ulong(colSymbols));
	draw_in_bitmap(imgRep, ^(NSBitmapImageRep * _Nonnull bm) {
		[[NSColor colorWithWhite:0. alpha:0.] setFill];
		[NSBezierPath fillRect:imgRect];
		[img drawInRect:imgRect]; });
	unsigned char *row = imgRep.bitmapData;
	for (NSInteger iy = 0; iy < imgRep.pixelsHigh; iy ++, row += imgRep.bytesPerRow) {
		unsigned char *bytes = row;
		for (NSInteger ix = 0; ix < imgRep.pixelsWide; ix ++, bytes += 4) {
			if (bytes[3] == 0) memset(bytes, 0, 4);
			else for (NSInteger i = 0; i < 3; i ++) bytes[i] = c.c[i] * (bytes[3] / 255.);
		}
	}
	[NSGraphicsContext saveGraphicsState];
	NSAffineTransform *trsMx = NSAffineTransform.transform;
	[trsMx translateXBy:tileSize.x * (p.x + .1) yBy:tileSize.y * (p.y - .1)];
	[trsMx rotateByRadians:M_PI / -2.];
	[trsMx concat];
	NSRect dstRect = imgRect;
	dstRect.origin.y = (tileSize.x * 0.8 - imgRect.size.height) / 2.;
//	[imgRep drawInRect:imgRect];
	[imgRep drawInRect:dstRect fromRect:imgRect
		operation:NSCompositingOperationSourceOver
		fraction:1. respectFlipped:NO hints:nil];
	[NSGraphicsContext restoreGraphicsState];
}
- (void)drawByCoreGraphics {
	[NSGraphicsContext saveGraphicsState];
	NSSize pSize = self.bounds.size;
	CGFloat whRate = pSize.width / pSize.height;
	BOOL rotate = NO;
	if (whRate < 1.) {
		whRate = 1. / whRate;
		rotate = YES;
		CGFloat d = pSize.width; pSize.width = pSize.height; pSize.height = d;
	}
	NSPoint offset = {0., 0.};
	CGFloat scale = 1., dWhRate = recordView.hidden? (CGFloat)PTCLMaxX / PTCLMaxY : 16. / 9.;
	if (whRate > dWhRate) {
		scale = pSize.height / PTCLMaxY;
		offset.x = (pSize.width - pSize.height * dWhRate) / 2.;
	} else {
		scale = pSize.width / (PTCLMaxY * dWhRate);
		offset.y = (pSize.height - pSize.width / dWhRate) / 2.;
	}
	[[NSColor colorWithWhite:0. alpha:0.] setFill];
	[NSBezierPath fillRect:self.bounds];
	NSAffineTransform *trans = NSAffineTransform.transform;
	if (rotate) {
		[trans rotateByDegrees:90.];
		[trans translateXBy:0. yBy:-pSize.height];
	}
	[trans translateXBy:offset.x yBy:offset.y];
	[trans scaleBy:scale];
	[trans concat];
	[NSBezierPath clipRect:(NSRect){0., 0., PTCLMaxY * dWhRate, PTCLMaxY}];
	// background
	[colBackground setFill];
	[NSBezierPath fillRect:(NSRect){0., 0., PTCLMaxX, PTCLMaxY}];
	// Agent
	[colAgent setFill];
	float agentDiameter = simd_reduce_min(tileSize) * .9f;
	simd_float2 aPos = (simd_float(display.agent.position) + .5f) * simd_float(tileSize)
		- agentDiameter / 2.f;
	[[NSBezierPath bezierPathWithOvalInRect:(NSRect)
		{aPos.x, aPos.y, agentDiameter, agentDiameter}] fill];
	// Symbols
	NSDictionary *attr = @{NSFontAttributeName:[NSFont userFontOfSize:tileSize.x / 2],
		NSForegroundColorAttributeName:colSymbols};
	draw_symbol(@"S", attr, StartP);
	draw_symbol(@"G", attr, GoalP);
	// Particles, Vectors, or Q Values
	switch (display.displayMode) {
		case DispParticle: [self drawParticles]; break;
		case DispVector: [self drawVectors:N_VECTORS]; break;
		case DispQValues: [self drawVectors:nActiveGrids * NActs];
		default: break;
	}
	// Grid lines
	NSBezierPath *path = NSBezierPath.new;
	for (int i = 1; i < nGridH; i ++) {
		[path moveToPoint:(NSPoint){0., i * tileSize.y}];
		[path relativeLineToPoint:(NSPoint){PTCLMaxX, 0}];
	}
	for (int i = 1; i < nGridW; i ++) {
		[path moveToPoint:(NSPoint){i * tileSize.x, 0.}];
		[path relativeLineToPoint:(NSPoint){0., PTCLMaxY}];
	}
	[colGridLines setStroke];
	[path stroke];
	// Obstacles
	[path removeAllPoints];
	NSRect obstRect = {0., 0., tileSize.x, tileSize.y};
	for (int i = 0; i < nObstacles; i ++) {
		simd_int2 oo = ObsP[i] * tileSize;
		obstRect.origin = (NSPoint){oo.x, oo.y};
		[path appendBezierPathWithRect:obstRect];
	}
	[colObstacles setFill];
	[path fill];
	if (obstaclesMode != ObsExternal) {
		// Equations
		[self drawEqu:@"equationL" at:(NSPoint){ObsP[0].x, ObsP[0].y + 3}];
		[self drawEqu:@"equationP" at:(NSPoint){ObsP[4].x, ObsP[4].y + 3}];
		// Project Logo
		if (logoDrawer == nil) logoDrawer = LogoDrawerCG.new;
		[colSymbols set];
		float logoDim = simd_reduce_min(tileSize);
		simd_float2 logoP = (simd_float(ObsP[3]) + .5) * simd_float(tileSize) - logoDim / 2.;
		[logoDrawer drawByCGinRect:(NSRect){logoP.x, logoP.y, logoDim, logoDim}];
	}
	// Info view -- steps, goals and FPS
	[NSGraphicsContext saveGraphicsState];
	trans = NSAffineTransform.transform;
	[trans scaleBy:PTCLMaxY / infoView.superview.frame.size.height];
	NSPoint origin = infoView.frame.origin;
	[trans translateXBy:origin.x yBy:origin.y];
	[trans concat];
	for (NSView *v in infoView.subviews) {
		[NSGraphicsContext saveGraphicsState];
		trans = NSAffineTransform.transform;
		origin = v.frame.origin; 
		[trans translateXBy:origin.x yBy:origin.y];
		[trans concat];
		[v drawRect:v.bounds];
		[NSGraphicsContext restoreGraphicsState];
	}
	[NSGraphicsContext restoreGraphicsState];
	// Recorded images
	if (dWhRate == 16. / 9.) {
		trans = NSAffineTransform.transform;
		[trans translateXBy:PTCLMaxX yBy:0.];
		[trans scaleBy:PTCLMaxY / recordView.frame.size.height];
		[trans concat];
		[recordView drawRect:recordView.bounds];
	}
	[NSGraphicsContext restoreGraphicsState];
}
- (void)drawRect:(NSRect)rect {
	if ([NSGraphicsContext.currentContext.attributes
		[NSGraphicsContextRepresentationFormatAttributeName]
		isEqualToString:NSGraphicsContextPDFFormat]) [self drawByCoreGraphics];
	else {
		if (imgCache == nil) {
			imgCache = [self bitmapImageRepForCachingDisplayInRect:self.bounds];
			draw_in_bitmap(imgCache, ^(NSBitmapImageRep * _Nonnull bm) {
				[self drawByCoreGraphics];
			});
		}
		[imgCache draw];
	}
}
@end
