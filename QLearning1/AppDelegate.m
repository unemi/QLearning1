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


@interface MyMTKView : MTKView {
	IBOutlet NSMenu *myMenu;
}
@end
@implementation MyMTKView
// pressing ESC key to exit from full screen mode. 
- (void)keyDown:(NSEvent *)event {
	if (event.keyCode == 53 && self.isInFullScreenMode)
		[self exitFullScreenModeWithOptions:nil];
	else [super keyDown:event];
}
- (void)mouseDown:(NSEvent *)event {
	if (event.buttonNumber == 2 || event.modifierFlags & NSEventModifierFlagControl)
		[NSMenu popUpContextMenu:myMenu withEvent:event forView:self];
	[super mouseDown:event];
}
@end

@implementation MyViewController {
	Agent *agent;
	Display *display;
	CGFloat interval;
	BOOL running;
	IBOutlet NSToolbarItem *startStopItem;
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
		startStopItem.label = @"Stop";
	} else {
		startStopItem.image = [NSImage imageNamed:NSImageNameTouchBarPlayTemplate];
		startStopItem.label = @"Start";
	}
}
- (IBAction)fullScreen:(id)sender {
	if (!self.view.inFullScreenMode) {
		NSScreen *screen = self.view.window.screen;
		if (scrForFullScr != nil) for (NSScreen *scr in NSScreen.screens)
			if ([scrForFullScr isEqualToString:scr.localizedName])
				{ screen = scr; break; }
		[self.view enterFullScreenMode:screen
			withOptions:@{NSFullScreenModeAllScreens:@NO}];
	} else [self.view exitFullScreenModeWithOptions:nil];
}
- (void)windowWillClose:(NSNotification *)notification {
	if (notification.object == self.view.window)
		[NSApp terminate:nil];
}
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	SEL action = menuItem.action;
	if (action == @selector(startStop:))
		menuItem.title = running? @"Stop" : @"Start";
	else if (action == @selector(fullScreen:))
		menuItem.title = self.view.isInFullScreenMode?
			@"Exit from Full Screen" : @"Full Screen";
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
		dispatch_async(dispatch_get_main_queue(), ^{
			NSMenuItem *item = [popup itemWithTitle:scrForFullScr];
			if (item != nil) [popup selectItem:item];
			else [popup selectItemAtIndex:0];
		});
	} else if (screens.count == 1) {
		[popup addItemWithTitle:screens[0].localizedName];
		dispatch_async(dispatch_get_main_queue(),
			^{ [popup selectItemAtIndex:0]; });
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
		*btnColConst, *btnColAngle, *btnColSpeed, *btnRevertToFD;
	IBOutlet NSPopUpButton *screenPopUp;
	NSArray<NSColorWell *> *colWels;
	NSArray<NSTextField *> *ivDgts, *fvDgts;
	NSArray<NSButton *> *colBtns, *dmBtns;
	int FDBTCol, FDBTInt, FDBTFloat, FDBTDc, FDBTDm, FDBTFulScr; 
	UInt64 FDBits;
}
- (NSString *)windowNibName { return @"ControlPanel"; }
- (void)adjustControls {
	for (NSColorWell *cwl in colWels) cwl.color = *ColVars[cwl.tag].v;
	for (NSTextField *dgt in ivDgts) dgt.intValue = *IntVars[dgt.tag].v;
	for (NSTextField *dgt in fvDgts) dgt.floatValue = *FloatVars[dgt.tag].v;
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
		cond:newValUlong == col_to_ulong(ColVars[colWl.tag].fd)];
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
	[self checkFDBits:FDBTInt + dgt.tag cond:newValue == IntVars[dgt.tag].fd];
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
	[self checkFDBits:FDBTFloat + dgt.tag cond:newValue == FloatVars[dgt.tag].fd];
	if (info->flag & ShouldRedrawScreen) [NSNotificationCenter.defaultCenter
		postNotificationName:keyShouldRedraw object:NSApp];
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
