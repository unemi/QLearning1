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
#import "CommPanel.h"
#import "MainWindow.h"
#import "Display.h"
#import "Agent.h"
#import "MySound.h"

simd_int2 Move[4] = {{0,1},{1,0},{0,-1},{-1,0}}; // up, right, down, left
simd_int2 ObsP[NObstacles] = {{2,2},{2,3},{2,4},{5,1},{7,3},{7,4},{7,5}};
simd_int2 StartP = {0,3}, GoalP = {8,5};
simd_int2 FieldP[NGrids];
int nActiveGrids = NActiveGrids;
int Obstacles[NGridH][NGridW];
NSString *keyCntlPnl = @"controlPanel";
NSString *keyOldValue = @"oldValue", *keyShouldRedraw = @"shouldRedraw",
	*keyShouldReviseVertices = @"shouldReviseVertices", *keySoundTestExited = @"soundTextExited";
NSString *keyColorMode = @"ptclColorMode", *keyShapeMode = @"ptclShapeMode",
	*keyObsMode = @"obstaclesMode";
NSString *scrForFullScrFD, *keyScrForFullScr = @"screenForFullScreenMode";
PTCLColorMode ptclColorModeFD;
PTCLShapeMode ptclShapeModeFD;
ObstaclesMode obsModeFD;

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
	{ @"stepsPerSec", &StepsPerSec, 0, 0 },
	{ @"ptclMass", &Mass, 0, 0 },
	{ @"ptclFriction", &Friction, 0, 0 },
	{ @"ptclLength", &StrokeLength, 0, ShouldReviseVertices },
	{ @"ptclWeight", &StrokeWidth, 0, ShouldReviseVertices },
	{ @"ptclMaxSpeed", &MaxSpeed, 0, 0 },
	{ nil }
};
ColVarInfo ColVars[] = {
	{ @"colorBackground", &colBackground, nil, ShouldPostNotification },
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
	{ @"sounds", YES, YES, ShouldPostNotification },
	{ @"startWithFullScreenMode", NO },
	{ @"recordFinalImage", NO, NO, ShouldPostNotification },
	{ @"showFPS", YES, YES, ShouldPostNotification },
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
NSUInteger hex_string_to_uint(NSString *str) {
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
		if (nm != nil) star p->v = nm.val; });
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
		if (str == nil) return;
		NSUInteger rgba = hex_string_to_uint(str);
		*p->v = ulong_to_col(rgba);
	});
	ptclColorModeFD = ptclColorMode;
	ptclShapeModeFD = ptclShapeMode;
	obsModeFD = obstaclesMode;
	scrForFullScrFD = scrForFullScr;
	NSNumber *nm = [ud objectForKey:keyColorMode];
	if (nm != nil) ptclColorMode = nm.intValue;
	nm = [ud objectForKey:keyShapeMode];
	if (nm != nil) ptclShapeMode = nm.intValue;
	nm = [ud objectForKey:keyObsMode];
	if (nm != nil) obstaclesMode = nm.intValue;
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
	check_initial_communication();
}
#define SAVE_DFLT(forAll,type,star,setter)	forAll(^(type *p) {\
		[ud setter: star p->v forKey:p->key]; });
- (void)applicationWillTerminate:(NSNotification *)notification {
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	SAVE_DFLT(for_all_int_vars, IntVarInfo, *, setInteger)
	SAVE_DFLT(for_all_float_vars, FloatVarInfo, *, setFloat)
	SAVE_DFLT(for_all_uint_vars, UIntegerVarInfo, , setInteger)
	SAVE_DFLT(for_all_bool_vars, BoolVarInfo, , setBool)
	for_all_color_vars(^(ColVarInfo *p) {
		[ud setObject:[NSString stringWithFormat:@"%08lX", col_to_ulong(*p->v)] forKey:p->key];
	});
	[ud setInteger:ptclColorMode forKey:keyColorMode];
	[ud setInteger:ptclShapeMode forKey:keyShapeMode];
	[ud setInteger:obstaclesMode forKey:keyObsMode];
	[ud setObject:scrForFullScr forKey:keyScrForFullScr];
	for (SoundType type = 0; type < NVoices; type ++) {
		SoundSrc *s = &sndData[type];
		[ud setObject:@{@"path":s->v.path, @"mmin":@(s->v.mmin),
			@"mmax":@(s->v.mmax), @"vol":@(s->v.vol)} forKey:s->key];
	}
}
@end
