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
	if (ptclDrawMethod == PTCLbyLines) { [color setStroke]; [path stroke]; }
	else { [color setFill]; [path fill]; }
}
static NSColor *col_from_vec(vector_float4 vc) {
	return [NSColor colorWithRed: vc.x green:vc.y blue:vc.z alpha:vc.w];
}
- (void)drawParticles {
	NSBezierPath *path = NSBezierPath.new;
	Particle *particles = display.particles;
	int np = display.nPtcls;
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
				draw_particle(col_from_vec(ptcl_rgb_color(p, ptclHSB, maxSpeed)), path);
		}}}
}
- (void)drawVectors:(NSInteger)n {
	static int vIndices[] = {1, 5, 8, 6, 7, 2};
	NSBezierPath *path = NSBezierPath.new;
	for (NSInteger i = 0; i < n; i ++) {
		vector_float2 *vec = display.arrowVec + i * NVERTICES_ARROW;
		[path removeAllPoints];
		[path moveToPoint:(NSPoint){vec[0].x, vec[0].y}];
		for (NSInteger j = 0; j < 6; j ++) {
			vector_float2 v = vec[vIndices[j]];
			[path lineToPoint:(NSPoint){v.x, v.y}];
		}
		[path closePath];
		[col_from_vec(display.arrowCol[i]) setFill];
		[path fill];
	}
}
static void draw_equ(NSString *name, NSPoint p) {
	[NSGraphicsContext saveGraphicsState];
	NSAffineTransform *trsMx = NSAffineTransform.transform;
	[trsMx translateXBy:TileSize * (p.x + .1) yBy:TileSize * (p.y - .1)];
	[trsMx rotateByRadians:M_PI / -2.];
	[trsMx concat];
	NSImage *img = [NSImage imageNamed:name];
	NSRect imgRect = {0., 0, TileSize * 2.8, };
	imgRect.size.height = imgRect.size.width * img.size.height / img.size.width;
	imgRect.origin.y = (TileSize * 0.8 - imgRect.size.height) / 2.;
	[img drawInRect:imgRect];
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
	// Particles, Vectors, or Q Values
	switch (display.displayMode) {
		case DispParticle: [self drawParticles]; break;
		case DispVector: [self drawVectors:N_VECTORS]; break;
		case DispQValues: [self drawVectors:NActiveGrids * NActs];
	}
	// Obstacles
	NSBezierPath *path = NSBezierPath.new;
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
	// Equations
	draw_equ(@"equationL", (NSPoint){2., 5.});
	draw_equ(@"equationP", (NSPoint){7., 6.});
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