//
//  SpeedColPanel.m
//  Learning is Life
//
//  Created by Tatsuo Unemi on 2023/06/29.
//

#import "SpeedColPanel.h"
#import "Display.h"
#import "AppDelegate.h"
#import "ControlPanel.h"
@import CoreImage.CIFilterBuiltins;

static void draw_checker_background(NSRect rect) {
	static CIFilter<CICheckerboardGenerator> *generator = nil;
	if (generator == nil) {
		generator = [CIFilter checkerboardGeneratorFilter];
		generator.color0 = [CIColor colorWithRed:.33 green:.33 blue:.33];
		generator.color1 = [CIColor colorWithRed:.67 green:.67 blue:.67];
		generator.width = 3;
	}
	[generator.outputImage drawAtPoint:rect.origin fromRect:rect
		operation:NSCompositingOperationCopy fraction:1.];
}
NSString *keySpeedColors = @"speedColors";
NSInteger nSpeedColors = 3;
SpeedColor *speedColors = (SpeedColor[3]){
	{0., {.667, 1., .667, .1}},
	{.6, {.167, 1., .667, .15}},
	{1., {0., 1., .667, .2}}
};
NSData *spdColUD, *spdColFD;
int FDBTSpdCol = 0;

BOOL spdcol_is_equal_to(NSData *data) {
	if (nSpeedColors != data.length / sizeof(SpeedColor)) return NO;
	return memcmp(speedColors, data.bytes, nSpeedColors * sizeof(SpeedColor)) == 0;
}
static NSColor *color_from_hsb(simd_float4 hsb) {
	return [NSColor colorWithHue:hsb.x saturation:hsb.y brightness:hsb.z alpha:hsb.w];
}
static simd_float4 color_to_hsb(NSColor *color) {
	CGFloat c[4];
	[[color colorUsingColorSpace:NSColorSpace.genericRGBColorSpace]
		getHue:c saturation:c+1 brightness:c+2 alpha:c+3];
	return (simd_float4){c[0], c[1], c[2], c[3]};
}

@interface KeyColorWell : NSView {
	CGFloat prevFrameX;
}
@property BOOL active;
@property simd_float4 hsba;
@end

@interface GradientBar () {
	NSRect colWelFrm, colBarFrm;
	NSBitmapImageRep *imgRep;
	KeyColorWell *activeColorWell;
	BOOL initialization, changed;
	CGFloat useAlpha;
}
- (CGFloat)useAlpha;
- (void)addColorWell:(KeyColorWell *)cw;
- (void)checkAddCWEnabled;
- (void)colorChanged;
- (void)changeColor:(void (^)(void))undoHandler;
@end

@implementation KeyColorWell
- (void)drawRect:(NSRect)rect {
	if (_active) [NSColor.grayColor setFill];
	else [NSColor.lightGrayColor setFill];
	[NSBezierPath fillRect:rect];
	NSRect bounds = self.bounds;
	CGFloat inset = fmin(bounds.size.width, bounds.size.height) * .2;
	NSRect colRect = NSInsetRect(bounds, inset, inset);
	CGFloat alpha = _hsba.w;
	alpha += (1. - alpha) * (100. - ((GradientBar *)self.superview).useAlpha) / 100.;
	if (alpha < 1.) draw_checker_background(colRect);
	[[color_from_hsb(_hsba) colorWithAlphaComponent:alpha] setFill];
	[NSBezierPath fillRect:NSIntersectionRect(rect, colRect)];
}
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (void)moveXTo:(CGFloat)newX undoable:(BOOL)undoable {
	NSPoint origin = self.frame.origin;
	if (newX == origin.x) return;
	[self setFrameOrigin:(NSPoint){newX, origin.y}];
	[(GradientBar *)self.superview colorChanged];
	[(GradientBar *)self.superview checkAddCWEnabled];
	if (undoable) {
		CGFloat orgX = origin.x;
		[(GradientBar *)self.superview changeColor:
			^{ [self moveXTo:orgX undoable:YES]; }];
	}
}
- (void)mouseDown:(NSEvent *)event {
	prevFrameX = self.frame.origin.x;
}
- (void)mouseUp:(NSEvent *)event {
	switch (event.clickCount) {
		case 1: {
			NSColorPanel *colPnl = NSColorPanel.sharedColorPanel;
			colPnl.action = nil;
			colPnl.color = color_from_hsb(_hsba);
			colPnl.action = @selector(changeCol:);
			colPnl.target = self;
			[colPnl orderFront:nil];
		} break;
		case 0: if (prevFrameX != self.frame.origin.x) {
			CGFloat orgX = prevFrameX;
			[(GradientBar *)self.superview changeColor:
				^{ [self moveXTo:orgX undoable:YES]; }];
			[(GradientBar *)self.superview checkAddCWEnabled];
		}
	}
}
- (void)mouseDragged:(NSEvent *)event {
	NSRect frm = self.frame;
	[self moveXTo:fmax(0., fmin(NSMaxX(self.superview.bounds) - frm.size.width,
		frm.origin.x + event.deltaX)) undoable:NO];
}
- (void)changeColorTo:(simd_float4)newColor {
	simd_float4 orgColor = _hsba;
	_hsba = newColor;
	[(GradientBar *)self.superview changeColor:^{ [self changeColorTo:orgColor]; }];
	[(GradientBar *)self.superview colorChanged];
}
- (void)changeCol:(NSColorPanel *)colPnl {
	[self changeColorTo:color_to_hsb(colPnl.color)];
}
@end

@implementation GradientBar
- (instancetype)initWithCoder:(NSCoder *)coder {
	if (!(self = [super initWithCoder:coder])) return nil;
	NSSize size = self.frame.size;
	CGFloat sz = size.height * .5;
	colWelFrm = (NSRect){0., 0., sz, sz};
	colBarFrm = (NSRect){sz/2., sz, size.width - sz, size.height - sz};
	[NSColorPanel.sharedColorPanel addObserver:self forKeyPath:@"target"
		options:NSKeyValueObservingOptionNew|NSKeyValueObservingOptionOld context:nil];
	self.refusesFirstResponder = NO;
	return self;
}
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (CGFloat)useAlpha { return useAlpha; }
- (void)awakeFromNib {
	if (addBtn != nil) {
		addBtn.target = self;
		addBtn.action = @selector(addNewColorWell:);
		addBtn.enabled = YES;
	}
	if (removeBtn != nil) {
		removeBtn.target = self;
		removeBtn.action = @selector(removeActiveColorWell:);
		removeBtn.enabled = NO;
	}
	if (alphaSld != nil) {
		useAlpha = alphaSld.doubleValue;
		alphaSld.target = self;
		alphaSld.action = @selector(changeUseAlpha:);
	} else useAlpha = 50.;
}
- (NSArray<KeyColorWell *> *)colorWells {
	return [self.subviews sortedArrayUsingComparator:^(NSView *v1, NSView *v2) {
		CGFloat x1 = v1.frame.origin.x, x2 = v2.frame.origin.x;
		return (x1 < x2)? NSOrderedAscending :
			(x1 > x2)? NSOrderedDescending : NSOrderedSame;
	}];
}
- (SpeedColor *)values:(NSInteger *)nCols {
	NSArray<KeyColorWell *> *colWels = [self colorWells];
	if (nCols != NULL) *nCols = colWels.count;
	if (colWels.count == 0) return NULL;
	SpeedColor *mem = malloc(sizeof(SpeedColor) * colWels.count);
	for (NSInteger i = 0; i < colWels.count; i ++) {
		mem[i].x = colWels[i].frame.origin.x / colBarFrm.size.width;
		mem[i].hsb = colWels[i].hsba;
	}
	return mem;
}
- (NSData *)dataOfValues {
	NSInteger nCols = 0;
	SpeedColor *mem = [self values:&nCols];
	return (mem == NULL)? nil :
		[NSData dataWithBytesNoCopy:mem length:nCols * sizeof(SpeedColor) freeWhenDone:YES];
}
static simd_float4 interpolated_hsb(simd_float4 c1, simd_float4 c2, float rate) {
	if (c1.y < 1e-6) c1.x = c2.x;
	else if (c2.y < 1e-6) c2.x = c1.x;
	else if (c2.x - c1.x > .5) c1.x += 1.;
	else if (c1.x - c2.x > .5) c2.x += 1.;
	simd_float4 hsb = c1 * (1. - rate) + c2 * rate;
	if (hsb.x > 1.) hsb.x -= 1.;
	return hsb;
}
simd_float4 grade_to_hsb(float grade) {
	if (nSpeedColors == 0) return (simd_float4){0.,0.,0.,0.};
	NSInteger idx;
	for (idx = 0; idx < nSpeedColors; idx ++)
		if (grade < speedColors[idx].x) break;
	if (idx == 0) return speedColors[0].hsb;
	else if (idx == nSpeedColors) return speedColors[nSpeedColors - 1].hsb;
	else return interpolated_hsb(speedColors[idx - 1].hsb, speedColors[idx].hsb,
		(grade - speedColors[idx - 1].x) / (speedColors[idx].x - speedColors[idx - 1].x));
}
static void fill_pixels(unsigned char *buf, NSInteger bpr, NSInteger pxW, NSInteger pxH,
	simd_float4 c1, simd_float4 c2) {
	for (NSInteger px = 0; px < pxW; px ++) {
		simd_float4 rgb = hsb_to_rgb(interpolated_hsb(c1, c2, (float)px / pxW), YES) * 255.;
		unsigned char rgba[4] = {rgb.x, rgb.y, rgb.z, rgb.w};
		for (NSInteger i = 0; i < pxH; i ++)
			memcpy(buf + (i * bpr) + px * 4, rgba, 4);
	}
}
- (void)checkAddCWEnabled {
	NSArray<KeyColorWell *> *colWels = [self colorWells];
	@try {
		if (colWels.count == 0) @throw @YES;
		if (activeColorWell == nil) @throw @(colWels[0].frame.origin.x > 0.);
		CGFloat x = activeColorWell.frame.origin.x;
		if (activeColorWell == colWels.lastObject) @throw @(x < colBarFrm.size.width);
		@throw @(x != colWels[[colWels indexOfObject:activeColorWell] + 1].frame.origin.x);
	} @catch (NSNumber *num) { addBtn.enabled = num.boolValue; }
}
- (void)addColorWellAt:(CGFloat)x color:(simd_float4)col {
	colWelFrm.origin.x = (self.bounds.size.width - colWelFrm.size.width) * x;
	KeyColorWell *cw = [KeyColorWell.alloc initWithFrame:colWelFrm];
	cw.hsba = col;
	[self addColorWell:cw];
}
- (void)setupColors:(SpeedColor *)colors count:(NSInteger)count {
	initialization = YES;
	while (self.subviews.count > count) [self.subviews.lastObject removeFromSuperview];
	for (NSInteger i = 0; i < count; i ++) {
		if (i < self.subviews.count) {
			KeyColorWell *cw = self.subviews[i];
			[cw setFrameOrigin:(NSPoint){colors[i].x * colBarFrm.size.width, colWelFrm.origin.y}];
			cw.hsba = colors[i].hsb;
		} else [self addColorWellAt:colors[i].x color:colors[i].hsb];
	}
	self.needsDisplay = YES;
	initialization = NO;
	[self hideColorPanelIfOpened];
	[self checkAddCWEnabled];
}
- (void)resetupColorsWells:(SpeedColor *)colors count:(NSInteger)count
	colWels:(NSArray<KeyColorWell *> *)colWels {
	NSMutableArray *toRemove = NSMutableArray.new;
	for (KeyColorWell *cw in self.subviews)
		if ([colWels indexOfObject:cw] == NSNotFound) [toRemove addObject:cw];
	for (KeyColorWell *cw in toRemove) [cw removeFromSuperview];
	for (NSInteger i = 0; i < count; i ++) {
		KeyColorWell *cw = colWels[i];
		[cw setFrameOrigin:(NSPoint){colors[i].x * colBarFrm.size.width, colWelFrm.origin.y}];
		cw.hsba = colors[i].hsb;
		if (cw.superview == nil) [self addSubview:cw];
	}
	[self hideColorPanelIfOpened];
	[self checkAddCWEnabled];
}
- (void)drawRect:(NSRect)rect {
	if (imgRep == nil) {
		CGFloat scale = self.window.screen.backingScaleFactor;
		NSInteger pxW = colBarFrm.size.width * scale, pxH = colBarFrm.size.height * scale;
		imgRep = [NSBitmapImageRep.alloc initWithBitmapDataPlanes:NULL
			pixelsWide:pxW pixelsHigh:pxH bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES
			isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:pxW*4 bitsPerPixel:32];
		changed = YES;
	}
	if (changed) {
		NSInteger nCols = 0;
		SpeedColor *mem = [self values:&nCols];
		simd_float4 prevC = {0.,0.,0.,0.}, newC;
		if (nCols > 0) prevC = mem[0].hsb;
		prevC.w += (1. - prevC.w) * (100. - useAlpha) / 100.;
		NSInteger prevPx = 0, newPx = 0;
		unsigned char *bmBuf = imgRep.bitmapData;
		for (NSInteger i = 0; i < nCols; i ++) {
			newC = mem[i].hsb;
			newC.w += (1. - newC.w) * (100. - useAlpha) / 100.;
			newPx = round(mem[i].x * imgRep.pixelsWide);
			fill_pixels(bmBuf + prevPx * 4,
				imgRep.bytesPerRow, newPx - prevPx, imgRep.pixelsHigh, prevC, newC);
			prevC = newC;
			prevPx = newPx;
		}
		if (newPx < imgRep.pixelsWide) fill_pixels(bmBuf + newPx * 4, imgRep.bytesPerRow,
			imgRep.pixelsWide - newPx, imgRep.pixelsHigh, prevC, prevC);
		free(mem);
	}
	if (useAlpha) draw_checker_background(colBarFrm);
	[imgRep drawInRect:colBarFrm fromRect:(NSRect){0., 0., imgRep.size}
		operation:NSCompositingOperationSourceOver fraction:1. respectFlipped:NO hints:nil];
}
- (void)colorChanged {
	changed = YES;
	self.needsDisplay = YES;
	[self sendAction:self.action to:self.target];
}
- (NSUndoManager *)undoManager {
	NSWindow *win = self.window;
	return [win.delegate windowWillReturnUndoManager:win];
}
- (void)changeColor:(void (^)(void))undoHandler {
	[self.undoManager registerUndoWithTarget:self handler:^(id _) { undoHandler(); }];
}
- (void)removeColorWell:(KeyColorWell *)cw {
	[self.undoManager registerUndoWithTarget:self handler:
		^(GradientBar *target) { [target addColorWell:cw]; }];
	if (cw.active) NSColorPanel.sharedColorPanel.target = nil;
	[cw removeFromSuperview];
	changed = YES;
	[self sendAction:self.action to:self.target];
}
- (void)addColorWell:(KeyColorWell *)cw {
	if (!initialization) [self.undoManager registerUndoWithTarget:self handler:
		^(GradientBar *target) { [target removeColorWell:cw]; }];
	[self addSubview:cw];
	changed = YES;
	if (!initialization) [self sendAction:self.action to:self.target];
}
- (void)hideColorPanelIfOpened {
	if (activeColorWell != nil) {
		NSColorPanel.sharedColorPanel.target = nil;
		[NSColorPanel.sharedColorPanel orderOut:nil];
	}
}
- (void)removeActiveColorWell:(id)sender {
	if (activeColorWell != nil) {
		[self removeColorWell:activeColorWell];
		[NSColorPanel.sharedColorPanel orderOut:nil];
	}
}
- (void)mouseDown:(NSEvent *)event {
	[self hideColorPanelIfOpened];
}
- (void)addNewColorWell:(id)sender {
	NSArray<KeyColorWell *> *colWels = [self colorWells];
	CGFloat x1 = 0., x2 = colBarFrm.size.width;
	simd_float4 c1 = {0.,0.,0.,0.}, c2 = c1;
	if (activeColorWell != nil) {
		x1 = activeColorWell.frame.origin.x;
		c1 = activeColorWell.hsba;
		NSInteger idx = [colWels indexOfObject:activeColorWell];
		if (idx < colWels.count - 1) {
			x2 = colWels[idx + 1].frame.origin.x;
			c2 = colWels[idx + 1].hsba;
		} else c2 = c1;
	} else if (colWels.count > 0) {
		x2 = colWels[0].frame.origin.x;
		c1 = c2 = colWels[0].hsba;
	}
	if (x1 == x2) return;
	[self addColorWellAt:(x1 + x2) / 2. / colBarFrm.size.width
		color:interpolated_hsb(c1, c2, .5)];
}
- (void)changeUseAlpha:(NSSlider *)sender {
	CGFloat newValue = sender.doubleValue;
	if (useAlpha == newValue) return;
	useAlpha = newValue;
	changed = YES;
	self.needsDisplay = YES;
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
	change:(NSDictionary<NSKeyValueChangeKey, id> *)change context:(void *)context {
	KeyColorWell *oldTgt = change[NSKeyValueChangeOldKey], *newTgt = change[NSKeyValueChangeNewKey];
	if ([oldTgt isKindOfClass:KeyColorWell.class]) {
		oldTgt.active = NO;
		oldTgt.needsDisplay = YES;
	}
	if ([newTgt isKindOfClass:KeyColorWell.class]) {
		newTgt.active = YES;
		newTgt.needsDisplay = YES;
		removeBtn.enabled = YES;
		activeColorWell = newTgt;
	} else {
		removeBtn.enabled = NO;
		activeColorWell = nil;
	}
	[self checkAddCWEnabled];
}
@end

@interface SpeedColPanel () {
	NSUndoManager *undoManager;
	ControlPanel *ctrlPnl;
	NSData *lastSpdCols;
}
@end
@implementation SpeedColPanel
- (NSString *)windowNibName { return @"SpeedColPanel"; }
- (void)windowDidLoad {
	add_observer(keySpeedColors, ^(NSNotification * _Nonnull note) {
		NSData *data = note.userInfo[keyOldValue];
		NSLog(@"%@ %ld", keySpeedColors, data.length);
		[NSNotificationCenter.defaultCenter postNotificationName:@"colorParticles" object:NSApp];
	});
}
- (void)setupControls {
	[gradientBar setupColors:speedColors count:nSpeedColors];
	rvtFDBtn.enabled = !spdcol_is_equal_to(spdColFD);
	rvtUDBtn.enabled = !spdcol_is_equal_to(spdColUD);
}
NSData *data_from_spdCols(void) {
	return [NSData dataWithBytes:speedColors length:sizeof(SpeedColor) * nSpeedColors];
}
void spdCols_from_data(NSData *data) {
	NSInteger nCols = data.length / sizeof(SpeedColor);
	if (nCols != nSpeedColors)
		speedColors = realloc(speedColors, sizeof(SpeedColor) * (nSpeedColors = nCols));
	memcpy(speedColors, data.bytes, sizeof(SpeedColor) * nCols);
}
+ (void)initParamDefaults {
	spdColFD = data_from_spdCols(); speedColors = NULL; nSpeedColors = 0;
	spdColUD = [NSUserDefaults.standardUserDefaults objectForKey:keySpeedColors];
	if (spdColUD == nil) {
		spdCols_from_data(spdColFD);
		spdColUD = spdColFD;
	} else spdCols_from_data(spdColUD);
}
+ (NSInteger)initParams:(NSInteger)fdBit fdBits:(UInt64 *)fdB {
	FDBTSpdCol = (int)fdBit;
	if (!spdcol_is_equal_to(spdColFD)) *fdB |= 1 << fdBit;
	return fdBit + 1;
}
- (void)checkModification {
	BOOL isFD = spdcol_is_equal_to(spdColFD), isUD = spdcol_is_equal_to(spdColUD);
	rvtFDBtn.enabled = !isFD;
	rvtUDBtn.enabled = !isUD;
	if (ctrlPnl == nil) ctrlPnl = (ControlPanel *)self.window.sheetParent.delegate;
	[ctrlPnl checkFDBits:FDBTSpdCol fd:isFD ud:isUD];
	[NSNotificationCenter.defaultCenter postNotificationName:@"colorParticles" object:NSApp];
}
- (IBAction)colorBarModified:(id)sender {
	NSData *data = [gradientBar dataOfValues];
	if (spdcol_is_equal_to(data)) return;
	spdCols_from_data(data);
	[self checkModification];
}
- (IBAction)sheetOk:(id)sender {
	[gradientBar hideColorPanelIfOpened];
	lastSpdCols = data_from_spdCols();
	[super sheetOk:sender];
}
- (void)setSpdColsFromData:(NSData *)data colWels:(NSArray<KeyColorWell *> *)colWels {
	NSData *orgData = data_from_spdCols();
	NSArray<KeyColorWell *> *orgKeyColWels = gradientBar.colorWells;
	[undoManager registerUndoWithTarget:self handler:^(id _Nonnull target) {
		[self setSpdColsFromData:orgData colWels:orgKeyColWels];
	}];
	spdCols_from_data(data);
	if (colWels == nil) [gradientBar setupColors:speedColors count:nSpeedColors];
	else [gradientBar resetupColorsWells:speedColors count:nSpeedColors colWels:colWels];
	[self checkModification];
}
- (IBAction)revertToUserDefaults:(id)sender {
	[self setSpdColsFromData:spdColUD colWels:nil];
}
- (IBAction)revertToFactoryDefaults:(id)sender {
	[self setSpdColsFromData:spdColFD colWels:nil];
}
//
- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window {
	if (undoManager == nil) undoManager = NSUndoManager.new;
	return undoManager;
}
@end
