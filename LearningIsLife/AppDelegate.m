//
//  AppDelegate.m
//  LearningIsLife
//
//  Created by Tatsuo Unemi on 2022/12/24.
//
// Q-Learning by Look-up-table
// on simple maze.

#import "AppDelegate.h"
#import "ControlPanel.h"
#import "InteractionPanel.h"
#import "CommPanel.h"
#import "MainWindow.h"
#import "Display.h"
#import "Agent.h"
#import "MySound.h"

simd_int2 Move[4] = {{0,1},{1,0},{0,-1},{-1,0}}; // up, right, down, left
simd_int2 FixedObsP[NObstaclesDF] = {{2,2},{2,3},{2,4},{5,1},{7,3},{7,4},{7,5}};
simd_int2 FixedStartP = {0,3}, FixedGoalP = {8,5};
simd_int2 *ObsP = NULL, *FieldP = NULL, StartP, GoalP, tileSize = {TileSizeWDF, TileSizeHDF};
float *ObsHeight = NULL;
int nGridW = NGridWDF, nGridH = NGridHDF, nObstacles = NObstaclesDF;
int newGridW = NGridWDF, newGridH = NGridHDF, newTileH = TileSizeHDF,
	newStartX = 0, newStartY = 3, newGoalX = 8, newGoalY = 5;

NSString *keyCntlPnl = @"controlPanel";
NSString *keyOldValue = @"oldValue", *keyShouldRedraw = @"shouldRedraw",
	*keyShouldReviseVertices = @"shouldReviseVertices", *keySoundTestExited = @"soundTextExited";
NSString *keyColorMode = @"ptclColorMode", *keyShapeMode = @"ptclShapeMode",
	*keyObsMode = @"obstaclesMode";
NSString *scrForFullScrFD, *scrForFullScrUD, *keyScrForFullScr = @"screenForFullScreenMode";
NSString *infoViewConfFD, *infoViewConfUD, *keyInfoViewConf = @"infoViewConf";
PTCLColorMode ptclColorModeFD, ptclColorModeUD;
PTCLShapeMode ptclShapeModeFD, ptclShapeModeUD;
ObstaclesMode obsModeFD, obsModeUD;

IntVarInfo IntVars[] = {
	{ @"gridW", 0, &newGridW },
	{ @"gridH", 0, &newGridH },
	{ @"tileH", 0, &newTileH },
	{ @"startX", 0, &newStartX },
	{ @"startY", 0, &newStartY },
	{ @"goalX", 0, &newGoalX },
	{ @"goalY", 0, &newGoalY },
	{ @"memSize", 0, &MemSize },
	{ @"memTrials", 0, &MemTrials },
	{ @"nParticles", ShouldPostNotification, &NParticles },
	{ @"ptclLifeSpan", ShouldPostNotification, &LifeSpan },
	{ nil }
};
FloatVarInfo FloatVars[] = {
	{ @"T0", 0, &T0 },
	{ @"T1", 0, &T1 },
	{ @"cooling", 0, &CoolingRate },
	{ @"initQValue", 0, &InitQValue },
	{ @"gamma", 0, &Gamma },
	{ @"alpha", 0, &Alpha },
	{ @"stepsPerSec", 0, &StepsPerSec },
	{ @"ptclMass", 0, &Mass },
	{ @"ptclFriction", 0, &Friction },
	{ @"ptclLength", ShouldReviseVertices, &StrokeLength },
	{ @"ptclWeight", ShouldReviseVertices, &StrokeWidth },
	{ @"ptclMaxSpeed", 0, &MaxSpeed },
	{ @"manipulatedObstacleLifeSpan", 0, &ManObsLifeSpan },
	{ @"fadeoutTimeInSecond", 0, &FadeoutSec },
	{ nil }
};
ColVarInfo ColVars[] = {
	{ @"colorBackground", ShouldPostNotification, &colBackground },
	{ @"colorObstacles", 0, &colObstacles },
	{ @"colorAgent",0,  &colAgent },
	{ @"colorGridLines", 0, &colGridLines },
	{ @"colorSymbols", ShouldPostNotification, &colSymbols },
	{ @"colorParticles", ShouldPostNotification, &colParticles },
	{ @"colorTracking", 0, &colTracking },
	{ @"colorInfoFG", ShouldPostNotification, &colInfoFG },
	{ nil }
};
UIntegerVarInfo UIntegerVars[] = {
	{ @"maxSteps", ShouldPostNotification, 8000 },
	{ @"maxGoalCount", ShouldPostNotification, 60 },
	{ nil }
};
BoolVarInfo BoolVars[] = {
	{ @"drawHand", ShouldRedrawScreen, YES },
	{ @"sounds", ShouldPostNotification, YES  },
	{ @"startWithFullScreenMode", 0, NO },
	{ @"recordFinalImage", ShouldPostNotification, NO },
	{ @"showFPS", ShouldPostNotification, YES },
	{ @"saveAsUserDefaultsWhenTerminate", 0, YES },
	{ nil }
};

#define DEF_FOR_ALL_PROC(name,type,table) \
void name(void (^block)(type *p)) {\
	for (NSInteger i = 0; table[i].key != nil; i ++) block(&table[i]);\
}
DEF_FOR_ALL_PROC(for_all_int_vars, IntVarInfo, IntVars)
DEF_FOR_ALL_PROC(for_all_float_vars, FloatVarInfo, FloatVars)
DEF_FOR_ALL_PROC(for_all_uint_vars, UIntegerVarInfo, UIntegerVars)
DEF_FOR_ALL_PROC(for_all_bool_vars, BoolVarInfo, BoolVars)
DEF_FOR_ALL_PROC(for_all_color_vars, ColVarInfo, ColVars)

SoundSrc sndData[NVoices] = {
	{ @"soundBump", { @"/System/Library/Sounds/Frog.aiff", -1., 1., 1.} },
	{ @"soundGoal", { @"/System/Library/Sounds/Submarine.aiff", -.5, .5, 1.} },
	{ @"soundGood", { @"/Applications/iMovie.app/Contents/Resources/iLife Sound Effects/"
		@"Stingers/Ethereal Accents.caf", -.5, .5, 1.} },
	{ @"soundBad", { @"/Applications/iMovie.app/Contents/Resources/iLife Sound Effects/"
		@"Stingers/Electric Flutters 02.caf", 0., 1., 1.} },
	{ @"soundAmbience", { @"/Applications/iMovie.app/Contents/Resources/iMovie Sound Effects/"
		@"Cave and Wind.mp3", -1., 6., 1.} }
};
NSUInteger col_to_ulong(NSColor *col) {
	CGFloat c[4] = {0., 0., 0., 1.};
	[[col colorUsingColorSpace:NSColorSpace.genericRGBColorSpace]
		getComponents:c];
	return (((NSUInteger)(c[0] * 255)) << 24) |
		(((NSUInteger)(c[1] * 255)) << 16) |
		(((NSUInteger)(c[2] * 255)) << 8) |
		(NSUInteger)(c[3] * 255);
}
NSColor *ulong_to_col(NSUInteger rgba) {
	CGFloat c[4] = {
		(rgba >> 24) / 255.,
		((rgba >> 16) & 255) / 255.,
		((rgba >> 8) & 255) / 255.,
		(rgba & 255) / 255.};
	return [NSColor colorWithColorSpace:
		NSColorSpace.genericRGBColorSpace components:c count:4];
}
NSUInteger hex_string_to_ulong(NSString *str) {
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
	if (controlPanel == nil)
		controlPanel = [ControlPanel.alloc initWithWindow:nil];
	[controlPanel showWindow:sender];
	controlPanel.nextResponder = mainWindow;
}
- (IBAction)openCommPanel:(id)sender {
	static CommPanel *comPanel = nil;
	if (comPanel == nil) comPanel = [CommPanel.alloc initWithWindow:nil];
	[comPanel showWindow:nil];
}
#define SET_DFLT_VAL(forAll,type,star,val)	forAll(^(type *p) {\
		p->fd = star p->v;\
		NSNumber *nm = [ud objectForKey:p->key];\
		if (nm != nil) star p->v = nm.val;\
		p->ud = star p->v; });
- (void)applicationWillFinishLaunching:(NSNotification *)aNotification {
	init_default_colors();
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	SET_DFLT_VAL(for_all_int_vars, IntVarInfo, *, intValue)
	SET_DFLT_VAL(for_all_float_vars, FloatVarInfo, *, floatValue)
	SET_DFLT_VAL(for_all_uint_vars, UIntegerVarInfo, , integerValue)
	SET_DFLT_VAL(for_all_bool_vars, BoolVarInfo, , boolValue)
	for_all_color_vars(^(ColVarInfo *p) {
		p->fd = *p->v;
		NSString *str = [ud stringForKey:p->key];
		if (str != nil) *p->v = ulong_to_col(hex_string_to_ulong(str));
		p->ud = *p->v;
	});
	ptclColorModeFD = ptclColorMode;
	ptclShapeModeFD = ptclShapeMode;
	obsModeFD = obstaclesMode;
	scrForFullScrFD = scrForFullScr;
	infoViewConfFD = infoViewConf;
	NSNumber *nm;
	if ((nm = [ud objectForKey:keyColorMode]) != nil) ptclColorMode = nm.intValue;
	if ((nm = [ud objectForKey:keyShapeMode]) != nil) ptclShapeMode = nm.intValue;
	if ((nm = [ud objectForKey:keyObsMode]) != nil) newObsMode = nm.intValue;
	NSString *str;
	if ((str = [ud objectForKey:keyScrForFullScr]) != nil) scrForFullScr = str;
	if ((str = [ud objectForKey:keyInfoViewConf]) != nil) infoViewConf = str;
	ptclColorModeUD = ptclColorMode;
	ptclShapeModeUD = ptclShapeMode;
	obsModeUD = newObsMode;
	scrForFullScrUD = scrForFullScr;
	infoViewConfUD = infoViewConf;
	[InteractionPanel initParams];
	NSFileManager *fm = NSFileManager.defaultManager;
	NSMutableDictionary<NSString *, NSString *> *missingSnd = NSMutableDictionary.new;
	for (SoundType type = 0; type < NVoices; type ++) {
		SoundSrc *s = &sndData[type];
		s->fd = s->v;
		NSObject *obj = [ud objectForKey:s->key];
		if ([obj isKindOfClass:NSString.class]) s->v.path = (NSString *)obj;
		else if ([obj isKindOfClass:NSDictionary.class])
			set_param_from_dict(&s->v, (NSDictionary *)obj);
		s->loaded = @"";
		if (s->v.path.length > 0 && ![fm fileExistsAtPath:s->v.path]) {
			missingSnd[s->key] = s->v.path;
			s->v.path = @"";
		}
		s->ud = s->v;
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
	[mainWindow adjustForRecordView:nil];
	if (START_WIDTH_FULL_SCR) {
		[NSTimer scheduledTimerWithTimeInterval:.1 repeats:NO
			block:^(NSTimer * _Nonnull timer) {
			[self->mainWindow fullScreen:nil];
			[NSTimer scheduledTimerWithTimeInterval:.5 repeats:NO
				block:^(NSTimer * _Nonnull timer) {
				[self->mainWindow startStop:nil]; }];
		}];
	} 
	init_audio_out();
	check_initial_communication();
}
#define SAVE_DFLT(forAll,type,star,setter)	forAll(^(type *p) {\
	if (star p->v == p->fd) [ud removeObjectForKey:p->key];\
	else [ud setter: star p->v forKey:p->key]; });
#define SAVE_STR_DFLT(key,var,fdVar)	if ([var isEqualToString:fdVar])\
		[ud removeObjectForKey:key];\
	else [ud setObject:var forKey:key];
void save_as_user_defaults(void) {
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	SAVE_DFLT(for_all_int_vars, IntVarInfo, *, setInteger)
	SAVE_DFLT(for_all_float_vars, FloatVarInfo, *, setFloat)
	SAVE_DFLT(for_all_uint_vars, UIntegerVarInfo, , setInteger)
	SAVE_DFLT(for_all_bool_vars, BoolVarInfo, , setBool)
	for_all_color_vars(^(ColVarInfo *p) {
		NSUInteger cu = col_to_ulong(*p->v);
		if (cu == col_to_ulong(p->fd)) [ud removeObjectForKey:p->key];
		else [ud setObject:[NSString stringWithFormat:@"%08lX", cu] forKey:p->key];
	});
	if (ptclColorMode == ptclColorModeFD) [ud removeObjectForKey:keyColorMode];
		else [ud setInteger:ptclColorMode forKey:keyColorMode];
	if (ptclShapeMode == ptclShapeModeFD) [ud removeObjectForKey:keyShapeMode];
		else [ud setInteger:ptclShapeMode forKey:keyShapeMode];
	if (newObsMode == obsModeFD) [ud removeObjectForKey:keyObsMode];
		else [ud setInteger:newObsMode forKey:keyObsMode];
	SAVE_STR_DFLT(keyScrForFullScr, scrForFullScr, scrForFullScrFD)
	SAVE_STR_DFLT(keyInfoViewConf, infoViewConf, infoViewConfFD)
	for (SoundType type = 0; type < NVoices; type ++) {
		SoundSrc *s = &sndData[type];
		if (prm_equal(&s->v, &s->fd)) [ud removeObjectForKey:s->key];
		else [ud setObject:@{@"path":s->v.path, @"mmin":@(s->v.mmin),
				@"mmax":@(s->v.mmax), @"vol":@(s->v.vol)} forKey:s->key];
	}
}
#define COMP_DFLT(forAll,type,cmp)	forAll(^(type *p) { if (cmp) @throw @YES; });
static BOOL was_params_edited(void) {
	@try {
		COMP_DFLT(for_all_int_vars, IntVarInfo, *p->v != p->ud)
		COMP_DFLT(for_all_float_vars, FloatVarInfo, *p->v != p->ud)
		COMP_DFLT(for_all_uint_vars, UIntegerVarInfo, p->v != p->ud)
		COMP_DFLT(for_all_bool_vars, BoolVarInfo, p->v != p->ud)
		COMP_DFLT(for_all_color_vars, ColVarInfo, col_to_ulong(*p->v) != col_to_ulong(p->ud))
		if (ptclColorMode != ptclColorModeUD) @throw @YES;
		if (ptclShapeMode != ptclShapeModeUD) @throw @YES;
		if (newObsMode != obsModeUD) @throw @YES;
		if (![scrForFullScr isEqualToString:scrForFullScrUD]) @throw @YES;
		if (![infoViewConf isEqualToString:infoViewConfUD]) @throw @YES;
		for (SoundType type = 0; type < NVoices; type ++)
			if (!prm_equal(&sndData[type].v, &sndData[type].ud)) @throw @YES;
	} @catch (id _) { return YES; }
	return NO;
}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender{
	if (was_params_edited()) {
		NSAlert *alt = NSAlert.new;
		alt.alertStyle = NSAlertStyleWarning;
		alt.messageText = @"Shall we save the current settings as default?";
		alt.informativeText = @"It'll start with the same settings in next time,"
			@" if you press OK button.";
		for (NSString *title in @[@"OK", @"Don’t Save", @"Cancel"])
			[alt addButtonWithTitle:title];
		switch ([alt runModal]) {
			case NSAlertFirstButtonReturn: save_as_user_defaults();	// OK
			case NSAlertSecondButtonReturn: return NSTerminateNow;	// Don't Save
			default: return NSTerminateCancel;	// Cancel
		}
	} else return NSTerminateNow;	// Has nothing to save
}
@end
