//
//  LogoDrawer.m
//  LearningIsLife
//
//  Created by Tatsuo Unemi on 2023/01/10.
//
// Drawing Logo of the Project 7^2 by T. Unemi & D. Bisig
// in rectangle area (0,0,200,200)
//

#import "LogoDrawer.h"
#import "Comm.h"
#import "AppDelegate.h"
#import "Display.h"
#import "VecTypes.h"
#define LOGO_SIZE 200.
#define LINE_WIDTH 7.
#define RADIUS_S 11.
#define RADIUS_L 20.
#define CIRCLE_L_CX 97.5
#define CIRCLE_L_CY 95.5

static NSPoint path1[] = {
	{23, 154}, {163, 154}, {172, 154}, {180, 144}, {175, 135}, {102, 20}},
	path2[] = {{28, 42}, {113, 180}};
static NSBezierPath *get_path1(void) {
	static NSBezierPath *path = nil;
	if (path == nil) {
		path = NSBezierPath.new;
		[path moveToPoint:path1[0]];
		[path lineToPoint:path1[1]];
		[path curveToPoint:path1[4] controlPoint1:path1[2] controlPoint2:path1[3]];
		[path lineToPoint:path1[5]];
		path.lineWidth = LINE_WIDTH;
	}
	return path;
}
@implementation LogoDrawerCG {
	NSBezierPath *linePath, *smallCircle, *largeCircle;
}
- (instancetype)init {
	if (!(self = [super init])) return nil;
	linePath = NSBezierPath.new;
	[linePath moveToPoint:path2[0]];
	[linePath lineToPoint:path2[1]];
	linePath.lineWidth = 7.;
	smallCircle = [NSBezierPath bezierPathWithOvalInRect:
		(NSRect){-RADIUS_S, -RADIUS_S, RADIUS_S*2, RADIUS_S*2}];
	largeCircle = [NSBezierPath bezierPathWithOvalInRect:
		(NSRect){-RADIUS_L, -RADIUS_L, RADIUS_L*2, RADIUS_L*2}];
	return self;
}
- (void)drawByCGinRect:(NSRect)rect {
	[NSGraphicsContext saveGraphicsState];
	NSAffineTransform *trs = NSAffineTransform.transform;
	[trs translateXBy:rect.origin.x yBy:rect.origin.y];
	[trs scaleXBy:rect.size.width / LOGO_SIZE yBy:rect.size.height / LOGO_SIZE];
	[trs concat];
	[get_path1() stroke];
	[linePath stroke];
	NSAffineTransform *orgTrs = [NSAffineTransform.alloc initWithTransform:trs];
	[NSGraphicsContext restoreGraphicsState];
	[NSGraphicsContext saveGraphicsState];
	[trs translateXBy:102 yBy:20];
	[trs concat];
	[smallCircle fill];
	[NSGraphicsContext restoreGraphicsState];
	[NSGraphicsContext saveGraphicsState];
	trs.transformStruct = orgTrs.transformStruct;
	[trs translateXBy:113 yBy:180];
	[trs concat];
	[smallCircle fill];
	[NSGraphicsContext restoreGraphicsState];
	[NSGraphicsContext saveGraphicsState];
	trs.transformStruct = orgTrs.transformStruct;
	[trs translateXBy:CIRCLE_L_CX yBy:CIRCLE_L_CY];
	[trs concat];
	[largeCircle fill];
	[NSGraphicsContext restoreGraphicsState];
}
@end

#define N_CIRLCE_EDGES 32
@implementation LogoDrawerMTL {
	vector_float2 *line1Path, *line1Outline, line2Path[2], line2Delta;
	float *pointRate;
	NSInteger elementCount;
	NSUInteger startTime;
}
static float big_atan2(float y, float x) {
	float th = atan2f(y, x);
	return (th > 0.)? th : th + M_PI * 2.;
}
- (instancetype)init {
	if (!(self = [super init])) return nil;
	NSBezierPath *line1 = [get_path1() bezierPathByFlatteningPath];
	elementCount = line1.elementCount;
	line1Path = malloc(sizeof(vector_float2) * elementCount * 3);
	line1Outline = line1Path + elementCount;
	for (NSInteger i = 0; i < elementCount; i ++) {
		NSPoint pt;
		[line1 elementAtIndex:i associatedPoints:&pt];
		line1Path[i] = (vector_float2){pt.x, pt.y};
	}
	vector_float2 v1 = line1Path[0], v2 = line1Path[1], d;
	float th1 = big_atan2(v2.y - v1.y, v2.x - v1.x) + M_PI / 2., th2;
	d = (vector_float2){cosf(th1), sinf(th1)} * LINE_WIDTH / 2.;
	line1Outline[0] = v1 + d;
	line1Outline[1] = v1 - d;
	for (NSInteger i = 2; i < elementCount; i ++) {
		v1 = v2; v2 = line1Path[i];
		th2 = big_atan2(v2.y - v1.y, v2.x - v1.x) + M_PI / 2.;
		float th = (th1 + th2) / 2.;
		d = (vector_float2){cosf(th), sinf(th)} * LINE_WIDTH / 2. / cosf(th - th1);
		line1Outline[i * 2 - 2] = v1 + d;
		line1Outline[i * 2 - 1] = v1 - d;
		th1 = th2;
	}
	d = (vector_float2){cosf(th1), sinf(th1)} * LINE_WIDTH / 2.;
	line1Outline[elementCount * 2 - 2] = v2 + d;
	line1Outline[elementCount * 2 - 1] = v2 - d;

	pointRate = malloc(sizeof(float) * elementCount);
	float len = 0., dist = 0.;
	for (NSInteger i = 1; i < elementCount; i ++)
		len += simd_distance(line1Path[i - 1], line1Path[i]);
	pointRate[0] = 0.;
	for (NSInteger i = 1; i < elementCount; i ++)
		pointRate[i] = (dist += simd_distance(line1Path[i - 1], line1Path[i])) / len;
	line2Path[0] = (vector_float2){path2[0].x, path2[0].y};
	line2Path[1] = (vector_float2){path2[1].x, path2[1].y};
	d = line2Path[1] - line2Path[0];
	th1 = atan2f(d.y, d.x) + M_PI / 2.;
	line2Delta = (vector_float2){cosf(th1), sinf(th1)} * LINE_WIDTH / 2.;
	startTime = current_time_us();
	return self;
}
- (void)drawByMTL:(id<MTLRenderCommandEncoder>)rce inRect:(NSRect)rect {
	vector_float2 vx[elementCount * 2],
		scl = {rect.size.width, rect.size.height}, ofst = {rect.origin.x, rect.origin.y};
	scl /= LOGO_SIZE;
	for (NSInteger i = 0; i < elementCount * 2; i ++)
		vx[i] = line1Outline[i] * scl + ofst;
	[rce setVertexBytes:vx length:sizeof(vx) atIndex:IndexVertices];
	[rce drawPrimitives:MTLPrimitiveTypeTriangleStrip
		vertexStart:0 vertexCount:elementCount * 2];
	NSUInteger tm = current_time_us() - startTime;
	float pRate = (tm % 3000000L) / 3e6;
	vector_float2 cc = line2Path[0] + (line2Path[1] - line2Path[0]) * pRate; 
	vx[0] = line2Path[0] + line2Delta;
	vx[1] = line2Path[0] - line2Delta;
	vx[2] = cc + line2Delta;
	vx[3] = cc - line2Delta;
	for (NSInteger i = 0; i < 4; i ++) vx[i] = vx[i] * scl + ofst;
	[rce setVertexBytes:vx length:sizeof(vector_float2) * 4 atIndex:IndexVertices];
	[rce drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
	float r_scl = rect.size.width / LOGO_SIZE;
	fill_circle_at(rce, cc * scl + ofst, RADIUS_S * r_scl, N_CIRLCE_EDGES);
	pRate = (tm % 7000000L) / 7e6;
	for (NSInteger i = 1; i < elementCount; i ++) if (pRate < pointRate[i]) {
		cc = line1Path[i - 1] + (line1Path[i] - line1Path[i - 1])
			* (pRate - pointRate[i - 1]) / (pointRate[i] - pointRate[i - 1]);
		break;
	}
	fill_circle_at(rce, cc * scl + ofst, RADIUS_S * r_scl, N_CIRLCE_EDGES);
	cc = (vector_float2){CIRCLE_L_CX, CIRCLE_L_CY};
	fill_circle_at(rce, cc * scl + ofst, RADIUS_L * r_scl, N_CIRLCE_EDGES);
}
@end
