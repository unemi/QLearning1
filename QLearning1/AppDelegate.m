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
NSString *keyOldValue = @"oldValue", *keyShouldRedraw = @"shouldRedraw",
	*keyChangeDrawMethod = @"changeDrawMethod";
int Move[4][2] = {{0,1},{1,0},{0,-1},{-1,0}}; // up, right, down, left
int ObsP[NObstacles][2] = {{2,2},{2,3},{2,4},{5,1},{7,3},{7,4},{7,5}};
int FieldP[NGridW * NGridH - NObstacles][2];
int Obstacles[NGridH][NGridW];
int StartP[] = {0,3}, GoalP[] = {8,5};
enum {
	ShouldPostNotification = 1,
	ShouldRedrawScreen = 2
};
static PTCLDrawMethod ptclDrawMethodFD;
static NSString *keyDrawMethod = @"ptclDrawMethod";
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
	{ @"colorParticles", &colParticles, nil, 0 },
	{ nil }
};
static void for_all_int_vars(void (^block)(IntVarInfo *p)) {
	for (NSInteger i = 0; IntVars[i].key != nil; i ++) block(&IntVars[i]);
}
static void for_all_float_vars(void (^block)(FloatVarInfo *p)) {
	for (NSInteger i = 0; FloatVars[i].key != nil; i ++) block(&FloatVars[i]);
}
static void for_all_color_vars(void (^block)(ColVarInfo *p)) {
	for (NSInteger i = 0; ColVars[i].key != nil; i ++) block(&ColVars[i]);
}

@implementation MyViewController {
	Agent *agent;
	Display *display;
	CGFloat interval;
	BOOL running;
	IBOutlet NSMenuItem *startStopMenuItem, *resetMenuItem;
	IBOutlet NSToolbarItem *startStopItem, *resetItem;
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
}
- (void)loopThread {
	while (running) {
		NSDate *time0 = NSDate.date;
		[agent oneStep];
		[display oneStep];
		NSTimeInterval timeRemain = interval + time0.timeIntervalSinceNow
			- (1./52. - 1./60.);
		if (timeRemain > 0.) usleep(timeRemain * 1e6);
	}
}
- (IBAction)reset:(id)sender {
	[agent reset];
	[agent restart];
	[display reset];
}
- (IBAction)startStop:(id)sender {
	if ((running = !running)) {
		[NSThread detachNewThreadSelector:@selector(loopThread)
			toTarget:self withObject:nil];
		startStopItem.image = [NSImage imageNamed:NSImageNameTouchBarPauseTemplate];
		startStopItem.label = startStopMenuItem.title = @"Stop";
		resetItem.enabled = NO;
	} else {
		startStopItem.image = [NSImage imageNamed:NSImageNameTouchBarPlayTemplate];
		startStopItem.label = startStopMenuItem.title = @"Start";
		resetItem.enabled = YES;
	}
}
- (void)windowWillClose:(NSNotification *)notification {
	if (notification.object == self.view.window)
		[NSApp terminate:nil];
}
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	if (menuItem == resetMenuItem) return !running;
	return YES;
}
- (BOOL)validateToolbarItem:(NSToolbarItem *)item {
	if (item == resetItem) return !running;
	else return YES;
}
@end

@implementation ControlPanel {
	IBOutlet NSColorWell *cwlBackground, *cwObstacles, *cwAgent,
		*cwGridLines, *cwSymbols, *cwParticles;
	IBOutlet NSTextField *dgtMemSize, *dgtMemTrials, *dgtNParticles, *dgtLifeSpan;
	IBOutlet NSTextField *dgtT0, *dgtT1, *dgtCoolingRate, *dgtInitQValue, *dgtGamma, *dgtAlpha,
		*dgtMass, *dgtFriction, *dgtStrokeLength, *dgtStrokeWidth, *dgtMaxSpeed;
	IBOutlet NSButton *btnDrawByRects, *btnDrawByTriangles, *btnDrawByLines, *btnRevertToFD;
	NSArray<NSColorWell *> *colWels;
	NSArray<NSTextField *> *ivDgts, *fvDgts;
	NSArray<NSButton *> *dmBtns;
	int FDBTCol, FDBTInt, FDBTFloat, FDBTDm; 
	UInt64 FDBits;
}
- (NSString *)windowNibName { return @"ControlPanel"; }
- (void)adjustControls {
	for (NSColorWell *cwl in colWels) cwl.color = *ColVars[cwl.tag].v;
	for (NSTextField *dgt in ivDgts) dgt.intValue = *IntVars[dgt.tag].v;
	for (NSTextField *dgt in fvDgts) dgt.floatValue = *FloatVars[dgt.tag].v;
	for (NSButton *btn in dmBtns) btn.state = (ptclDrawMethod == btn.tag);
	btnRevertToFD.enabled = (FDBits != 0);
}
- (void)windowDidLoad {
	[super windowDidLoad];
	if (self.window == nil) return;
	_undoManager = NSUndoManager.new;
	colWels = @[cwlBackground, cwObstacles, cwAgent, cwGridLines, cwSymbols, cwParticles];
	ivDgts = @[dgtMemSize, dgtMemTrials, dgtNParticles, dgtLifeSpan];
	fvDgts = @[dgtT0, dgtT1, dgtCoolingRate, dgtInitQValue, dgtGamma, dgtAlpha,
		dgtMass, dgtFriction, dgtStrokeLength, dgtStrokeWidth, dgtMaxSpeed];
	dmBtns = @[btnDrawByRects, btnDrawByTriangles, btnDrawByLines];
	NSInteger bit = 0, tag = 0;
	FDBTCol = (int)bit;
	for (NSColorWell *cwl in colWels) {
		if (!simd_equal(col_to_vec(*ColVars[tag].v), col_to_vec(ColVars[tag].fd)))
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
	FDBTDm = (int)bit;
	if (ptclDrawMethod != ptclDrawMethodFD) FDBits |= 1 << bit;
	for (NSButton *btn in dmBtns) {
		btn.target = self;
		btn.action = @selector(chooseDrawMethod:);
		btn.tag = tag ++;
	}
	[self adjustControls];
}
- (IBAction)chooseColorWell:(NSColorWell *)colWl {
	ColVarInfo *info = &ColVars[colWl.tag];
	NSColor * __strong *var = info->v, *newValue = colWl.color;
	vector_float4 newValVec = col_to_vec(newValue);
	if (simd_equal(col_to_vec(*var), newValVec)) return;
	NSColor *orgValue = *var;
	[_undoManager registerUndoWithTarget:self handler:^(id  _Nonnull target) {
		colWl.color = orgValue;
		[colWl sendAction:colWl.action to:target];
	}];
	*var = newValue;
	UInt64 mask = 1ULL << (FDBTCol + colWl.tag);
	if (simd_equal(newValVec, col_to_vec(ColVars[colWl.tag].fd))) FDBits &= ~ mask;
	else FDBits |= mask;
	btnRevertToFD.enabled = (FDBits != 0);
	[NSNotificationCenter.defaultCenter postNotificationName:
		(info->flag & ShouldPostNotification)? info->key : keyShouldRedraw object:NSApp];
}
- (IBAction)changeIntValue:(NSTextField *)dgt {
	IntVarInfo *info = &IntVars[dgt.tag];
	int *var = info->v, newValue = dgt.intValue;
	if (*var == newValue) return;
	int orgValue = *var;
	[_undoManager registerUndoWithTarget:self handler:^(id  _Nonnull target) {
		dgt.intValue = orgValue;
		[dgt sendAction:dgt.action to:target];
	}];
	*var = newValue;
	UInt64 mask = 1ULL << (FDBTInt + dgt.tag);
	if (newValue == IntVars[dgt.tag].fd) FDBits &= ~ mask;
	else FDBits |= mask;
	btnRevertToFD.enabled = (FDBits != 0);
	if (info->flag & ShouldPostNotification)
		[NSNotificationCenter.defaultCenter postNotificationName:
			info->key object:NSApp userInfo:@{keyOldValue:@(orgValue)}];
}
- (IBAction)changeFloatValue:(NSTextField *)dgt {
	FloatVarInfo *info = &FloatVars[dgt.tag];
	float *var = info->v, newValue = dgt.floatValue;
	if (*var == newValue) return;
	float orgValue = *var;
	[_undoManager registerUndoWithTarget:self handler:^(id  _Nonnull target) {
		dgt.floatValue = orgValue;
		[dgt sendAction:dgt.action to:target];
	}];
	*var = newValue;
	UInt64 mask = 1ULL << (FDBTFloat + dgt.tag);
	if (newValue == FloatVars[dgt.tag].fd) FDBits &= ~ mask;
	else FDBits |= mask;
	btnRevertToFD.enabled = (FDBits != 0);
	if (info->flag & ShouldRedrawScreen) [NSNotificationCenter.defaultCenter
		postNotificationName:keyShouldRedraw object:NSApp];
}
- (IBAction)chooseDrawMethod:(NSButton *)btn {
	PTCLDrawMethod newValue = (PTCLDrawMethod)btn.tag;
	if (ptclDrawMethod == newValue) return;
	NSButton *orgBtn = dmBtns[ptclDrawMethod];
	[_undoManager registerUndoWithTarget:self handler:^(id  _Nonnull target) {
		[orgBtn performClick:nil];
	}];
	ptclDrawMethod = newValue;
	UInt64 mask = 1ULL << FDBTDm;
	if (newValue == ptclDrawMethodFD) FDBits &= ~ mask;
	else FDBits |= mask;
	btnRevertToFD.enabled = (FDBits != 0);
	[NSNotificationCenter.defaultCenter
		postNotificationName:keyChangeDrawMethod object:NSApp];
}
- (IBAction)revertToFactoryDefault:(id)sender {
	NSMutableArray<NSString *> *postKeys = NSMutableArray.new;
	BOOL shouldRedraw = NO, *srP = &shouldRedraw;
	for_all_int_vars(^(IntVarInfo *p) {
		if (*p->v == p->fd) return;
		if (p->flag & ShouldPostNotification) [postKeys addObject:p->key];
		*p->v = p->fd; });
	for_all_float_vars(^(FloatVarInfo *p) {
		if (*p->v == p->fd) return;
		if (p->flag & ShouldRedrawScreen) *srP = YES;
		*p->v = p->fd; });
	for_all_color_vars(^(ColVarInfo *p) {
		if (simd_equal(col_to_vec(*p->v), col_to_vec(p->fd))) return;
		if (p->flag & ShouldPostNotification) [postKeys addObject:p->key];
		else *srP = YES;
		*p->v = p->fd; });
	if (ptclDrawMethod != ptclDrawMethodFD) {
		ptclDrawMethod = ptclDrawMethodFD;
		[postKeys addObject:keyChangeDrawMethod];
	}
	FDBits = 0;
	[self adjustControls];
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
		if (nm != nil) *p->v = (int)[ud integerForKey:p->key]; });
	for_all_float_vars(^(FloatVarInfo *p) {
		p->fd = *p->v;
		NSNumber *nm = [ud objectForKey:p->key];
		if (nm != nil) *p->v = [ud floatForKey:p->key]; });
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
	ptclDrawMethodFD = ptclDrawMethod;
	NSNumber *nm = [ud objectForKey:keyDrawMethod];
	if (nm != nil) ptclDrawMethod = nm.intValue;
	NSColorPanel.sharedColorPanel.showsAlpha = YES;
	[viewController reset:nil];
}
- (void)applicationWillTerminate:(NSNotification *)notification {
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	for_all_int_vars(^(IntVarInfo *p) {
		if (*p->v == p->fd) [ud removeObjectForKey:p->key];
		else [ud setInteger:*p->v forKey:p->key]; });
	for_all_float_vars(^(FloatVarInfo *p) {
		if (*p->v == p->fd) [ud removeObjectForKey:p->key];
		else [ud setFloat:*p->v forKey:p->key]; });
	for_all_color_vars(^(ColVarInfo *p) {
		vector_float4 col = col_to_vec(*p->v);
		if (simd_equal(col, col_to_vec(p->fd))) [ud removeObjectForKey:p->key];
		else {
			NSUInteger rgba =
				(((NSUInteger)(col.x * 255)) << 24) |
				(((NSUInteger)(col.y * 255)) << 16) |
				(((NSUInteger)(col.z * 255)) << 8) |
				(NSUInteger)(col.w * 255);
			char buf[16];
			sprintf(buf, "%08lX", rgba);
			[ud setObject:[NSString stringWithUTF8String:buf] forKey:p->key];
		}
	});
	if (ptclDrawMethod == ptclDrawMethodFD) [ud removeObjectForKey:keyDrawMethod];
	else [ud setBool:ptclDrawMethod forKey:keyDrawMethod];
}
@end
