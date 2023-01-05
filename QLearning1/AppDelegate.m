//
//  AppDelegate.m
//  QLearning1
//
//  Created by Tatsuo Unemi on 2022/12/24.
//
// Q-Learning by Look-up-table
// on simple maze.

#import "AppDelegate.h"
#import "Agent.h"
#import "Display.h"
#import "RecordView.h"
#import "MyViewForCG.h"

int Move[4][2] = {{0,1},{1,0},{0,-1},{-1,0}}; // up, right, down, left
int ObsP[NObstacles][2] = {{2,2},{2,3},{2,4},{5,1},{7,3},{7,4},{7,5}};
int FieldP[NGridW * NGridH - NObstacles][2];
int Obstacles[NGridH][NGridW];
int StartP[] = {0,3}, GoalP[] = {8,5};
NSString *keyOldValue = @"oldValue", *keyShouldRedraw = @"shouldRedraw";
NSString *keyColorMode = @"ptclColorMode", *keyDrawMethod = @"ptclDrawMethod";
static NSString *scrForFullScr = @"Screen the main window placed", *scrForFullScrFD;
static NSString *keyScrForFullScr = @"screenForFullScreenMode";
static PTCLColorMode ptclColorModeFD;
static PTCLDrawMethod ptclDrawMethodFD;
static NSString *labelFullScreenOn = @"Full Screen", *labelFullScreenOff = @"Full Screen Off";
static NSImage *imgFullScreenOn, *imgFullScreenOff;
enum {
	ShouldPostNotification = 1,
	ShouldRedrawScreen = 2
};
IntVarInfo IntVars[] = {
	{ @"memSize", &MemSize, 0, 0 },
	{ @"memTrials", &MemTrials, 0, 0 },
	{ @"nParticles", &NParticles, 0, ShouldPostNotification },
	{ @"ptclLifeSpan", &LifeSpan, 0, ShouldPostNotification },
	{ nil }
};
FloatVarInfo FloatVars[] = {
	{ @"T0", &T0, 0, 0 },
	{ @"T1", &T1, 0, 0 },
	{ @"cooling", &CoolingRate, 0, 0 },
	{ @"initQValue", &InitQValue, 0, 0 },
	{ @"gamma", &Gamma, 0, 0 },
	{ @"alpha", &Alpha, 0, 0 },
	{ @"ptclMass", &Mass, 0, 0 },
	{ @"ptclFriction", &Friction, 0, 0 },
	{ @"ptclLength", &StrokeLength, 0, ShouldRedrawScreen },
	{ @"ptclWeight", &StrokeWidth, 0, ShouldRedrawScreen },
	{ @"ptclMaxSpeed", &MaxSpeed, 0, 0 },
	{ nil }
};
ColVarInfo ColVars[] = {
	{ @"colorBackground", &colBackground, nil, 0 },
	{ @"colorObstacles", &colObstacles, nil, 0 },
	{ @"colorAgent", &colAgent, nil, 0 },
	{ @"colorGridLines", &colGridLines, nil, 0 },
	{ @"colorSymbols", &colSymbols, nil, ShouldPostNotification },
	{ @"colorParticles", &colParticles, nil, ShouldPostNotification },
	{ nil }
};
#define MAX_STEPS (UIntegerVars[0].v)
#define MAX_GOALCNT (UIntegerVars[1].v)
UIntegerVarInfo UIntegerVars[] = {
	{ @"maxSteps", 8000 },
	{ @"maxGoalCount", 60 },
	{ nil }
};
#define START_WIDTH_FULL_SCR (BoolVars[0].v)
#define RECORD_IMAGES (BoolVars[1].v)
BoolVarInfo BoolVars[] = {
	{ @"startWithFullScreenMode", NO },
	{ @"recordFinalImage", NO, NO, ShouldPostNotification },
	{ nil }
};

#define DEF_FOR_ALL_PROC(name,type,table) \
static void name(void (^block)(type *p)) {\
	for (NSInteger i = 0; table[i].key != nil; i ++) block(&table[i]);\
}
DEF_FOR_ALL_PROC(for_all_int_vars, IntVarInfo, IntVars)
DEF_FOR_ALL_PROC(for_all_float_vars, FloatVarInfo, FloatVars)
DEF_FOR_ALL_PROC(for_all_uint_vars, UIntegerVarInfo, UIntegerVars)
DEF_FOR_ALL_PROC(for_all_bool_vars, BoolVarInfo, BoolVars)
DEF_FOR_ALL_PROC(for_all_color_vars, ColVarInfo, ColVars)

//NSUInteger tm0 = current_time_us();
//NSUInteger tm1 = current_time_us();
//printf("%ld\n", tm1-tm0);
unsigned long current_time_us(void) {
	static long startTime = -1;
	struct timeval tv;
	gettimeofday(&tv, NULL);
	if (startTime < 0) startTime = tv.tv_sec;
	return (tv.tv_sec - startTime) * 1000000L + tv.tv_usec;
}
void in_main_thread(void (^block)(void)) {
	if (NSThread.isMainThread) block();
	else dispatch_async(dispatch_get_main_queue(), block);
}

@interface MyContentView : NSView
@end
@implementation MyContentView
// pressing ESC key to exit from full screen mode. 
- (void)keyDown:(NSEvent *)event {
	if (event.keyCode == 53 && self.inFullScreenMode)
		[self exitFullScreenModeWithOptions:nil];
	else [super keyDown:event];
}
- (void)drawRect:(NSRect)rect {
	[NSColor.blackColor setFill];
	[NSBezierPath fillRect:rect];
}
@end

@implementation MyViewController {
	Agent *agent;
	Display *display;
	CGFloat interval;
	BOOL running;
	NSUInteger steps, goalCount;
	IBOutlet NSToolbarItem *startStopItem, *fullScreenItem,
		*stepsItem, *goalCntItem;
	IBOutlet NSView *stepsView, *goalCntView;
	IBOutlet NSTextField *stepsDgt, *goalCntDgt;
	IBOutlet RecordView *recordView;
}
- (void)adjustForRecordView:(NSNotification *)note {
	NSRect vFrame = self.view.superview.frame, wFrame = self.view.window.frame;
	NSSize vSize = vFrame.size;
	CGFloat widthToBe = (RECORD_IMAGES? 16. / 9. : (CGFloat)NGridW / NGridH) * vSize.height;
	if (wFrame.size.width != widthToBe) {
		NSRect orgFrm = self.view.frame;
		wFrame.size.width += widthToBe - vSize.width;
		wFrame.origin.x -= (widthToBe - vSize.width) / 2.;
		[self.view.window setFrame:wFrame display:YES];
		[self.view setFrame:orgFrm];
	}
	recordView.hidden = !RECORD_IMAGES;
}
- (void)adjustViewFrame:(NSNotification *)note {
	NSView *cView = (NSView *)note.object;
	NSSize cSize = cView.frame.size;
	CGFloat cAspect = cSize.width / cSize.height,
		iAspect = RECORD_IMAGES? 16. / 9. : (CGFloat)NGridW / NGridH;
	NSRect vFrame = (cAspect == iAspect)? (NSRect){0., 0., cSize} :
		(cAspect > iAspect)?
			(NSRect){(cSize.width - cSize.height * iAspect) / 2., 0.,
				cSize.height * iAspect, cSize.height} :
			(NSRect){0., (cSize.height - cSize.width / iAspect) / 2.,
				cSize.width, cSize.width / iAspect};
	if (RECORD_IMAGES) {
		NSRect rFrame = vFrame;
		vFrame.size.width = vFrame.size.height * NGridW / NGridH;
		rFrame.size.width -= vFrame.size.width;
		rFrame.origin.x += vFrame.size.width;
		[recordView setFrame:rFrame];
	}
	[self.view setFrame:vFrame];
}
- (void)viewDidLoad {
	[super viewDidLoad];
	memset(Obstacles, 0, sizeof(Obstacles));
	for (int i = 0; i < NObstacles; i ++)
		Obstacles[ObsP[i][1]][ObsP[i][0]] = 1;
	int k1 = 0, k2 = 0;
	for (int j = 0; j < NGridW; j ++)
	for (int i = 0; i < NGridH; i ++) {
		if (k1 < NObstacles && ObsP[k1][0] == j && ObsP[k1][1] == i) k1 ++;
		else { FieldP[k2][0] = j; FieldP[k2][1] = i; k2 ++; }
	}
	interval = 1. / 60.;
	agent = Agent.new;
	display = [Display.alloc initWithView:(MTKView *)self.view agent:agent];
	imgFullScreenOn = [NSImage imageNamed:@"NSEnterFullScreenTemplate"];
	imgFullScreenOff = [NSImage imageNamed:@"NSExitFullScreenTemplate"];
	stepsItem.view = stepsView;
	goalCntItem.view = goalCntView;
//	fullScreenItem.possibleLabels = @[labelFullScreenOn, labelFullScreenOn];
	[NSNotificationCenter.defaultCenter addObserver:self
		selector:@selector(adjustForRecordView:) name:@"recordFinalImage" object:nil];
	[NSNotificationCenter.defaultCenter addObserver:self
		selector:@selector(adjustViewFrame:)
		name:NSViewFrameDidChangeNotification object:self.view.superview];
}
- (void)showSteps { stepsDgt.integerValue = steps; }
- (void)showGoalCount { goalCntDgt.integerValue = goalCount; }
- (void)loopThread {
	while (running) {
		NSDate *time0 = NSDate.date;
		if ([agent oneStep]) {
			goalCount ++;
			in_main_thread(^{ [self showGoalCount]; });
		}
		steps ++;
		in_main_thread(^{ [self showSteps]; });
		[display oneStep];
		NSTimeInterval timeRemain = interval + time0.timeIntervalSinceNow
			- (1./52. - 1./60.);
		if (timeRemain > 0.) usleep(timeRemain * 1e6);
		if ((MAX_STEPS > 0 && steps >= MAX_STEPS)
		 || (MAX_GOALCNT > 0 && goalCount >= MAX_GOALCNT))
			in_main_thread(^{ [self reset:nil]; });
	}
}
- (IBAction)reset:(id)sender {
	if (RECORD_IMAGES && goalCount > 0)
		[recordView addImage:display];
	[agent reset];
	[agent restart];
	[display reset];
	steps = goalCount = 0;
	in_main_thread(^{
		[self showSteps];
		[self showGoalCount];
	});
}
- (IBAction)startStop:(id)sender {
	if ((running = !running)) {
		[NSThread detachNewThreadSelector:@selector(loopThread)
			toTarget:self withObject:nil];
		startStopItem.image = [NSImage imageNamed:NSImageNameTouchBarPauseTemplate];
		startStopItem.label = @"Stop";
	} else {
		startStopItem.image = [NSImage imageNamed:NSImageNameTouchBarPlayTemplate];
		startStopItem.label = @"Start";
	}
}
- (IBAction)fullScreen:(id)sender {
	NSView *view = self.view.superview;
	if (!view.inFullScreenMode) {
		NSScreen *screen = self.view.window.screen;
		if (scrForFullScr != nil) for (NSScreen *scr in NSScreen.screens)
			if ([scrForFullScr isEqualToString:scr.localizedName])
				{ screen = scr; break; }
		[view enterFullScreenMode:screen
			withOptions:@{NSFullScreenModeAllScreens:@NO}];
		fullScreenItem.label = labelFullScreenOff;
		fullScreenItem.image = imgFullScreenOff;
	} else {
		[view exitFullScreenModeWithOptions:nil];
		fullScreenItem.label = labelFullScreenOn;
		fullScreenItem.image = imgFullScreenOn;
	}
}
- (IBAction)print:(id)sender {
	NSPrintInfo *prInfo = NSPrintInfo.sharedPrintInfo;
	NSRect pb = prInfo.imageablePageBounds;
	NSSize pSize = prInfo.paperSize;
	prInfo.topMargin = pSize.height - NSMaxY(pb);
	prInfo.bottomMargin = pb.origin.y;
	prInfo.leftMargin = pb.origin.x;
	prInfo.rightMargin = pSize.width - NSMaxX(pb);
	MyViewForCG *view = [MyViewForCG.alloc initWithFrame:pb display:display];
	NSPrintOperation *prOpe = [NSPrintOperation printOperationWithView:view printInfo:prInfo];
	[prOpe runOperation];
}
- (IBAction)copy:(id)sender {
	NSRect frame = {0., 0., NGridW * TileSize, NGridH * TileSize};
	MyViewForCG *view = [MyViewForCG.alloc initWithFrame:frame display:display];
	NSData *data = [view dataWithPDFInsideRect:frame];
	NSPasteboard *pb = NSPasteboard.generalPasteboard;
	[pb declareTypes:@[NSPasteboardTypePDF] owner:NSApp];
	[pb setData:data forType:NSPasteboardTypePDF];
}
// Window Delegate
- (void)windowWillClose:(NSNotification *)notification {
	if (notification.object == self.view.window)
		[NSApp terminate:nil];
}
// Menu item validation
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	SEL action = menuItem.action;
	if (action == @selector(startStop:))
		menuItem.title = running? @"Stop" : @"Start";
	else if (action == @selector(fullScreen:))
		menuItem.title = self.view.superview.inFullScreenMode?
			labelFullScreenOff : labelFullScreenOn;
	return YES;
}
@end

static NSUInteger col_to_ulong(NSColor *col) {
	CGFloat c[4] = {0., 0., 0., 1.};
	[[col colorUsingColorSpace:NSColorSpace.genericRGBColorSpace]
		getComponents:c];
	return (((NSUInteger)(c[0] * 255)) << 24) |
		(((NSUInteger)(c[1] * 255)) << 16) |
		(((NSUInteger)(c[2] * 255)) << 8) |
		(NSUInteger)(c[3] * 255);
}
static void setup_screen_menu(NSPopUpButton *popup) {
	[popup removeAllItems];
	NSArray<NSScreen *> *screens = NSScreen.screens;
	if (screens.count > 1) {
		[popup addItemWithTitle:scrForFullScrFD];
		for (NSScreen *scr in screens)
			[popup addItemWithTitle:scr.localizedName];
		in_main_thread(^{
			NSMenuItem *item = [popup itemWithTitle:scrForFullScr];
			if (item != nil) [popup selectItem:item];
			else [popup selectItemAtIndex:0];
		});
	} else if (screens.count == 1) {
		[popup addItemWithTitle:screens[0].localizedName];
		in_main_thread(^{ [popup selectItemAtIndex:0]; });
	}
	popup.enabled = (screens.count > 1);
}
static void displayReconfigCB(CGDirectDisplayID display,
	CGDisplayChangeSummaryFlags flags, void *userInfo) {
	if ((flags & kCGDisplayBeginConfigurationFlag) != 0 ||
		(flags & (kCGDisplayAddFlag | kCGDisplayRemoveFlag |
		kCGDisplayEnabledFlag | kCGDisplayDisabledFlag)) == 0) return;
	setup_screen_menu((__bridge NSPopUpButton *)userInfo);
}
@implementation ControlPanel {
	IBOutlet NSColorWell *cwlBackground, *cwObstacles, *cwAgent,
		*cwGridLines, *cwSymbols, *cwParticles;
	IBOutlet NSTextField *dgtMemSize, *dgtMemTrials, *dgtNParticles, *dgtLifeSpan;
	IBOutlet NSTextField *dgtT0, *dgtT1, *dgtCoolingRate, *dgtInitQValue, *dgtGamma, *dgtAlpha,
		*dgtMass, *dgtFriction, *dgtStrokeLength, *dgtStrokeWidth, *dgtMaxSpeed;
	IBOutlet NSButton *btnDrawByRects, *btnDrawByTriangles, *btnDrawByLines,
		*btnColConst, *btnColAngle, *btnColSpeed,
		*cboxStartFullScr, *cboxRecordImages, *btnRevertToFD;
	IBOutlet NSPopUpButton *screenPopUp;
	IBOutlet NSTextField *dgtMaxSteps, *dgtMaxGoalCnt;
	NSArray<NSColorWell *> *colWels;
	NSArray<NSTextField *> *ivDgts, *fvDgts, *uvDgts;
	NSArray<NSButton *> *colBtns, *dmBtns, *boolVBtns;
	int FDBTCol, FDBTInt, FDBTFloat, FDBTUInt, FDBTBool, FDBTDc,
		FDBTDm, FDBTFulScr;
	UInt64 FDBits;
}
- (NSString *)windowNibName { return @"ControlPanel"; }
- (void)adjustControls {
	for (NSColorWell *cwl in colWels) cwl.color = *ColVars[cwl.tag].v;
	for (NSTextField *dgt in ivDgts) dgt.intValue = *IntVars[dgt.tag].v;
	for (NSTextField *dgt in fvDgts) dgt.floatValue = *FloatVars[dgt.tag].v;
	for (NSTextField *dgt in uvDgts) dgt.integerValue = UIntegerVars[dgt.tag].v;
	for (NSButton *btn in boolVBtns) btn.state = BoolVars[btn.tag].v;
	for (NSButton *btn in colBtns) btn.state = (ptclColorMode == btn.tag);
	for (NSButton *btn in dmBtns) btn.state = (ptclDrawMethod == btn.tag);
	dgtStrokeWidth.enabled = (ptclDrawMethod != PTCLbyLines);
	[screenPopUp selectItemWithTitle:scrForFullScr];
	btnRevertToFD.enabled = (FDBits != 0);
}
- (void)windowDidLoad {
	[super windowDidLoad];
	if (self.window == nil) return;
	_undoManager = NSUndoManager.new;
	setup_screen_menu(screenPopUp);
	CGError error = CGDisplayRegisterReconfigurationCallback
		(displayReconfigCB, (__bridge void *)screenPopUp);
	if (error != kCGErrorSuccess)
		NSLog(@"CGDisplayRegisterReconfigurationCallback error = %d", error);
	colWels = @[cwlBackground, cwObstacles, cwAgent, cwGridLines, cwSymbols, cwParticles];
	ivDgts = @[dgtMemSize, dgtMemTrials, dgtNParticles, dgtLifeSpan];
	fvDgts = @[dgtT0, dgtT1, dgtCoolingRate, dgtInitQValue, dgtGamma, dgtAlpha,
		dgtMass, dgtFriction, dgtStrokeLength, dgtStrokeWidth, dgtMaxSpeed];
	uvDgts = @[dgtMaxSteps, dgtMaxGoalCnt];
	boolVBtns = @[cboxStartFullScr, cboxRecordImages];
	colBtns = @[btnColConst, btnColAngle, btnColSpeed];
	dmBtns = @[btnDrawByRects, btnDrawByTriangles, btnDrawByLines];
	NSInteger bit = 0, tag = 0;
	FDBTCol = (int)bit;
	for (NSColorWell *cwl in colWels) {
		if (col_to_ulong(*ColVars[tag].v) != col_to_ulong(ColVars[tag].fd))
			FDBits |= 1 << bit;
		cwl.target = self;
		cwl.action = @selector(chooseColorWell:);
		cwl.tag = tag ++; bit ++;
	}
	tag = 0;
	FDBTInt = (int)bit;
	for (NSTextField *dgt in ivDgts) {
		if (*IntVars[tag].v != IntVars[tag].fd) FDBits |= 1 << bit;
		dgt.target = self;
		dgt.action = @selector(changeIntValue:);
		dgt.tag = tag ++; bit ++;
	}
	tag = 0;
	FDBTFloat = (int)bit;
	for (NSTextField *dgt in fvDgts) {
		if (*FloatVars[tag].v != FloatVars[tag].fd) FDBits |= 1 << bit;
		dgt.target = self;
		dgt.action = @selector(changeFloatValue:);
		dgt.tag = tag ++; bit ++;
	}
	tag = 0;
	FDBTUInt = (int)bit;
	for (NSTextField *dgt in uvDgts) {
		if (UIntegerVars[tag].v != UIntegerVars[tag].fd) FDBits |= 1 << bit;
		dgt.target = self;
		dgt.action = @selector(changeUIntegerValue:);
		dgt.tag = tag ++; bit ++;
	}
	tag = 0;
	FDBTBool = (int)bit;
	for (NSButton *btn in boolVBtns) {
		if (BoolVars[tag].v != BoolVars[tag].fd) FDBits |= 1 << bit;
		btn.target = self;
		btn.action = @selector(switchBoolValue:);
		btn.tag = tag ++; bit ++;
	}
	tag = 0;
	FDBTDc = (int)bit;
	if (ptclColorMode != ptclColorModeFD) FDBits |= 1 << bit;
	for (NSButton *btn in colBtns) {
		btn.target = self;
		btn.action = @selector(chooseColorMode:);
		btn.tag = tag ++; bit ++;
	}
	tag = 0;
	FDBTDm = (int)bit;
	if (ptclDrawMethod != ptclDrawMethodFD) FDBits |= 1 << bit;
	for (NSButton *btn in dmBtns) {
		btn.target = self;
		btn.action = @selector(chooseDrawMethod:);
		btn.tag = tag ++; bit ++;
	}
	FDBTFulScr = (int)bit;
	if (scrForFullScr != scrForFullScrFD) FDBits |= 1 << bit;
	[self adjustControls];
}
- (void)checkFDBits:(NSInteger)bitPosition cond:(BOOL)cond {
	UInt64 mask = 1ULL << bitPosition;
	if (cond) FDBits &= ~ mask;
	else FDBits |= mask;
	btnRevertToFD.enabled = (FDBits != 0);
}
- (IBAction)chooseColorWell:(NSColorWell *)colWl {
	ColVarInfo *info = &ColVars[colWl.tag];
	NSColor * __strong *var = info->v, *newValue = colWl.color;
	NSUInteger newValUlong = col_to_ulong(newValue);
	if (col_to_ulong(*var) == newValUlong) return;
	NSColor *orgValue = *var;
	[_undoManager registerUndoWithTarget:self handler:^(id _Nonnull target) {
		colWl.color = orgValue;
		[colWl sendAction:colWl.action to:target];
	}];
	*var = newValue;
	[self checkFDBits:FDBTCol + (int)colWl.tag
		cond:newValUlong == col_to_ulong(info->fd)];
	[NSNotificationCenter.defaultCenter postNotificationName:
		(info->flag & ShouldPostNotification)? info->key : keyShouldRedraw object:NSApp];
}
- (IBAction)changeIntValue:(NSTextField *)dgt {
	IntVarInfo *info = &IntVars[dgt.tag];
	int *var = info->v, newValue = dgt.intValue;
	if (*var == newValue) return;
	int orgValue = *var;
	[_undoManager registerUndoWithTarget:self handler:^(id _Nonnull target) {
		dgt.intValue = orgValue;
		[dgt sendAction:dgt.action to:target];
	}];
	*var = newValue;
	[self checkFDBits:FDBTInt + dgt.tag cond:newValue == info->fd];
	if (info->flag & ShouldPostNotification)
		[NSNotificationCenter.defaultCenter postNotificationName:
			info->key object:NSApp userInfo:@{keyOldValue:@(orgValue)}];
}
- (IBAction)changeFloatValue:(NSTextField *)dgt {
	FloatVarInfo *info = &FloatVars[dgt.tag];
	float *var = info->v, newValue = dgt.floatValue;
	if (*var == newValue) return;
	float orgValue = *var;
	[_undoManager registerUndoWithTarget:self handler:^(id _Nonnull target) {
		dgt.floatValue = orgValue;
		[dgt sendAction:dgt.action to:target];
	}];
	*var = newValue;
	[self checkFDBits:FDBTFloat + dgt.tag cond:newValue == info->fd];
	if (info->flag & ShouldRedrawScreen) [NSNotificationCenter.defaultCenter
		postNotificationName:keyShouldRedraw object:NSApp];
}
- (IBAction)changeUIntegerValue:(NSTextField *)dgt {
	UIntegerVarInfo *info = &UIntegerVars[dgt.tag];
	NSUInteger newValue = dgt.integerValue, orgValue = info->v;
	if (orgValue == newValue) return;
	[_undoManager registerUndoWithTarget:self handler:^(id _Nonnull target) {
		dgt.integerValue = orgValue;
		[dgt sendAction:dgt.action to:target];
	}];
	info->v = newValue;
	[self checkFDBits:FDBTUInt + dgt.tag cond:newValue == info->fd];
}
- (IBAction)switchBoolValue:(NSButton *)btn {
	BoolVarInfo *info = &BoolVars[btn.tag];
	BOOL newValue = btn.state, orgValue = info->v;
	if (newValue == orgValue) return;
	[_undoManager registerUndoWithTarget:self handler:^(id _Nonnull target) {
		btn.state = orgValue;
		[btn sendAction:btn.action to:target];
	}];
	info->v = newValue;
	[self checkFDBits:FDBTBool + btn.tag cond:newValue == info->fd];
	if (info->flag & ShouldPostNotification)
		[NSNotificationCenter.defaultCenter postNotificationName:
			info->key object:NSApp userInfo:nil];
}
- (IBAction)chooseColorMode:(NSButton *)btn {
	PTCLColorMode newValue = (PTCLColorMode)btn.tag;
	if (ptclColorMode == newValue) return;
	NSButton *orgBtn = colBtns[ptclColorMode];
	[_undoManager registerUndoWithTarget:self handler:^(id _Nonnull target) {
		[orgBtn performClick:nil];
	}];
	ptclColorMode = newValue;
	[self checkFDBits:FDBTDc cond:newValue == ptclColorModeFD];
	[NSNotificationCenter.defaultCenter
		postNotificationName:keyColorMode object:NSApp];
}
- (IBAction)chooseDrawMethod:(NSButton *)btn {
	PTCLDrawMethod newValue = (PTCLDrawMethod)btn.tag;
	if (ptclDrawMethod == newValue) return;
	NSButton *orgBtn = dmBtns[ptclDrawMethod];
	[_undoManager registerUndoWithTarget:self handler:^(id _Nonnull target) {
		[orgBtn performClick:nil];
	}];
	ptclDrawMethod = newValue;
	dgtStrokeWidth.enabled = (newValue != PTCLbyLines);
	[self checkFDBits:FDBTDm cond:newValue == ptclDrawMethodFD];
	[NSNotificationCenter.defaultCenter
		postNotificationName:keyDrawMethod object:NSApp];
}
- (IBAction)chooseScreenForFullScreen:(NSPopUpButton *)popUp {
	NSString *newValue = popUp.titleOfSelectedItem;
	if ([scrForFullScr isEqualToString:newValue]) return;
	NSString *orgValue = scrForFullScr;
	[_undoManager registerUndoWithTarget:self handler:^(id _Nonnull target) {
		if ([popUp itemWithTitle:orgValue] != nil)
			[popUp selectItemWithTitle:orgValue];
		else [popUp selectItemAtIndex:0];
		[popUp sendAction:popUp.action to:target];
	}];
	scrForFullScr = newValue;
	[self checkFDBits:FDBTFulScr cond:newValue == scrForFullScrFD];
}
- (IBAction)revertToFactoryDefault:(id)sender {
	NSMutableDictionary *md = NSMutableDictionary.new;
	for_all_int_vars(^(IntVarInfo *p) {
		if (*p->v != p->fd) md[p->key] = @(p->fd);
	});
	for_all_float_vars(^(FloatVarInfo *p) {
		if (*p->v != p->fd) md[p->key] = @(p->fd);
	});
	for_all_uint_vars(^(UIntegerVarInfo *p) {
		if (p->v != p->fd) md[p->key] = @(p->fd);
	});
	for_all_bool_vars(^(BoolVarInfo *p) {
		if (p->v != p->fd) md[p->key] = @(p->fd);
	});
	for_all_color_vars(^(ColVarInfo *p) {
		if (col_to_ulong(*p->v) != col_to_ulong(p->fd)) md[p->key] = p->fd;
	});
	if (ptclColorMode != ptclColorModeFD) md[keyColorMode] = @(ptclColorModeFD);
	if (ptclDrawMethod != ptclDrawMethodFD) md[keyDrawMethod] = @(ptclDrawMethodFD);
	if (![scrForFullScr isEqualToString:scrForFullScrFD])
		md[keyScrForFullScr] = scrForFullScrFD;
	[self setParamValuesFromDict:md];
}
- (void)setParamValuesFromDict:(NSDictionary *)dict {
	NSMutableArray<NSString *> *postKeys = NSMutableArray.new;
	NSMutableDictionary *orgValues = NSMutableDictionary.new;
	BOOL shouldRedraw = NO, *srP = &shouldRedraw;
	UInt64 fdFlipBits = 0, *fbP = &fdFlipBits;
	for_all_int_vars(^(IntVarInfo *p) {
		NSNumber *num = dict[p->key]; if (num == nil) return;
		int newValue = num.intValue; if (*p->v == newValue) return;
		if (p->flag & ShouldPostNotification) [postKeys addObject:p->key];
		orgValues[p->key] = @(*p->v);
		if (newValue == p->fd || *p->v == p->fd)
			*fbP |= 1 << (self->FDBTInt + (p - IntVars));
		*p->v = newValue;
	});
	for_all_float_vars(^(FloatVarInfo *p) {
		NSNumber *num = dict[p->key]; if (num == nil) return;
		float newValue = num.floatValue; if (*p->v == newValue) return;
		if (p->flag & ShouldRedrawScreen) *srP = YES;
		orgValues[p->key] = @(*p->v);
		if (newValue == p->fd || *p->v == p->fd)
			*fbP |= 1 << (self->FDBTFloat + (p - FloatVars));
		*p->v = newValue;
	});
	for_all_uint_vars(^(UIntegerVarInfo *p) {
		NSNumber *num = dict[p->key]; if (num == nil) return;
		NSUInteger newValue = num.integerValue; if (p->v == newValue) return;
		orgValues[p->key] = @(p->v);
		if (newValue == p->fd || p->v == p->fd)
			*fbP |= 1 << (self->FDBTUInt + (p - UIntegerVars));
		p->v = newValue;
	});
	for_all_bool_vars(^(BoolVarInfo *p) {
		NSNumber *num = dict[p->key]; if (num == nil) return;
		BOOL newValue = num.boolValue; if (p->v == newValue) return;
		orgValues[p->key] = @(p->v);
		if (newValue == p->fd || p->v == p->fd)
			*fbP |= 1 << (self->FDBTBool + (p - BoolVars));
		p->v = newValue;
	});
	for_all_color_vars(^(ColVarInfo *p) {
		NSColor *newCol = dict[p->key]; if (newCol == nil) return;
		if (col_to_ulong(*p->v) == col_to_ulong(newCol)) return;
		if (p->flag & ShouldPostNotification) [postKeys addObject:p->key];
		else *srP = YES;
		orgValues[p->key] = *p->v;
		NSInteger fdCol = col_to_ulong(p->fd);
		if (col_to_ulong(newCol) == fdCol || col_to_ulong(*p->v) == fdCol)
			*fbP |= 1 << (self->FDBTCol + (p - ColVars));
		*p->v = newCol; });
	NSNumber *num = dict[keyColorMode];
	if (num != nil) {
		PTCLColorMode newValue = num.intValue;
		if (ptclColorMode != newValue) {
			orgValues[keyColorMode] = @(ptclColorMode);
			if (ptclColorMode == ptclColorModeFD || newValue == ptclColorModeFD)
				*fbP |= 1 << self->FDBTDc;
			ptclColorMode = newValue;
			[postKeys addObject:keyColorMode];
		}
	}
	num = dict[keyDrawMethod];
	if (num != nil) {
		PTCLDrawMethod newValue = num.intValue;
		if (ptclDrawMethod != newValue) {
			orgValues[keyDrawMethod] = @(ptclDrawMethod);
			if (ptclDrawMethod == ptclDrawMethodFD || newValue == ptclDrawMethodFD)
				*fbP |= 1 << self->FDBTDm;
			ptclDrawMethod = newValue;
			[postKeys addObject:keyDrawMethod];
		}
	}
	NSString *newValue = dict[keyScrForFullScr];
	if (newValue != nil) {
		if (![scrForFullScr isEqualToString:newValue]) {
			orgValues[keyScrForFullScr] = scrForFullScr;
			if (scrForFullScr == scrForFullScrFD || newValue == scrForFullScrFD)
				*fbP |= 1 << self->FDBTFulScr;
			scrForFullScr = newValue;
		}
	}
	FDBits ^= fdFlipBits;
	[self adjustControls];
	[_undoManager registerUndoWithTarget:self handler:^(id _Nonnull target) {
		[self setParamValuesFromDict:orgValues];
	}];
	for (NSString *key in postKeys) [NSNotificationCenter.defaultCenter
		postNotificationName:key object:NSApp];
	if (shouldRedraw) [NSNotificationCenter.defaultCenter
		postNotificationName:keyShouldRedraw object:NSApp];
}
- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window {
	return _undoManager;
}
@end

@implementation AppDelegate {
	IBOutlet MyViewController *viewController;
	ControlPanel *controlPanel;
}
- (IBAction)openControlPanel:(id)sender {
	if (controlPanel == nil)
		controlPanel = [ControlPanel.alloc initWithWindow:nil];
	[controlPanel showWindow:sender];
}
- (void)applicationWillFinishLaunching:(NSNotification *)aNotification {
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	for_all_int_vars(^(IntVarInfo *p) {
		p->fd = *p->v;
		NSNumber *nm = [ud objectForKey:p->key];
		if (nm != nil) *p->v = nm.intValue; });
	for_all_float_vars(^(FloatVarInfo *p) {
		p->fd = *p->v;
		NSNumber *nm = [ud objectForKey:p->key];
		if (nm != nil) *p->v = nm.floatValue; });
	for_all_uint_vars(^(UIntegerVarInfo *p) {
		p->fd = p->v;
		NSNumber *nm = [ud objectForKey:p->key];
		if (nm != nil) p->v = nm.integerValue; });
	for_all_bool_vars(^(BoolVarInfo *p) {
		p->fd = p->v;
		NSNumber *nm = [ud objectForKey:p->key];
		if (nm != nil) p->v = nm.boolValue; });
	for_all_color_vars(^(ColVarInfo *p) {
		p->fd = *p->v;
		NSString *str = [ud stringForKey:p->key];
		if (str == nil) return;
		NSUInteger rgba;
		sscanf(str.UTF8String, "%lX", &rgba);
		CGFloat c[4] = {
			(rgba >> 24) / 255.,
			((rgba >> 16) & 255) / 255.,
			((rgba >> 8) & 255) / 255.,
			(rgba & 255) / 255.
		};
		*p->v = [NSColor colorWithColorSpace:
			NSColorSpace.genericRGBColorSpace components:c count:4];
	});
	ptclColorModeFD = ptclColorMode;
	ptclDrawMethodFD = ptclDrawMethod;
	scrForFullScrFD = scrForFullScr;
	NSNumber *nm = [ud objectForKey:keyColorMode];
	if (nm != nil) ptclColorMode = nm.intValue;
	nm = [ud objectForKey:keyDrawMethod];
	if (nm != nil) ptclDrawMethod = nm.intValue;
	NSString *str = [ud objectForKey:keyScrForFullScr];
	if (str != nil) scrForFullScr = str;
	NSColorPanel.sharedColorPanel.showsAlpha = YES;
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
	[viewController reset:nil];
	if (START_WIDTH_FULL_SCR) [viewController fullScreen:nil];
	else [viewController adjustForRecordView:nil];
}
- (void)applicationWillTerminate:(NSNotification *)notification {
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	for_all_int_vars(^(IntVarInfo *p) {
		if (*p->v == p->fd) [ud removeObjectForKey:p->key];
		else [ud setInteger:*p->v forKey:p->key]; });
	for_all_float_vars(^(FloatVarInfo *p) {
		if (*p->v == p->fd) [ud removeObjectForKey:p->key];
		else [ud setFloat:*p->v forKey:p->key]; });
	for_all_uint_vars(^(UIntegerVarInfo *p) {
		if (p->v == p->fd) [ud removeObjectForKey:p->key];
		else [ud setInteger:p->v forKey:p->key]; });
	for_all_bool_vars(^(BoolVarInfo *p) {
		if (p->v == p->fd) [ud removeObjectForKey:p->key];
		else [ud setBool:p->v forKey:p->key]; });
	for_all_color_vars(^(ColVarInfo *p) {
		NSUInteger rgba = col_to_ulong(*p->v);
		if (rgba != col_to_ulong(p->fd)) {
			char buf[16];
			sprintf(buf, "%08lX", rgba);
			[ud setObject:[NSString stringWithUTF8String:buf] forKey:p->key];
		} else [ud removeObjectForKey:p->key];
	});
	if (ptclColorMode == ptclColorModeFD) [ud removeObjectForKey:keyColorMode];
	else [ud setInteger:ptclColorMode forKey:keyColorMode];
	if (ptclDrawMethod == ptclDrawMethodFD) [ud removeObjectForKey:keyDrawMethod];
	else [ud setInteger:ptclDrawMethod forKey:keyDrawMethod];
	if (scrForFullScr == scrForFullScrFD) [ud removeObjectForKey:keyScrForFullScr];
	else [ud setObject:scrForFullScr forKey:keyScrForFullScr];
}
@end
