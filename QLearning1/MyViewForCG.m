//
//  MyViewForCG.m
//  QLearning1
//
//  Created by Tatsuo Unemi on 2023/01/05.
//

#import "MyViewForCG.h"
#import "Display.h"
#import "AppDelegate.h"
#import "Agent.h"

@implementation MyViewForCG {
	Display *display;
	NSBitmapImageRep *imgCache;
}
- (instancetype)initWithFrame:(NSRect)frameRect display:(Display *)disp {
	if (!(self = [super initWithFrame:frameRect])) return nil;
	display = disp;
	return self;
}
static void draw_symbol(NSString *str, NSDictionary *attr, int p[2]) {
	NSSize size = [str sizeWithAttributes:attr];
	[str drawAtPoint:(NSPoint){
		p[0] * TileSize + (TileSize - size.width) / 2.,
		p[1] * TileSize + (TileSize - size.height) / 2.} withAttributes:attr];
}
static NSPoint trans_point(simd_float3x3 trs, float x, float y) {
	simd_float3 p = simd_mul(trs, (simd_float3){x, y, 1.});
	return (NSPoint){p.x, p.y};
}
static void set_particle_path(Particle *p, NSBezierPath *path) {
	vector_float2 sz = particle_size(p);
	[path removeAllPoints];
	switch (ptclDrawMethod) {
		case PTCLbyLines: {
			vector_float2 vv = p->v / simd_length(p->v) * sz.x, pp = p->p - vv;
			[path moveToPoint:(NSPoint){pp.x, pp.y}];
			pp = p->p + p->v / simd_length(p->v) * sz.x;
			[path lineToPoint:(NSPoint){pp.x, pp.y}];
		} break;
		case PTCLbyTriangles: {
			simd_float3x3 trs = trans_matrix(p);
			[path moveToPoint:trans_point(trs, sz.x, sz.y)];
			[path lineToPoint:trans_point(trs, -sz.x, 0.)];
			[path lineToPoint:trans_point(trs, sz.x, -sz.y)];
		} break;
		case PTCLbyRectangles: {
			simd_float3x3 trs = trans_matrix(p);
			[path moveToPoint:trans_point(trs, sz.x, sz.y)];
			[path lineToPoint:trans_point(trs, -sz.x, sz.y)];
			[path lineToPoint:trans_point(trs, -sz.x, -sz.y)];
			[path lineToPoint:trans_point(trs, sz.x, -sz.y)];
		}
	}
}
static void draw_particle(NSColor *color, NSBezierPath *path) {
	if (ptclDrawMethod == PTCLbyLines) {
		[color setStroke];
		[path stroke];
	} else {
		[color setFill];
		[path fill];
	}
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
	CGFloat scale = 1.;
	if (whRate > (CGFloat)NGridW / NGridH) {
		scale = pSize.height / (NGridH * TileSize);
		offset.x = (pSize.width - NGridW * TileSize * scale) / 2.;
	} else {
		scale = pSize.width / (NGridW * TileSize);
		offset.y = (pSize.height - NGridH * TileSize * scale) / 2.;
	}
	[[NSColor colorWithWhite:0. alpha:0.] setFill];
	[NSBezierPath fillRect:self.bounds];
	NSAffineTransform *trans = NSAffineTransform.transform;
	if (rotate) {
		[trans rotateByDegrees:90.];
		[trans translateXBy:0. yBy:-pSize.height];
	}
	[trans scaleBy:scale];
	[trans translateXBy:offset.x yBy:offset.y];
	[trans concat];
	// background
	[colBackground setFill];
	[NSBezierPath fillRect:(NSRect){0., 0., NGridW * TileSize, NGridH * TileSize}];
	// Agent
	int ix, iy;
	[display.agent getPositionX:&ix Y:&iy];
	[colAgent setFill];
	[[NSBezierPath bezierPathWithOvalInRect:(NSRect)
		{(ix + .05) * TileSize, (iy + .05) * TileSize, TileSize * .9, TileSize * .9}] fill];
	// Symbols
	NSDictionary *attr = @{NSFontAttributeName:[NSFont userFontOfSize:TileSize / 2],
		NSForegroundColorAttributeName:colSymbols};
	draw_symbol(@"S", attr, StartP);
	draw_symbol(@"G", attr, GoalP);
	// Particles
	NSBezierPath *path = NSBezierPath.new;
	Particle *particles = display.particles;
	int np = display.nParticles;
	float maxSpeed = TileSize * .005;
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
			vector_float4 ptclHSB = ptcl_hsb_color();
			for (int i = 0; i < np; i ++) {
				Particle *p = particles + i;
				set_particle_path(p, path);
				vector_float4 vc = ptcl_rgb_color(p, ptclHSB, maxSpeed);
				draw_particle([NSColor colorWithRed:vc.x green:vc.y blue:vc.z alpha:vc.w], path);
			}
		}
	}
	// Obstacles
	NSRect obstRect = {0., 0., TileSize, TileSize};
	for (int i = 0; i < NObstacles; i ++) {
		obstRect.origin = (NSPoint){ObsP[i][0] * TileSize, ObsP[i][1] * TileSize};
		[path appendBezierPathWithRect:obstRect];
	}
	[colObstacles setFill];
	[path fill];
	// Grid lines
	[path removeAllPoints];
	for (int i = 1; i < NGridH; i ++) {
		[path moveToPoint:(NSPoint){0., i * TileSize}];
		[path relativeLineToPoint:(NSPoint){NGridW * TileSize, 0}];
	}
	for (int i = 1; i < NGridW; i ++) {
		[path moveToPoint:(NSPoint){i * TileSize, 0.}];
		[path relativeLineToPoint:(NSPoint){0., NGridH * TileSize}];
	}
	[colGridLines setStroke];
	[path stroke];
	[NSGraphicsContext restoreGraphicsState];
}
- (NSBitmapImageRep *)bitmapImageChache:( void (^_Nullable)(NSView *))block {
	NSBitmapImageRep *bm = [self bitmapImageRepForCachingDisplayInRect:self.bounds];
	NSGraphicsContext *orgCtx = NSGraphicsContext.currentContext;
	NSGraphicsContext.currentContext =
		[NSGraphicsContext graphicsContextWithBitmapImageRep:bm];
	[self drawByCoreGraphics];
	if (block != nil) block(self);
	NSGraphicsContext.currentContext = orgCtx;
	return bm;
}
- (void)drawRect:(NSRect)rect {
	if ([NSGraphicsContext.currentContext.attributes
		[NSGraphicsContextRepresentationFormatAttributeName]
		isEqualToString:NSGraphicsContextPDFFormat]) [self drawByCoreGraphics];
	else {
		if (imgCache == nil) imgCache = [self bitmapImageChache:nil];
		[imgCache draw];
	}
}
@end
