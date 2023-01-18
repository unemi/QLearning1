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
- (void)drawEqu:(NSString *)name at:(NSPoint)p {
	NSImage *img = [NSImage imageNamed:name];
	NSRect imgRect = {0., 0, TileSize * 2.8, };
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
	[trsMx translateXBy:TileSize * (p.x + .1) yBy:TileSize * (p.y - .1)];
	[trsMx rotateByRadians:M_PI / -2.];
	[trsMx concat];
	imgRect.origin.y = (TileSize * 0.8 - imgRect.size.height) / 2.;
	[imgRep drawInRect:imgRect];
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
	CGFloat scale = 1., dWhRate = recordView.hidden? (CGFloat)NGridW / NGridH : 16. / 9.;
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
	// Grid lines
	NSBezierPath *path = NSBezierPath.new;
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
	// Obstacles
	[path removeAllPoints];
	NSRect obstRect = {0., 0., TileSize, TileSize};
	for (int i = 0; i < NObstacles; i ++) {
		obstRect.origin = (NSPoint){ObsP[i][0] * TileSize, ObsP[i][1] * TileSize};
		[path appendBezierPathWithRect:obstRect];
	}
	[colObstacles setFill];
	[path fill];
	// Equations
	[self drawEqu:@"equationL" at:(NSPoint){ObsP[0][0], ObsP[0][1] + 3}];
	[self drawEqu:@"equationP" at:(NSPoint){ObsP[4][0], ObsP[4][1] + 3}];
	// Project Logo
	if (logoDrawer == nil) logoDrawer = LogoDrawerCG.new;
	[colSymbols set];
	[logoDrawer drawByCGinRect:
		(NSRect){ObsP[3][0] * TileSize, ObsP[3][1] * TileSize, TileSize, TileSize}];
	// Info view -- steps and goals
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
