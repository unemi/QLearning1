//
//  AppDelegate.m
//  QLearning1
//
//  Created by Tatsuo Unemi on 2022/12/24.
//
// Q-Learning by Look-up-table
// on simple maze.

#import "AppDelegate.h"
#import "MainWindow.h"
#import "Display.h"
#import "Agent.h"
#import "MySound.h"
@import UniformTypeIdentifiers;

int Move[4][2] = {{0,1},{1,0},{0,-1},{-1,0}}; // up, right, down, left
int ObsP[NObstacles][2] = {{2,2},{2,3},{2,4},{5,1},{7,3},{7,4},{7,5}};
int FieldP[NActiveGrids][2];
int Obstacles[NGridH][NGridW];
int StartP[] = {0,3}, GoalP[] = {8,5};
NSString *keyCntlPnl = @"controlPanel";
NSString *keyOldValue = @"oldValue", *keyShouldRedraw = @"shouldRedraw";
NSString *keyColorMode = @"ptclColorMode", *keyDrawMethod = @"ptclDrawMethod";
static NSString *scrForFullScrFD, *keyScrForFullScr = @"screenForFullScreenMode";
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
	{ @"colorParticles", &colParticles, nil, ShouldPostNotification },
	{ nil }
};
UIntegerVarInfo UIntegerVars[] = {
	{ @"maxSteps", 8000 },
	{ @"maxGoalCount", 60 },
	{ nil }
};
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

static SoundSrc sndData[NVoices] = {
	{ @"Frog", nil, 1 },
	{ @"Submarine", nil, 2 },
//	{ @"People/Kids Cheering.caf", @"iLife", 2 },
//	{ @"People/Children Aaaah.caf", @"iLife", 2 },
	{ @"Stingers/Ethereal Accents.caf", @"iLife", 2 },
	{ @"Stingers/Electric Flutters 02.caf", @"iLife", 2 },
	{ @"Cave and Wind.mp3", @"iMovie", 2 }
//	{ @"EnvNoise1", nil, 2 }
};

static struct {
	NSString *key, *fdValue;
	NSButton *playBtn;
	int FDBit;
} sndInfo[] = {
	{ @"soundBump", nil, nil, 0 },
	{ @"soundGoal", nil, nil, 0 }
};

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
void error_msg(NSObject *obj, NSWindow *window) {
	NSAlert *alt = NSAlert.new;
	alt.alertStyle = NSAlertStyleCritical;
	if ([obj isKindOfClass:NSError.class]) {
		NSError *error = (NSError *)obj;
		alt.messageText = error.localizedDescription;
		alt.informativeText = [NSString stringWithFormat:@"%@\n%@",
			error.localizedFailureReason, error.localizedRecoverySuggestion];
	} else if ([obj isKindOfClass:NSString.class])
		alt.messageText = (NSString *)obj;
	else alt.messageText = @"Unknown error.";
	if (window == nil) [alt runModal];
	else [alt beginSheetModalForWindow:window
		completionHandler:^(NSModalResponse returnCode) {
	}];
}
void err_msg(NSString *msg, OSStatus err, BOOL isFatal) {
	NSAlert *alt = NSAlert.new;
	alt.alertStyle = isFatal? NSAlertStyleCritical : NSAlertStyleWarning;
	alt.messageText = msg;
	alt.informativeText = [NSString stringWithFormat:@"Error code = %d", err];
	[alt runModal];
	if (isFatal) [NSApp terminate:nil];
}

NSUInteger col_to_ulong(NSColor *col) {
	CGFloat c[4] = {0., 0., 0., 1.};
	[[col colorUsingColorSpace:NSColorSpace.genericRGBColorSpace]
		getComponents:c];
	return (((NSUInteger)(c[0] * 255)) << 24) |
		(((NSUInteger)(c[1] * 255)) << 16) |
		(((NSUInteger)(c[2] * 255)) << 8) |
		(NSUInteger)(c[3] * 255);
}
static NSColor *ulong_to_col(NSUInteger rgba) {
	CGFloat c[4] = {
		(rgba >> 24) / 255.,
		((rgba >> 16) & 255) / 255.,
		((rgba >> 8) & 255) / 255.,
		(rgba & 255) / 255.};
	return [NSColor colorWithColorSpace:
		NSColorSpace.genericRGBColorSpace components:c count:4];
}
static NSUInteger hex_string_to_uint(NSString *str) {
	NSScanner *scan = [NSScanner scannerWithString:str];
	unsigned int uInt;
	[scan scanHexInt:&uInt];
	return (NSUInteger)uInt;
}

@implementation AppDelegate {
	MainWindow *mainWindow;
	ControlPanel *controlPanel;
}
- (IBAction)openControlPanel:(id)sender {
	if (controlPanel == nil) {
		controlPanel = [ControlPanel.alloc initWithWindow:nil];
		controlPanel.nextResponder = mainWindow;
	}
	[controlPanel showWindow:sender];
}
- (void)applicationWillFinishLaunching:(NSNotification *)aNotification {
	init_default_colors();
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
		NSUInteger rgba = hex_string_to_uint(str);
		*p->v = ulong_to_col(rgba);
	});
	ptclColorModeFD = ptclColorMode;
	ptclDrawMethodFD = ptclDrawMethod;
	scrForFullScrFD = scrForFullScr;
	sndInfo[SndBump].fdValue = sndData[SndBump].name;
	sndInfo[SndGoal].fdValue = sndData[SndGoal].name;
	NSNumber *nm = [ud objectForKey:keyColorMode];
	if (nm != nil) ptclColorMode = nm.intValue;
	nm = [ud objectForKey:keyDrawMethod];
	if (nm != nil) ptclDrawMethod = nm.intValue;
	NSString *str = [ud objectForKey:keyScrForFullScr];
	if (str != nil) scrForFullScr = str;
	for (SoundType type = 0; type < 2; type ++)
		if ((str = [ud objectForKey:sndInfo[type].key]) != nil) sndData[type].name = str;
	NSColorPanel.sharedColorPanel.showsAlpha = YES;
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
	mainWindow = [MainWindow.alloc initWithWindow:nil];
	[mainWindow showWindow:nil];
	if (START_WIDTH_FULL_SCR) {
		[NSTimer scheduledTimerWithTimeInterval:.1 repeats:NO
			block:^(NSTimer * _Nonnull timer) {
			[self->mainWindow fullScreen:nil];
			[NSTimer scheduledTimerWithTimeInterval:.5 repeats:NO
				block:^(NSTimer * _Nonnull timer) {
				[self->mainWindow startStop:nil]; }];
		}];
	} else [mainWindow adjustForRecordView:nil];
	init_audio_out(sndData, NVoices);
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
	for (SoundType type = 0; type < 2; type ++) {
		if ([sndData[type].name isEqualToString:sndInfo[type].fdValue])
			[ud removeObjectForKey:sndInfo[type].key];
		else [ud setObject:sndData[type].name forKey:sndInfo[type].key];
	}
}
@end

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
static NSString *SysSndDir = @"/System/Library/Sounds";
static void setup_sound_menu(NSPopUpButton *popup) {
	NSError *error;
	NSArray<NSString *> *list = [NSFileManager.defaultManager
		contentsOfDirectoryAtPath:SysSndDir error:&error];
	if (list == nil) { error_msg(error, nil); return; }
	list = [list sortedArrayUsingSelector:@selector(compare:)];
	[popup itemAtIndex:0].title = @"None";
	for (NSString *name in list) if ([name hasSuffix:@".aiff"])
		[popup addItemWithTitle:[name stringByDeletingPathExtension]];
}
@implementation ControlPanel {
	IBOutlet NSColorWell *cwlBackground, *cwObstacles, *cwAgent,
		*cwGridLines, *cwSymbols, *cwParticles;
	IBOutlet NSTextField *dgtMemSize, *dgtMemTrials, *dgtNParticles, *dgtLifeSpan;
	IBOutlet NSTextField *dgtT0, *dgtT1, *dgtCoolingRate, *dgtInitQValue, *dgtGamma, *dgtAlpha,
		*dgtMass, *dgtFriction, *dgtStrokeLength, *dgtStrokeWidth, *dgtMaxSpeed;
	IBOutlet NSButton *btnDrawByRects, *btnDrawByTriangles, *btnDrawByLines,
		*btnColConst, *btnColAngle, *btnColSpeed,
		*cboxStartFullScr, *cboxRecordImages, *btnRevertToFD, *btnExport;
	IBOutlet NSPopUpButton *screenPopUp, *sndBumpPopUp, *sndGoalPopUp;
	IBOutlet NSButton *playBumpBtn, *playGoalBtn;
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
	[sndBumpPopUp selectItemWithTitle:sndData[SndBump].name];
	[sndGoalPopUp selectItemWithTitle:sndData[SndGoal].name];
	playBumpBtn.enabled = (sndBumpPopUp.indexOfSelectedItem > 0);
	playGoalBtn.enabled = (sndGoalPopUp.indexOfSelectedItem > 0);
	dgtCoolingRate.enabled = (MAX_STEPS == 0);
	btnRevertToFD.enabled = btnExport.enabled = (FDBits != 0);
}
- (void)windowDidLoad {
	[super windowDidLoad];
	if (self.window == nil) return;
	_undoManager = NSUndoManager.new;
	setup_screen_menu(screenPopUp);
	setup_sound_menu(sndBumpPopUp);
	setup_sound_menu(sndGoalPopUp);
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
	for (SoundType type = 0; type < 2; type ++) {
		sndInfo[type].FDBit = (int)(++ bit);
		if (![sndData[type].name isEqualToString:sndInfo[type].fdValue]) FDBits |= 1 << bit;
	}
	sndInfo[SndBump].playBtn = playBumpBtn;
	sndInfo[SndGoal].playBtn = playGoalBtn;
	[self adjustControls];
}
- (void)checkFDBits:(NSInteger)bitPosition cond:(BOOL)cond {
	UInt64 mask = 1ULL << bitPosition;
	if (cond) FDBits &= ~ mask;
	else FDBits |= mask;
	btnRevertToFD.enabled = btnExport.enabled = (FDBits != 0);
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
			info->key object:NSApp userInfo:@{keyOldValue:@(orgValue), keyCntlPnl:self}];
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
	if (dgt.tag == MAX_STEPS_TAG)
		dgtCoolingRate.enabled = (MAX_STEPS == 0);
	[NSNotificationCenter.defaultCenter
		postNotificationName:info->key object:NSApp];
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
		[NSNotificationCenter.defaultCenter
			postNotificationName:info->key object:NSApp];
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
	[NSNotificationCenter.defaultCenter postNotificationName:
		keyColorMode object:NSApp userInfo:@{keyCntlPnl:self}];
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
	[NSNotificationCenter.defaultCenter postNotificationName:
		keyDrawMethod object:NSApp userInfo:@{keyCntlPnl:self}];
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
- (IBAction)chooseSound:(NSPopUpButton *)popUp {
	SoundType type = (SoundType)popUp.tag;
	NSString *orgValue = sndData[type].name,
		*newValue = [popUp titleOfSelectedItem];
	if ([orgValue isEqualToString:newValue]) return;
	[_undoManager registerUndoWithTarget:self handler:^(id _Nonnull target) {
		[popUp selectItemWithTitle:orgValue];
		[popUp sendAction:popUp.action to:target];
	}];
	change_sound_data(type, newValue);
//	if (popUp.indexOfSelectedItem > 0)
//		change_sound_data(type);
//	else if (sndData[type].buf != NULL) {
//		free(sndData[type].buf);
//		sndData[type].buf = NULL;
//	}
	sndInfo[type].playBtn.enabled = (popUp.indexOfSelectedItem > 0);
	[self checkFDBits:sndInfo[type].FDBit cond:
		[newValue isEqualToString:sndInfo[type].fdValue]];
}
- (IBAction)listenSound:(NSButton *)btn {
	NSString *path = [NSString stringWithFormat:
		@"%@/%@.aiff", SysSndDir, sndData[btn.tag].name];
	NSSound *snd = [NSSound.alloc initWithContentsOfFile:path byReference:YES];
	[snd play];
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
	for (SoundType type = 0; type < 2; type ++)
		if (![sndData[type].name isEqualToString:sndInfo[type].fdValue])
			md[sndInfo[type].key] = sndInfo[type].fdValue;
	[self setParamValuesFromDict:md];
}
static void set_sound_from_dict(NSDictionary *dict, SoundType type,
	NSString *key, NSString *fdName, NSMutableDictionary *orgValues, int bit, UInt64 *fbP) {
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
		[postKeys addObject:p->key];
		orgValues[p->key] = @(p->v);
		if (newValue == p->fd || p->v == p->fd)
			*fbP |= 1 << (self->FDBTUInt + (p - UIntegerVars));
		p->v = newValue;
	});
	for_all_bool_vars(^(BoolVarInfo *p) {
		NSNumber *num = dict[p->key]; if (num == nil) return;
		BOOL newValue = num.boolValue; if (p->v == newValue) return;
		if (p->flag & ShouldPostNotification) [postKeys addObject:p->key];
		orgValues[p->key] = @(p->v);
		if (newValue == p->fd || p->v == p->fd)
			*fbP |= 1 << (self->FDBTBool + (p - BoolVars));
		p->v = newValue;
	});
	for_all_color_vars(^(ColVarInfo *p) {
		NSObject *newValue = dict[p->key];
		if (newValue == nil) return;
		NSUInteger uIntCol; NSColor *newCol = nil;
		if ([newValue isKindOfClass:NSColor.class]) {
			newCol = (NSColor *)newValue;
			uIntCol = col_to_ulong(newCol);
		} else if ([newValue isKindOfClass:NSString.class]) {
			uIntCol = hex_string_to_uint((NSString *)newValue);
		} else return;
		if (col_to_ulong(*p->v) == uIntCol) return;
		if (p->flag & ShouldPostNotification) [postKeys addObject:p->key];
		else *srP = YES;
		orgValues[p->key] = *p->v;
		NSInteger fdCol = col_to_ulong(p->fd);
		if (uIntCol == fdCol || col_to_ulong(*p->v) == fdCol)
			*fbP |= 1 << (self->FDBTCol + (p - ColVars));
		*p->v = (newCol != nil)? newCol : ulong_to_col(uIntCol); });
	NSNumber *num = dict[keyColorMode];
	if (num != nil) {
		PTCLColorMode newValue = num.intValue;
		if (ptclColorMode != newValue) {
			orgValues[keyColorMode] = @(ptclColorMode);
			if (ptclColorMode == ptclColorModeFD || newValue == ptclColorModeFD)
				*fbP |= 1 << FDBTDc;
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
				fdFlipBits |= 1 << FDBTDm;
			ptclDrawMethod = newValue;
			[postKeys addObject:keyDrawMethod];
		}
	}
	NSString *newValue = dict[keyScrForFullScr];
	if (newValue != nil && ![scrForFullScr isEqualToString:newValue]) {
		orgValues[keyScrForFullScr] = scrForFullScr;
		if (scrForFullScr == scrForFullScrFD || newValue == scrForFullScrFD)
			fdFlipBits |= 1 << FDBTFulScr;
		scrForFullScr = newValue;
	}
	for (SoundType type = 0; type < 2; type ++)
		if ((newValue = dict[sndInfo[type].key]) != nil
		 && ![sndData[type].name isEqualToString:newValue]) {
			orgValues[sndInfo[type].key] = sndData[type].name;
			if ([@[newValue, sndData[type].name] containsObject:sndInfo[type].fdValue])
				fdFlipBits |= 1 << sndInfo[type].FDBit;
				change_sound_data(type, newValue);
	}
	FDBits ^= fdFlipBits;
	[self adjustControls];
	[_undoManager registerUndoWithTarget:self handler:^(id _Nonnull target) {
		[self setParamValuesFromDict:orgValues];
	}];
	for (NSString *key in postKeys) [NSNotificationCenter.defaultCenter
		postNotificationName:key object:NSApp
		userInfo:@{keyCntlPnl:self, keyOldValue:orgValues[key]}];
	if (shouldRedraw) [NSNotificationCenter.defaultCenter
		postNotificationName:keyShouldRedraw object:NSApp];
}
- (NSDictionary *)propertyListOfParamValues {
	NSMutableDictionary *md = NSMutableDictionary.new;
	for_all_int_vars(^(IntVarInfo *p) {
		if (*p->v != p->fd) md[p->key] = @(*p->v);
	});
	for_all_float_vars(^(FloatVarInfo *p) {
		if (*p->v != p->fd) md[p->key] = @(*p->v);
	});
	for_all_uint_vars(^(UIntegerVarInfo *p) {
		if (p->v != p->fd) md[p->key] = @(p->v);
	});
	for_all_bool_vars(^(BoolVarInfo *p) {
		if (p->v != p->fd) md[p->key] = @(p->v);
	});
	for_all_color_vars(^(ColVarInfo *p) {
		NSUInteger uIntCol =  col_to_ulong(*p->v);
		if (uIntCol != col_to_ulong(p->fd))
			md[p->key] = [NSString stringWithFormat:@"%08lX", uIntCol];
	});
	if (ptclColorMode != ptclColorModeFD) md[keyColorMode] = @(ptclColorMode);
	if (ptclDrawMethod != ptclDrawMethodFD) md[keyDrawMethod] = @(ptclDrawMethod);
	if (![scrForFullScr isEqualToString:scrForFullScrFD])
		md[keyScrForFullScr] = scrForFullScr;
	return md;
}

- (IBAction)importSettings:(id)sender {
	NSOpenPanel *op = NSOpenPanel.new;
	op.allowedContentTypes = @[UTTypeXMLPropertyList];
	[op beginSheetModalForWindow:self.window
		completionHandler:^(NSModalResponse result) {
		if (result != NSModalResponseOK) return;
		NSError *error;
		NSData *data = [NSData dataWithContentsOfURL:op.URL options:0 error:&error];
		if (data == nil) { error_msg(error, self.window); return; }
		NSDictionary *plist = [NSPropertyListSerialization
			propertyListWithData:data options:0 format:NULL error:&error];
		if (plist == nil) { error_msg(error, self.window); return; }
		[self setParamValuesFromDict:plist];
	}];
}
- (IBAction)exportSettings:(id)sender {
	static UTType *settingsUTI = nil;
	if (settingsUTI == nil) settingsUTI =
		[UTType exportedTypeWithIdentifier:
			@"jp.ac.soka.unemi.QLearning1-settings"];
	NSSavePanel *sp = NSSavePanel.new;
	sp.allowedContentTypes = @[settingsUTI];
	[sp beginSheetModalForWindow:self.window
		completionHandler:^(NSModalResponse result) {
		if (result != NSModalResponseOK) return;
		NSError *error;
		NSDictionary *plist = [self propertyListOfParamValues];
		NSData *data = [NSPropertyListSerialization
			dataWithPropertyList:plist format:NSPropertyListXMLFormat_v1_0
			options:0 error:&error];
		if (data == nil) { error_msg(error, self.window); return; }
		if (![data writeToURL:sp.URL options:0 error:&error])
			error_msg(error, self.window);
	}];
}
- (void)adjustNParticleDgt { // called when memory allocation failed.
	dgtNParticles.integerValue = NParticles;
	int idx;
	for (idx = 0; IntVars[idx].key != nil; idx ++)
		if (IntVars[idx].v == &NParticles) break;
	[self checkFDBits:FDBTInt + idx cond:NParticles == IntVars[idx].fd];
}
- (void)adjustColorMode:(NSDictionary *)info { // called when buffer allocation failed.
	NSNumber *num = info[keyOldValue];
	if (num != nil) {
		ptclColorMode = (PTCLColorMode)num.intValue;
		for (NSButton *btn in colBtns) btn.state = (ptclColorMode == btn.tag);
		[self checkFDBits:FDBTDc cond:ptclColorMode == ptclColorModeFD];
	} else [_undoManager undo];
}
- (void)adjustDrawMethod:(NSDictionary *)info { // called when buffer allocation failed.
	NSNumber *num = info[keyOldValue];
	if (num != nil) {
		ptclDrawMethod = (PTCLDrawMethod)num.intValue;
		for (NSButton *btn in dmBtns) btn.state = (ptclDrawMethod == btn.tag);
		[self checkFDBits:FDBTDm cond:ptclDrawMethod == ptclDrawMethodFD];
	} else [_undoManager undo];
}
//
- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window {
	return _undoManager;
}
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	SEL action = menuItem.action;
	if (action == @selector(exportSettings:)
	 || action == @selector(revertToFactoryDefault:)) return btnExport.enabled;
	return YES;
}
@end
