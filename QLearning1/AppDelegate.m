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
NSString *keyOldValue = @"oldValue",
	*keyShouldRedraw = @"shouldRedraw", *keyShouldReviseVertices = @"shouldReviseVertices";
NSString *keyColorMode = @"ptclColorMode", *keyDrawMethod = @"ptclDrawMethod";
static NSString *scrForFullScrFD, *keyScrForFullScr = @"screenForFullScreenMode";
static PTCLColorMode ptclColorModeFD;
static PTCLDrawMethod ptclDrawMethodFD;
enum {
	ShouldPostNotification = 1,
	ShouldRedrawScreen = 2,
	ShouldReviseVertices = 4
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
	{ @"ptclLength", &StrokeLength, 0, ShouldReviseVertices },
	{ @"ptclWeight", &StrokeWidth, 0, ShouldReviseVertices },
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
	{ @"useSharedBuffer", YES, },
	{ @"showFPS", YES, YES, ShouldPostNotification },
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

SoundSrc sndData[NVoices] = {
	{ @"soundBump", 1, { @"/System/Library/Sounds/Frog.aiff", -.5, .5, 1.} },
	{ @"soundGoal", 2, { @"/System/Library/Sounds/Submarine.aiff", -.5, .5, 1.} },
//	{ @"People/Kids Cheering.caf", @"iLife", 2 },
//	{ @"People/Children Aaaah.caf", @"iLife", 2 },
	{ @"soundGood", 2, { @"/Applications/iMovie.app/Contents/Resources/iLife Sound Effects/"
		@"Stingers/Ethereal Accents.caf", 0., 0., 1.} },
	{ @"soundBad", 2, { @"/Applications/iMovie.app/Contents/Resources/iLife Sound Effects/"
		@"Stingers/Electric Flutters 02.caf", 0., 0., 1.} },
	{ @"soundAmbience", 2, { @"/Applications/iMovie.app/Contents/Resources/iMovie Sound Effects/"
		@"Cave and Wind.mp3", -1., 7., 1.} }
//	{ @"EnvNoise1", nil, 2 }
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
	union { OSStatus e; char c[4]; } u = { .e = EndianU32_NtoB(err) };
	char s[8];
	for (int i = 0; i < 4; i ++) s[i] = (u.c[i] < ' ' || u.c[i] >= 127)? ' ' : u.c[i];
	s[4] = '\0';
	NSAlert *alt = NSAlert.new;
	alt.alertStyle = isFatal? NSAlertStyleCritical : NSAlertStyleWarning;
	alt.messageText = msg;
	alt.informativeText = [NSString stringWithFormat:@"Error code = %s", s];
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
static BOOL prm_equal(SoundPrm *a, SoundPrm *b) {
	return [a->path isEqualToString:b->path] &&
		a->mmin == b->mmin && a->mmax == b->mmax && a->vol == b->vol;
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
	NSNumber *nm = [ud objectForKey:keyColorMode];
	if (nm != nil) ptclColorMode = nm.intValue;
	nm = [ud objectForKey:keyDrawMethod];
	if (nm != nil) ptclDrawMethod = nm.intValue;
	NSString *str = [ud objectForKey:keyScrForFullScr];
	if (str != nil) scrForFullScr = str;
	NSFileManager *fm = NSFileManager.defaultManager;
	NSMutableDictionary<NSString *, NSString *> *missingSnd = NSMutableDictionary.new;
	for (SoundType type = 0; type < NVoices; type ++) {
		SoundSrc *s = &sndData[type];
		s->fd = s->v;
		NSObject *obj = [ud objectForKey:s->key];
		if ([obj isKindOfClass:NSString.class]) s->v.path = (NSString *)obj;
		else if ([obj isKindOfClass:NSDictionary.class]) {
			NSDictionary *dict = (NSDictionary *)obj;
			if ((str = dict[@"path"]) != nil) s->v.path = str;
			if ((nm = dict[@"mmin"]) != nil) s->v.mmin = nm.floatValue;
			if ((nm = dict[@"mmax"]) != nil) s->v.mmax = nm.floatValue;
			if ((nm = dict[@"vol"]) != nil) s->v.vol = nm.floatValue;
		}
		s->loaded = @"";
		if (s->v.path.length > 0 && ![fm fileExistsAtPath:s->v.path]) {
			missingSnd[s->key] = s->v.path;
			s->v.path = @"";
		}
	}
	if (missingSnd.count > 0) {
		NSMutableString *msg = NSMutableString.new;
		[msg appendString:@"Could not find sound file"];
		for (NSString *key in missingSnd)
			[msg appendFormat:@"\n%@ for %@", missingSnd[key], [key substringFromIndex:5]];
		[msg appendString:@"."];
		error_msg(msg, nil);
	}
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
	init_audio_out();
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
	for (SoundType type = 0; type < NVoices; type ++) {
		SoundSrc *s = &sndData[type];
		if (prm_equal(&s->v, &s->fd)) [ud removeObjectForKey:s->key];
		else {
			NSMutableDictionary *md = NSMutableDictionary.new;
			if (![s->v.path isEqualToString:s->fd.path]) md[@"path"] = s->v.path;
			if (s->v.mmin != s->fd.mmin) md[@"mmin"] = @(s->v.mmin);
			if (s->v.mmax != s->fd.mmax) md[@"mmax"] = @(s->v.mmax);
			if (s->v.vol != s->fd.vol) md[@"vol"] = @(s->v.vol);
			[ud setObject:md forKey:s->key];
		}
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
@implementation ControlPanel {
	IBOutlet NSColorWell *cwlBackground, *cwObstacles, *cwAgent,
		*cwGridLines, *cwSymbols, *cwParticles;
	IBOutlet NSTextField *dgtMemSize, *dgtMemTrials, *dgtNParticles, *dgtLifeSpan;
	IBOutlet NSTextField *dgtT0, *dgtT1, *dgtCoolingRate, *dgtInitQValue, *dgtGamma, *dgtAlpha,
		*dgtMass, *dgtFriction, *dgtStrokeLength, *dgtStrokeWidth, *dgtMaxSpeed;
	IBOutlet NSButton *btnDrawByRects, *btnDrawByTriangles, *btnDrawByLines,
		*btnColConst, *btnColAngle, *btnColSpeed,
		*cboxStartFullScr, *cboxRecordImages, *cboxUseSharedBuffer, *cBoxShowFPS,
		*btnRevertToFD, *btnExport;
	IBOutlet NSPopUpButton *screenPopUp;
	IBOutlet NSTextField *txtBump, *txtGaol, *txtGood, *txtBad, *txtAmbience;
	IBOutlet NSButton *playBump, *playGoal, *playGood, *playBad, *playAmbience;
	IBOutlet NSPanel *sndPanel;
	IBOutlet NSTextField *sndPTitle, *sndPInfo, *sndPMMin, *sndPMMax, *sndPVol, *sndPMVal;
	IBOutlet NSSlider *sndPMValSld, *sndPVolSld;
	IBOutlet NSButton *sndPlayStopBtn, *sndPMSetMinBtn, *sndPMSetMaxBtn, *sndPRevertBtn;
	IBOutlet NSTextField *dgtMaxSteps, *dgtMaxGoalCnt;
	NSArray<NSColorWell *> *colWels;
	NSArray<NSTextField *> *ivDgts, *fvDgts, *uvDgts, *sndTxts;
	NSArray<NSButton *> *colBtns, *dmBtns, *boolVBtns, *playBtns;
	NSArray<NSControl *> *sndContrls;
	NSSound *soundNowPlaying;
	NSUndoManager *undoManager, *undoMng4SndPnl;
	SoundType playingSoundType, openingSoundType;
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
	for (SoundType type = 0; type < NVoices; type ++) {
		SoundSrc *s = &sndData[type];
		sndTxts[type].stringValue = s->v.path.lastPathComponent;
		playBtns[type].enabled = (s->v.path.length > 0);
	}
	dgtCoolingRate.enabled = (MAX_STEPS == 0);
	btnRevertToFD.enabled = btnExport.enabled = (FDBits != 0);
}
#define SETUP_CNTRL(b,class,list,fn,var,ref,act)	b = (int)bit; tag = 0;\
	for (class *ctr in list) {\
		if (fn(var ref[tag].v) != fn(ref[tag].fd)) FDBits |= 1 << bit;\
		ctr.target = self;\
		ctr.action = @selector(act:);\
		ctr.tag = tag ++; bit ++;\
	}
#define SETUP_RADIOBTN(b,var,fd,list,act)	b = (int)(bit ++); tag = 0;\
	if (var != fd) FDBits |= 1 << b;\
	for (NSButton *btn in list) {\
		btn.target = self;\
		btn.action = @selector(act:);\
		btn.tag = tag ++;\
	}
- (void)windowDidLoad {
	[super windowDidLoad];
	if (self.window == nil) return;
	undoManager = NSUndoManager.new;
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
	boolVBtns = @[cboxStartFullScr, cboxRecordImages, cboxUseSharedBuffer, cBoxShowFPS];
	colBtns = @[btnColConst, btnColAngle, btnColSpeed];
	dmBtns = @[btnDrawByRects, btnDrawByTriangles, btnDrawByLines];
	sndTxts = @[txtBump, txtGaol, txtGood, txtBad, txtAmbience];
	playBtns = @[playBump, playGoal, playGood, playBad, playAmbience];
	sndContrls = @[sndPMVal, sndPMValSld, sndPVolSld, sndPMSetMinBtn, sndPMSetMaxBtn];
	NSInteger bit = 0, tag;
	SETUP_CNTRL(FDBTCol, NSColorWell, colWels, col_to_ulong, *, ColVars, chooseColorWell)
	SETUP_CNTRL(FDBTInt, NSTextField, ivDgts, , *, IntVars, changeIntValue)
	SETUP_CNTRL(FDBTFloat, NSTextField, fvDgts, , *, FloatVars, changeFloatValue)
	SETUP_CNTRL(FDBTUInt, NSTextField, uvDgts, , , UIntegerVars, changeUIntegerValue)
	SETUP_CNTRL(FDBTBool, NSButton, boolVBtns, , , BoolVars, switchBoolValue)
	SETUP_RADIOBTN(FDBTDc, ptclColorMode, ptclColorModeFD, colBtns, chooseColorMode)
	SETUP_RADIOBTN(FDBTDm, ptclDrawMethod, ptclDrawMethodFD, dmBtns, chooseDrawMethod)
	FDBTFulScr = (int)bit;
	if (scrForFullScr != scrForFullScrFD) FDBits |= 1 << bit;
	for (SoundType type = 0; type < NVoices; type ++) {
		SoundSrc *s = &sndData[type];
		s->FDBit = (int)(++ bit);
		if (!prm_equal(&s->v, &s->fd)) FDBits |= 1 << bit;
	}
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
	[undoManager registerUndoWithTarget:self handler:^(id _Nonnull target) {
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
	[undoManager registerUndoWithTarget:self handler:^(id _Nonnull target) {
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
	[undoManager registerUndoWithTarget:self handler:^(id _Nonnull target) {
		dgt.floatValue = orgValue;
		[dgt sendAction:dgt.action to:target];
	}];
	*var = newValue;
	[self checkFDBits:FDBTFloat + dgt.tag cond:newValue == info->fd];
	if (info->flag & ShouldRedrawScreen) [NSNotificationCenter.defaultCenter
		postNotificationName:keyShouldRedraw object:NSApp];
	if (info->flag & ShouldReviseVertices) [NSNotificationCenter.defaultCenter
		postNotificationName:keyShouldReviseVertices object:NSApp];
}
- (IBAction)changeUIntegerValue:(NSTextField *)dgt {
	UIntegerVarInfo *info = &UIntegerVars[dgt.tag];
	NSUInteger newValue = dgt.integerValue, orgValue = info->v;
	if (orgValue == newValue) return;
	[undoManager registerUndoWithTarget:self handler:^(id _Nonnull target) {
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
	[undoManager registerUndoWithTarget:self handler:^(id _Nonnull target) {
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
	[undoManager registerUndoWithTarget:self handler:^(id _Nonnull target) {
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
	[undoManager registerUndoWithTarget:self handler:^(id _Nonnull target) {
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
	[undoManager registerUndoWithTarget:self handler:^(id _Nonnull target) {
		if ([popUp itemWithTitle:orgValue] != nil)
			[popUp selectItemWithTitle:orgValue];
		else [popUp selectItemAtIndex:0];
		[popUp sendAction:popUp.action to:target];
	}];
	scrForFullScr = newValue;
	[self checkFDBits:FDBTFulScr cond:newValue == scrForFullScrFD];
}
static NSString *sound_name(SoundType type) {
	return [sndData[type].key substringFromIndex:5];
}
- (void)setSoundType:(SoundType)type prm:(SoundPrm)prm {
	SoundSrc *s = &sndData[type];
	SoundPrm orgPrm = s->v;
	change_sound_data(type, prm.path);
	sndTxts[type].stringValue = prm.path.lastPathComponent;
	s->v = prm;
	[self checkFDBits:sndData[type].FDBit cond:prm_equal(&orgPrm, &prm)];
	[undoManager registerUndoWithTarget:self handler:^(id _Nonnull target) {
		[self setSoundType:type prm:orgPrm];
	}];
}
- (SoundPrm)getSoundParamsFromPanel {
	return (SoundPrm){ sndPInfo.stringValue,
		sndPMMin.doubleValue, sndPMMax.doubleValue, sndPVol.doubleValue };
}
- (void)stopIfNeeded {
	if (sndPlayStopBtn.state == NSControlStateValueOn) {
		sndPlayStopBtn.state = NSControlStateValueOff;
		[sndPlayStopBtn sendAction:sndPlayStopBtn.action to:sndPlayStopBtn.target];
	}
}
- (void)beginSoundPanel {
	SoundType type = openingSoundType;
	SoundSrc *s = &sndData[type];
	SoundPrm prm = [self getSoundParamsFromPanel];
	sndPRevertBtn.enabled = !prm_equal(&prm, &s->fd);
	[self.window beginSheet:sndPanel completionHandler:^(NSModalResponse returnCode) {
		switch (returnCode) {
			case NSModalResponseOK: {
				SoundPrm newPrm = [self getSoundParamsFromPanel], orgPrm = prm;
				if (!prm_equal(&newPrm, &orgPrm))
					[self setSoundType:type prm:newPrm];
			}
			case NSModalResponseCancel:
			self->undoMng4SndPnl = nil;
			[self stopIfNeeded];
			default: break;
		}
	}];
}
- (void)setSoundParamToPanel:(SoundPrm *)p {
	sndPInfo.stringValue = p->path;
	sndPMMin.doubleValue = sndPMValSld.minValue = p->mmin;
	sndPMMax.doubleValue = sndPMValSld.maxValue = p->mmax;
	sndPVol.doubleValue = sndPVolSld.doubleValue = p->vol;
	((NSNumberFormatter *)sndPMMin.formatter).maximum = @(p->mmax);
	((NSNumberFormatter *)sndPMMax.formatter).minimum = @(p->mmin);
	sndPMVal.doubleValue = sndPMValSld.doubleValue = (p->mmin + p->mmax) / 2.;
	sndPRevertBtn.enabled = !prm_equal(p, &sndData[openingSoundType].fd);
}
- (void)checkRevertable {
	SoundPrm prm = [self getSoundParamsFromPanel];
	sndPRevertBtn.enabled = !prm_equal(&prm, &sndData[openingSoundType].fd);
}
static NSString *keyPath = @"path", *keyPMMin = @"pmMin", *keyPMMax = @"pmMax",
	*keyPM = @"pm", *keyVol = @"vol";
- (NSDictionary *)sndParamDict {
	return @{keyPath:sndPInfo.stringValue,
		keyPMMin:@(sndPMMin.doubleValue), keyPMMax:@(sndPMMax.doubleValue),
		keyPM:@(sndPMVal.doubleValue), keyVol:@(sndPVol.doubleValue)};
}
- (void)setDictToPanel:(NSDictionary *)dict {
	[undoMng4SndPnl registerUndoWithTarget:self
		selector:@selector(setDictToPanel:) object:[self sndParamDict]];
	SoundPrm prm = {dict[keyPath],
		[dict[keyPMMin] doubleValue], [dict[keyPMMax] doubleValue],
		[dict[keyVol] doubleValue] };
	[self setSoundParamToPanel:&prm];
	sndPMVal.doubleValue = sndPMValSld.doubleValue = [dict[keyPM] doubleValue];
}
- (IBAction)openSoundPanel:(NSButton *)btn {
	SoundType type = openingSoundType = (SoundType)btn.tag;
	sndPTitle.stringValue = [NSString stringWithFormat:@"%@ Sound Settings", sound_name(type)];
	[self setSoundParamToPanel:&sndData[type].v];
	undoMng4SndPnl = NSUndoManager.new;
	[self beginSoundPanel];
}
- (IBAction)soundPanelOK:(id)sender {
	[self.window endSheet:sndPanel returnCode:NSModalResponseOK];
}
- (IBAction)soundPanelCancel:(id)sender {
	[self.window endSheet:sndPanel returnCode:NSModalResponseCancel];
}
- (void)setSndPInfoPath:(NSString *)newPath {
	[undoMng4SndPnl registerUndoWithTarget:self
		selector:@selector(setSndPInfoPath:) object:sndPInfo.stringValue];
	sndPInfo.stringValue = newPath;
	[self checkRevertable];
	[self stopIfNeeded];
}
- (IBAction)chooseSound:(NSButton *)btn {
	[self.window endSheet:sndPanel returnCode:NSModalResponseStop];
	NSOpenPanel *op = NSOpenPanel.openPanel;
	op.allowedContentTypes = @[UTTypeAudio];
	op.directoryURL = [NSURL fileURLWithPath:
		sndPInfo.stringValue.stringByDeletingLastPathComponent];
	op.message = [NSString stringWithFormat:
		@"Choose a sound file for %@.", sound_name(openingSoundType)];
	op.delegate = self;
	op.treatsFilePackagesAsDirectories = YES;
	[op beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
		if (result == NSModalResponseOK) [self setSndPInfoPath:op.URL.path];
		[self beginSoundPanel];
	}];
}
- (IBAction)defaultFile:(NSButton *)sender {
	[undoMng4SndPnl registerUndoWithTarget:self
		selector:@selector(setDictToPanel:) object:[self sndParamDict]];
	SoundSrc *s = &sndData[openingSoundType];
	[self setSoundParamToPanel:&s->fd];
}
- (IBAction)playStopSound:(NSButton *)btn {
	if (btn.state == NSControlStateValueOn) {
		for (NSControl *ctrl in sndContrls) ctrl.enabled = YES;
		enter_test_mode(sndPInfo.stringValue, sndPMVal.floatValue, sndPVol.floatValue);
	} else {
		exit_test_mode();
		for (NSControl *ctrl in sndContrls) ctrl.enabled = NO;
	}
}
- (IBAction)assignPMMin:(NSTextField *)sender {
	NSTextField *dgt = [sender isKindOfClass:NSTextField.class]? sender : sndPMVal;
	CGFloat value = dgt.doubleValue, orgValue = sndPMValSld.minValue;
	if (value == orgValue) return;
	[undoMng4SndPnl registerUndoWithTarget:sndPMMin handler:^(NSTextField *tf) {
		tf.doubleValue = orgValue;
		[tf sendAction:tf.action to:tf.target];
	}];
	((NSNumberFormatter *)sndPMMax.formatter).minimum = 
	((NSNumberFormatter *)sndPMVal.formatter).minimum = @(value);
	sndPMValSld.minValue = value;
	if (dgt == sndPMVal) sndPMMin.doubleValue = value;
	else if (sndPMVal.doubleValue < value)
		sndPMVal.doubleValue = sndPMValSld.doubleValue = value;
	[self checkRevertable];
}
- (IBAction)assignPMMax:(NSTextField *)sender {
	NSTextField *dgt = [sender isKindOfClass:NSTextField.class]? sender : sndPMVal;
	CGFloat value = dgt.doubleValue, orgValue = sndPMValSld.maxValue;
	if (value == orgValue) return;
	[undoMng4SndPnl registerUndoWithTarget:sndPMMax handler:^(NSTextField *tf) {
		tf.doubleValue = orgValue;
		[tf sendAction:tf.action to:tf.target];
	}];
	((NSNumberFormatter *)sndPMMin.formatter).maximum = 
	((NSNumberFormatter *)sndPMVal.formatter).maximum = @(value);
	sndPMValSld.maxValue = value;
	if (dgt == sndPMVal) sndPMMax.doubleValue = value;
	else if (sndPMVal.doubleValue > value)
		sndPMVal.doubleValue = sndPMValSld.doubleValue = value;
	[self checkRevertable];
}
- (void)changeSldDgtValue:(NSControl *)sender sld:(NSSlider *)sld dgt:(NSTextField *)dgt {
	NSControl *pc = (sender == sld)? dgt : sld;
	CGFloat value = sender.doubleValue, orgValue = pc.doubleValue;
	if (value == orgValue) return;
	[undoMng4SndPnl registerUndoWithTarget:sender handler:^(NSControl *ctl) {
		ctl.doubleValue = orgValue;
		[ctl sendAction:ctl.action to:ctl.target];
	}];
	pc.doubleValue = value;
}
- (IBAction)changePMValue:(NSControl *)sender {
	[self changeSldDgtValue:sender sld:sndPMValSld dgt:sndPMVal];
	set_test_mode_pm(sender.floatValue);
}
- (IBAction)changePVolume:(NSControl *)sender {
	[self changeSldDgtValue:sender sld:sndPVolSld dgt:sndPVol];
	[self checkRevertable];
	set_test_mode_vol(sender.floatValue);
}
// Delegate method for NSOpenPanel to disable MIDI files.
- (BOOL)panel:(id)sender shouldEnableURL:(NSURL *)url {
	return ![@[@"mid", @"midi"] containsObject:url.pathExtension];
}
- (IBAction)listenSound:(NSButton *)btn {
	SoundType type = (SoundType)btn.tag;
	if (soundNowPlaying != nil) {
		[soundNowPlaying stop];
		if (playingSoundType == type) { soundNowPlaying = nil; return; }
	}
	playingSoundType = type;
	soundNowPlaying = [NSSound.alloc initWithContentsOfFile:sndData[type].v.path byReference:YES];
	soundNowPlaying.delegate = self;
	[soundNowPlaying play];
}
- (void)sound:(NSSound *)sound didFinishPlaying:(BOOL)flag {
	playBtns[playingSoundType].state = NSControlStateValueOff;
	soundNowPlaying = nil;
}
static NSDictionary *param_diff_dict(SoundPrm *a, SoundPrm *b) {
	NSMutableDictionary *md = NSMutableDictionary.new;
	if (![a->path isEqualToString:b->path]) md[@"path"] = b->path;
	if (a->mmin != b->mmin) md[@"mmin"] = @(b->mmin);
	if (a->mmax != b->mmax) md[@"mmax"] = @(b->mmax);
	if (a->vol != b->vol) md[@"vol"] = @(b->vol);
	return md;
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
	for (SoundType type = 0; type < NVoices; type ++) {
		SoundSrc *s = &sndData[type];
		if (!prm_equal(&s->v, &s->fd)) md[s->key] = param_diff_dict(&s->v, &s->fd);
	}
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
	for (SoundType type = 0; type < NVoices; type ++) {
		SoundSrc *s = &sndData[type];
		NSDictionary *dc = dict[s->key];
		if (dc == nil) continue;
		SoundPrm prm = s->v;
		if ((newValue = dc[@"path"]) != nil) prm.path = newValue;
		if ((num = dc[@"mmin"]) != nil) prm.mmin = num.floatValue;
		if ((num = dc[@"mmax"]) != nil) prm.mmax = num.floatValue;
		if ((num = dc[@"vol"]) != nil) prm.vol = num.floatValue;
		if (prm_equal(&s->v, &prm)) continue;
		orgValues[s->key] = param_diff_dict(&prm, &s->v);
		if (prm_equal(&prm, &s->fd) || prm_equal(&s->v, &s->fd))
			fdFlipBits |= 1 << s->FDBit;
		if (![prm.path isEqualToString:s->v.path])
			change_sound_data(type, prm.path);
	}
	FDBits ^= fdFlipBits;
	[self adjustControls];
	[undoManager registerUndoWithTarget:self handler:^(id _Nonnull target) {
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
	} else [undoManager undo];
}
- (void)adjustDrawMethod:(NSDictionary *)info { // called when buffer allocation failed.
	NSNumber *num = info[keyOldValue];
	if (num != nil) {
		ptclDrawMethod = (PTCLDrawMethod)num.intValue;
		for (NSButton *btn in dmBtns) btn.state = (ptclDrawMethod == btn.tag);
		[self checkFDBits:FDBTDm cond:ptclDrawMethod == ptclDrawMethodFD];
	} else [undoManager undo];
}
//
- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window {
	return (window == self.window)? undoManager : undoMng4SndPnl;
}
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	SEL action = menuItem.action;
	if (action == @selector(exportSettings:)
	 || action == @selector(revertToFactoryDefault:)) return btnExport.enabled;
	return YES;
}
@end
