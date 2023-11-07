//
//  MainWindow.m
//  LearningIsLife
//
//  Created by Tatsuo Unemi on 2023/01/07.
//

#import "MainWindow.h"
#import "AppDelegate.h"
#import "Agent.h"
#import "Display.h"
#import "RecordView.h"
#import "MyViewForCG.h"
#import "MySound.h"
#import "CommPanel.h"

ObstaclesMode obstaclesMode = ObsFixed, newObsMode = ObsFixed;
float ManObsLifeSpan = 1.f;
NSString *scrForFullScr = @"Main window's screen", *infoViewConf = @"In the world view";
static NSString *labelFullScreenOn = @"Full Screen", *labelFullScreenOff = @"Full Screen Off";
MainWindow *theMainWindow = nil;

static NSColor *middle_color(NSColor *col1, NSColor *col2) {
	CGFloat r1, r2, g1, g2, b1, b2, a1, a2;
	NSColorSpace *colspc = NSColorSpace.genericRGBColorSpace;
	[[col1 colorUsingColorSpace:colspc] getRed:&r1 green:&g1 blue:&b1 alpha:&a1];
	[[col2 colorUsingColorSpace:colspc] getRed:&r2 green:&g2 blue:&b2 alpha:&a2];
	return [NSColor colorWithSRGBRed:(r1 + r2) / 2. green:(g1 + g2) / 2.
		blue:(b1 + b2) / 2. alpha:(a1 + a2) / 2.];
}
@implementation MyInfoView {
	NSColor *bgColor;
}
- (void)drawRect:(NSRect)dirtyRect {
	if (self.inFullScreenMode) {
		if (bgColor == nil) bgColor = middle_color(colBackground, colInfoFG);
		[bgColor setFill];
		[NSBezierPath fillRect:dirtyRect];
	} else if (bgColor != nil) bgColor = nil;
	[super drawRect:dirtyRect];
}
@end

@implementation MyProgressBar
- (void)setupAsDefault {
	_background = colBackground;
	_foreground = colInfoFG;
	_dimmed = middle_color(_background, _foreground);
	in_main_thread(^{ self.needsDisplay = YES; });
}
- (void)drawRect:(NSRect)dirtyRect {
	[super drawRect:dirtyRect];
	NSRect rect = self.bounds;
	if (_maxValue > 0.) {
		if (_doubleValue < _maxValue) rect.size.width *= _doubleValue / _maxValue;
		[_foreground setFill];
		[NSBezierPath fillRect:rect];
		rect.origin.x += rect.size.width;
		rect.size.width = self.bounds.size.width - rect.size.width;
		if (rect.size.width > 0.) {
			[_background setFill];
			[NSBezierPath fillRect:rect];
		}
	} else {
		[_dimmed setFill];
		[NSBezierPath fillRect:rect];
	}
}
@end

@implementation PrintPanelAccessory
- (NSString *)nibName { return @"PrintPanelAccessory"; }
- (NSArray<NSDictionary<NSPrintPanelAccessorySummaryKey,NSString *> *> *)localizedSummaryItems {
	return @[@{NSPrintPanelAccessorySummaryItemNameKey:@"figInPaper",
		NSPrintPanelAccessorySummaryItemDescriptionKey:_figInPaper? @"Yes" : @"No"}];
}
- (NSSet<NSString *> *)keyPathsForValuesAffectingPreview {
	return [NSSet setWithObject:@"figInPaper"];
}
- (IBAction)switchBlackAndWhite:(NSButton *)cbox {
	self.figInPaper = (cbox.state == NSControlStateValueOn);
}
@end

@interface ViewGeom : NSObject
@property (readonly) NSView *view;
@property (readonly) NSValue *geom;
@property (readonly) NSFont *font;
@end
@implementation ViewGeom
- (instancetype)initWithView:(NSView *)v {
	if (!(self = [super init])) return nil;
	_view = v;
	_geom = [NSValue valueWithRect:v.frame];
	if ([v isKindOfClass:NSControl.class]) _font = ((NSControl *)v).font;
	return self;
}
+ (ViewGeom *)geom:(NSView *)v { return [ViewGeom.alloc initWithView:v]; }
- (void)apply {
	_view.frame = _geom.rectValue;
	if (_font != nil) ((NSControl *)_view).font = _font;
}
@end

@implementation MainWindow {
	Agent *agent;
	Display *display;
	NSUInteger steps, goalCount;
	float sendingPPS;
	IBOutlet NSToolbarItem *startStopItem, *fullScreenItem;
	IBOutlet NSPopUpButton *dispModePopUp;
	IBOutlet MTKView *view;
	IBOutlet RecordView *recordView;
	IBOutlet MyInfoView *infoView;
	IBOutlet MyProgressBar *stepsPrg, *goalsPrg;
	IBOutlet NSTextField *stepsDgt, *goalsDgt, *stepsUnit, *goalsUnit, *fpsDgt;
	NSArray<NSTextField *> *infoTexts;
	NSArray<ViewGeom *> *infoViewGeom;
	CGFloat stepsPerSec, expectedGoals, expectedSteps;
	NSTimer *pointerTrackTimer, *cursorHidingTimer;
	NSMenuItem *dispAdjustItem;
	BOOL winScrChanged, flipSG;
}
- (NSString *)windowNibName { return @"MainWindow"; }
- (BOOL)recShownInMain {
	return RECORD_IMAGES && !infoView.inFullScreenMode;
}
static inline CGFloat field_aspect_ratio(void) {
	return (CGFloat)nGridW * tileSize.x / (nGridH * tileSize.y);
}
- (CGFloat)drawnAreaAspaectRatio {
	CGFloat far = field_aspect_ratio();
	return (![self recShownInMain])? far : far + 5. / 18.;
}
- (void)adjustViewFrame:(NSNotification *)note {	// called when contentview size changed
	NSSize cSize = view.superview.frame.size;
	CGFloat cAspect = cSize.width / cSize.height,
		iAspect = [self drawnAreaAspaectRatio];
#ifdef DEBUG
NSLog(@"adjustViewFrame %@ %.1fx%.1f c=%.3f, i=%.3f, %@", note.object,
	cSize.width, cSize.height, cAspect, iAspect, note.name);
#endif
	NSRect vFrame = (cAspect == iAspect)? (NSRect){0., 0., cSize} :
		(cAspect > iAspect)?
			(NSRect){(cSize.width - cSize.height * iAspect) / 2., 0.,
				cSize.height * iAspect, cSize.height} :
			(NSRect){0., (cSize.height - cSize.width / iAspect) / 2.,
				cSize.width, cSize.width / iAspect};
	if ([self recShownInMain]) {
		NSRect rFrame = vFrame;
		vFrame.size.width = vFrame.size.height * field_aspect_ratio();
		rFrame.size.width -= vFrame.size.width;
		rFrame.origin.x += vFrame.size.width;
		[recordView setFrame:rFrame];
	}
	[view setFrame:vFrame];
}
- (void)adjustForRecordView:(NSNotification *)note {
	if (!view.superview.inFullScreenMode) {
		NSRect wFrame = view.window.frame;
		NSSize cSize = view.superview.frame.size;
		CGFloat deltaWidth = view.frame.size.height * [self drawnAreaAspaectRatio] - cSize.width;
		wFrame.origin.x -= deltaWidth / 2.;
		wFrame.size.width += deltaWidth;
		[view.window setFrame:wFrame display:YES];
#ifdef DEBUG
NSLog(@"adjustForRecordView %.1fx%.1f d=%.3f, %@",
	cSize.width, cSize.height, deltaWidth, note.name);
#endif
	} else [self adjustViewFrame:note];
	recordView.hidden = !RECORD_IMAGES;
}
- (void)adjustMaxStepsOrGoals:(NSInteger)tag {
	switch (tag) {
		case MAX_STEPS_TAG:
		stepsPrg.maxValue = MAX_STEPS;
		stepsPrg.needsDisplay = YES;
		break;
		case MAX_GOALCNT_TAG:
		goalsPrg.maxValue = MAX_GOALCNT;
		goalsPrg.needsDisplay = YES;
	}
}
static BOOL is_info_visible(void) {
	NSInteger nc = colInfoFG.numberOfComponents;
	if (nc == 2 || nc == 4) {
		CGFloat c[4];
		[colInfoFG getComponents:c];
		return (c[nc - 1] > 0.);
	} else return YES;
}
static void organize_work_mems(void) {
	ObsHeight = realloc(ObsHeight, sizeof(float) * nGrids);
	FieldP = realloc(FieldP, sizeof(simd_int2) * nActiveGrids);
	memset(ObsHeight, 0, sizeof(float) * nGrids);
	for (int i = 0; i < nObstacles; i ++)
		ObsHeight[ij_to_idx(ObsP[i])] = 1;
	simd_int2 ixy; int k = 0;
	for (ixy.y = 0; ixy.y < nGridH; ixy.y ++)
	for (ixy.x = 0; ixy.x < nGridW; ixy.x ++)
		if (ObsHeight[ij_to_idx(ixy)] == 0 && k < nActiveGrids) FieldP[k ++] = ixy;
}
static int random_post(int x, int max) {
	if (x < max / 2) return random() % (x + 1);
	else if (x >= max) return max - 1;
	else return max - (random() % (max - x)) - 1;
}
-(void)setupObstacles {
	BOOL gridChanged = nGridW != newGridW || nGridH != newGridH,
		dimChanged = gridChanged || tileSize.y != newTileH,
		obsModeChanged = obstaclesMode != newObsMode;
	if (gridChanged) {
		nGridW = newGridW; nGridH = newGridH;
		[display clearObsPCache];
	}
	if (dimChanged) {
		tileSize.y = newTileH;
		[self adjustForRecordView:nil];
	}
	switch ((obstaclesMode = newObsMode)) {
		case ObsFixed: case ObsRandom:
		StartP = FixedStartP; GoalP = FixedGoalP;
		nObstacles = NObstaclesDF;
		ObsP = realloc(ObsP, sizeof(FixedObsP));
		memcpy(ObsP, FixedObsP, sizeof(FixedObsP));
		if (obstaclesMode == ObsRandom) {
			ObsP[0] = (simd_int2){(drand48() < .5)? 1 : 2, (drand48() < .5)? 1 : 2};
			ObsP[3] = (simd_int2){(drand48() < .5)? 4 : 5, (drand48() < .5)? 1 : 2};
			ObsP[1].x = ObsP[2].x = ObsP[0].x;
			ObsP[2].y = (ObsP[1].y = ObsP[0].y + 1) + 1;
		}
		organize_work_mems();
		break;
		case ObsPointer:
		if (theTracker == nil) theTracker = Tracker.new;
		case ObsExternal:
		StartP = simd_min((simd_int2){newStartX, newStartY}, (simd_int2){nGridW, nGridH} - 1);
		GoalP = simd_min((simd_int2){newGoalX, newGoalY}, (simd_int2){nGridW, nGridH} - 1);
		if (ALTERNATE_SG) {
			if (flipSG) { int x = StartP.x; StartP.x = GoalP.x; GoalP.x = x; }
			if (random() & 1) {
				StartP.y = nGridH - 1 - StartP.y; 
				GoalP.y = nGridH - 1 - GoalP.y; 
			}
			StartP.x = random_post(StartP.x, nGridW);
			StartP.y = random_post(StartP.y, nGridH);
			GoalP.x = random_post(GoalP.x, nGridW);
			GoalP.y = random_post(GoalP.y, nGridH);
			flipSG = !flipSG;
		}
		nObstacles = 0;
		ObsP = realloc(ObsP, sizeof(simd_int2) * nGrids);
		organize_work_mems();
	}
	if (obsModeChanged) [NSNotificationCenter.defaultCenter
		postNotificationName:@"obsModeChangedByReset" object:NSApp];
}
- (void)windowDidLoad {
	[super windowDidLoad];
	theMainWindow = self;
	expectedGoals = MAX_GOALCNT / 2.;
	expectedSteps = MAX_STEPS / 2.;
	_agentEnvLock = NSLock.new;
	_agentEnvLock.name = @"Agent Environment";
	agent = Agent.new;
	display = [Display.alloc initWithView:(MTKView *)view agent:agent];
	infoTexts = @[stepsDgt, stepsUnit, goalsDgt, goalsUnit, fpsDgt];
	for (NSTextField *txt in infoTexts) txt.textColor = colInfoFG;
	[recordView loadImages];
	[self adjustMaxStepsOrGoals:MAX_STEPS_TAG];
	[self adjustMaxStepsOrGoals:MAX_GOALCNT_TAG];
	[stepsPrg setupAsDefault];
	[goalsPrg setupAsDefault];
	fpsDgt.hidden = !SHOW_FPS;
	infoView.hidden = !is_info_visible();
	NSMenu *cMenu = view.menu;
	for (NSInteger i = cMenu.numberOfItems - 1; i >= 0; i --) {
		NSMenuItem *item = [cMenu itemAtIndex:i];
		if (item.action == @selector(switchDispAdjust:))
			{ [cMenu removeItem:item]; dispAdjustItem = item; break; }
	}
//	fullScreenItem.possibleLabels = @[labelFullScreenOn, labelFullScreenOn];
	[NSNotificationCenter.defaultCenter addObserver:self
		selector:@selector(adjustForRecordView:) name:@"recordFinalImage" object:nil];
	[NSNotificationCenter.defaultCenter addObserver:self
		selector:@selector(adjustViewFrame:)
		name:NSViewFrameDidChangeNotification object:view.superview];
	add_observer(@"maxSteps", ^(NSNotification * _Nonnull note) {
		[self adjustMaxStepsOrGoals:MAX_STEPS_TAG]; });
	add_observer(@"maxGoalCount", ^(NSNotification * _Nonnull note) {
		[self adjustMaxStepsOrGoals:MAX_GOALCNT_TAG]; });
	add_observer(@"colorBackground", ^(NSNotification * _Nonnull note) {
		self->view.needsDisplay = YES;
		[self->stepsPrg setupAsDefault]; [self->goalsPrg setupAsDefault]; });
	add_observer(@"colorSymbols", ^(NSNotification * _Nonnull note) {
		self->view.needsDisplay = YES;
	});
	add_observer(@"colorInfoFG", ^(NSNotification * _Nonnull note) {
		self->view.needsDisplay = YES;
		for (NSTextField *txt in self->infoTexts) txt.textColor = colInfoFG;
		[self->stepsPrg setupAsDefault]; [self->goalsPrg setupAsDefault];
		self->infoView.hidden = !is_info_visible();
	});
	add_observer(@"showFPS", ^(NSNotification * _Nonnull note) {
		self->fpsDgt.hidden = !SHOW_FPS; });
	add_observer(@"sounds", ^(NSNotification * _Nonnull note) {
		if (self.simState == SimRun) {
			if (SOUNDS_ON) start_audio_out();
			else stop_audio_out();
		}});
	add_observer(keySoundTestExited, ^(NSNotification * _Nonnull note) {
		if (SOUNDS_ON && self.simState == SimRun) start_audio_out(); });
	add_observer(keyObsMode, ^(NSNotification * _Nonnull note) {
		if (self->steps > 0) return;
		[self setupObstacles];
		[self->display reset]; });
	[NSNotificationCenter.defaultCenter addObserverForName:NSMenuDidEndTrackingNotification
		object:view.superview.menu queue:nil usingBlock:^(NSNotification * _Nonnull note) {
		if (self->view.superview.inFullScreenMode) self->cursorHidingTimer =
			[NSTimer scheduledTimerWithTimeInterval:.5 repeats:NO block:
				^(NSTimer * _Nonnull timer) { [NSCursor setHiddenUntilMouseMoves:YES];}];
	}];
	[view.window makeFirstResponder:self];
	[self reset:nil];
}
- (simd_int2)agentPosition { return agent.position; }
- (NSString *)infoText {
	return [NSString stringWithFormat:@"%@ steps, %ld goal%@",
		[NSNumberFormatter localizedStringFromNumber:@(steps)
			numberStyle:NSNumberFormatterDecimalStyle],
		goalCount, (goalCount == 1)? @"" : @"s"];
}
static void show_count(MyProgressBar *prg, NSTextField *dgt, NSTextField *unit, NSInteger cnt) {
	prg.doubleValue = (prg.maxValue >= cnt)? cnt : 0;
	dgt.integerValue = cnt;
	NSString *unitStr = unit.stringValue;
	if (cnt == 1) {
		if ([unitStr hasSuffix:@"s"])
			unit.stringValue = [unitStr substringToIndex:unitStr.length - 1];
	} else if (![unitStr hasSuffix:@"s"])
		unit.stringValue = [unitStr stringByAppendingString:@"s"];
	prg.needsDisplay = YES;
}
- (void)showSteps { show_count(stepsPrg, stepsDgt, stepsUnit, steps); }
- (void)showGoals { show_count(goalsPrg, goalsDgt, goalsUnit, goalCount); }
- (void)recordImageIfNeeded {
	if (RECORD_IMAGES && steps > 0)
		[recordView addImage:display infoText:self.infoText];
}
static float mag_to_scl(float mag, SoundPrm *p) {
	return powf(2.f, mag * (p->mmax - p->mmin) + p->mmin);
}
static void play_agent_sound(Agent *agent, SoundType sndType, float age) {
	SoundPrm *p = &sndData[sndType].v;
	SoundQue sndQue = { sndType, 1., 0., p->vol, 0 };
	simd_float2 aPos = simd_float(agent.position);
	sndQue.pan = aPos.x / (nGridW - 1) * 1.8 - .9;
	sndQue.pitchShift = mag_to_scl((aPos.y / (nGridH - 1) * .2 + 1. - age) / 1.2, p);
	set_audio_events(&sndQue);
}
static void play_sound_effect(SoundType sndType, float pitchShift) {
	set_audio_events(&(SoundQue){ sndType, pitchShift, 0., sndData[sndType].v.vol, 0 });
}
static void feed_env_noise_params(void) {
	SoundEnvParam sep[nGridW];
	int gCnt[nGridW];
	memset(sep, 0, sizeof(sep));
	memset(gCnt, 0, sizeof(gCnt));
	NSInteger n = nGridsInUse;
	for (NSInteger i = 0; i < n; i ++) {
		simd_int2 pos = FieldP[i];
		simd_float4 Q = QTable[ij_to_idx(pos)];
		for (NSInteger k = 0; k < NActs; k ++) sep[pos.x].amp += Q[k];
		sep[pos.x].pitchShift += hypotf(Q.x - Q.z, Q.y - Q.w);
		gCnt[pos.x] ++;
	}
	SoundPrm *p = &sndData[SndAmbience].v;
	for (NSInteger i = 0; i < nGridW; i ++) {
		sep[i].amp = ((sep[i].amp / gCnt[i] - 2.f) * .45f + .6f) * p->vol;
		sep[i].pitchShift = mag_to_scl(sep[i].pitchShift / gCnt[i], p);
	}
	set_audio_env_params(sep);
}
- (void)loopThreadForAgent {
	while (_simState == SimRun) {
		NSUInteger tm = current_time_us();
		[_agentEnvLock lock];
		AgentStepResult result = [agent oneStep];
		[_agentEnvLock unlock];
		switch (result) {
			case AgentStepped: break;
			case AgentBumped:
			play_agent_sound(agent, SndBump, (float)steps / MAX_STEPS); break;
			case AgentReached:
			goalCount ++;
			in_main_thread(^{ [self showGoals]; });
			SoundPrm *p = &sndData[SndGoal].v;
			play_sound_effect(SndGoal, (MAX_GOALCNT == 0)? 1. :
				mag_to_scl((float)goalCount / MAX_GOALCNT, p));
		}
		if (communication_is_running()) {
			[theTracker sendAgentInfo:result];
			if (sendingPPS > 0.) {
				NSInteger spp = StepsPerSec / sendingPPS;
				if (spp <= 1 || steps % spp == 0) [theTracker sendVectorFieldInfo];
			}
		}
		steps ++;
		unsigned long elapsed_us = current_time_us() - tm;
		NSInteger timeRemain = (StepsPerSec > 0.)? 1e6 / StepsPerSec - elapsed_us : 0;
		if (timeRemain > 0) {
			elapsed_us = 1e6 / StepsPerSec;
			usleep((useconds_t)timeRemain);
		}
		stepsPerSec += (1e6 / elapsed_us - stepsPerSec) * fmax(.05, 1. / steps);
		in_main_thread(^{ [self showSteps]; });
		if ((MAX_STEPS > 0 && steps >= MAX_STEPS)
		 || (MAX_GOALCNT > 0 && goalCount >= MAX_GOALCNT)) {
			_simState = SimDecay;
			in_main_thread(^{
				[self recordImageIfNeeded];
				[self->display startFading:^{
					[self reset:nil];
					[self startStop:nil];
				}];
			});
			if (goalCount >= MAX_GOALCNT) play_sound_effect(SndGood,
				mag_to_scl((float)(MAX_STEPS - steps) /
					(MAX_STEPS - expectedSteps / 2.), &sndData[SndGood].v));
			else play_sound_effect(SndBad,
				mag_to_scl((goalCount - expectedGoals / 2.) /
					(MAX_GOALCNT - expectedGoals / 2.), &sndData[SndBad].v));
			expectedSteps += (steps - expectedSteps) * .1;
			expectedGoals += (goalCount - expectedGoals) * .1;
#ifdef DEBUG
NSLog(@"expected:steps=%.1f,goals=%.1f", expectedSteps, expectedGoals);
#endif
	}}
}
- (void)loopThreadForDisplay {
	while (_simState != SimStop) {
		NSUInteger tm = current_time_us();
		switch (obstaclesMode) {
			case ObsExternal: if (!communication_is_running()) break;
			case ObsPointer: [theTracker stepTracking];
			default: break;
		}
		[display oneStep];
		feed_env_noise_params();
		unsigned long elapsed_us = current_time_us() - tm;
		NSInteger timeRemain = (DISP_INTERVAL - (1./52. - 1 / 60.)) * 1e6 - elapsed_us;
		if (timeRemain > 0) usleep((useconds_t)timeRemain);
		in_main_thread(^{ if (SHOW_FPS) self->fpsDgt.stringValue =
			[NSString stringWithFormat:@"%5.2f sps, %5.2f fps",
				self->stepsPerSec, self->display.FPS];
		});
	}
}
- (IBAction)reset:(id)sender {
	[self setupObstacles];
	[agent reset];
	[agent restart];
	[display reset];
	steps = goalCount = 0;
	[self showSteps];
	[self showGoals];
}
- (void)pointerTracker:(NSTimer *)timer {
	NSPoint pt = [view convertPoint:
		[view.window convertPointFromScreen:NSEvent.mouseLocation]
		fromView:nil];
	NSRect bounds = view.bounds;
	if (NSPointInRect(pt, bounds)) [theTracker addTrackedPoint:
		(simd_float2){pt.x / bounds.size.width, pt.y / bounds.size.height} index:0];
}
- (IBAction)startStop:(id)sender {
	switch (_simState) {
		case SimStop: _simState = SimRun;
		[NSThread detachNewThreadSelector:@selector(loopThreadForDisplay)
			toTarget:self withObject:nil];
		[NSThread detachNewThreadSelector:@selector(loopThreadForAgent)
			toTarget:self withObject:nil];
		startStopItem.image = [NSImage imageNamed:NSImageNameTouchBarPauseTemplate];
		startStopItem.label = @"Stop";
		if (SOUNDS_ON) start_audio_out();
		if (obstaclesMode == ObsPointer) pointerTrackTimer =
			[NSTimer scheduledTimerWithTimeInterval:1./30. target:self
				selector:@selector(pointerTracker:) userInfo:nil repeats:YES];
		break;
		case SimDecay: _simState = SimRun;
		[NSThread detachNewThreadSelector:@selector(loopThreadForAgent)
			toTarget:self withObject:nil];
		break;
		case SimRun: _simState = SimStop;
		startStopItem.image = [NSImage imageNamed:NSImageNameTouchBarPlayTemplate];
		startStopItem.label = @"Start";
		if (SOUNDS_ON) stop_audio_out();
		if (obstaclesMode == ObsPointer)
			{ [pointerTrackTimer invalidate]; pointerTrackTimer = nil; }
		break;
	}
}
static void adjust_subviews_frame(NSView *view, CGFloat scale) {
	for (NSView *v in view.subviews) {
		NSRect f = v.frame;
		v.frame = (NSRect){f.origin.x * scale, f.origin.y * scale,
			f.size.width * scale, f.size.height * scale};
		if ([v isKindOfClass:NSControl.class]) {
			NSFont *orgFont = ((NSControl *)v).font;
			((NSControl *)v).font = [NSFont fontWithName:
				orgFont.fontName size:orgFont.pointSize * scale];
		}
	}
}
static void shift_subviews(NSView *view, NSSize offset) {
	for (NSView *v in view.subviews) {
		NSPoint pt = v.frame.origin;
		[v setFrameOrigin:(NSPoint){pt.x + offset.width, pt.y + offset.height}];
	}
}
static CGFloat scale_for_rescale(NSSize orgVSz, NSSize newVSz) {
	return (orgVSz.width / orgVSz.height <= newVSz.width / newVSz.height)?
		newVSz.height / orgVSz.height : newVSz.width / orgVSz.width;
}
- (IBAction)fullScreen:(id)sender {
	NSView *cView = view.superview;
	if (!cView.inFullScreenMode) {
		NSScreen *screen = self.window.screen, *infoVScr = screen;
		if (scrForFullScr != nil) for (NSScreen *scr in NSScreen.screens)
			if ([scrForFullScr isEqualToString:scr.localizedName])
				{ screen = infoVScr = scr; break; }
		if (infoViewConf != nil) for (NSScreen *scr in NSScreen.screens)
			if ([infoViewConf isEqualToString:scr.localizedName])
				{ infoVScr = scr; break; }
		if (infoViewGeom == nil) {
			NSInteger n = infoView.subviews.count + 1, idx = 0;
			ViewGeom *vgs[n];
			vgs[idx ++] = [ViewGeom geom:infoView];
			for (NSView *v in infoView.subviews) vgs[idx ++] = [ViewGeom geom:v];
			infoViewGeom = [NSArray arrayWithObjects:vgs count:n];
		}
		NSDictionary *option = @{NSFullScreenModeAllScreens:@NO};
		NSRect infoViewFrame = infoView.frame;
		if (screen == infoVScr) {
			NSSize orgVSz = view.frame.size;
			[cView enterFullScreenMode:screen withOptions:option];
			CGFloat scale = scale_for_rescale(orgVSz, view.frame.size);
			[infoView setFrame:(NSRect){
				infoViewFrame.origin.x * scale, infoViewFrame.origin.y * scale,
				infoViewFrame.size.width * scale, infoViewFrame.size.height * scale
			}];
			[display setInfoView:infoView];
			adjust_subviews_frame(infoView, scale);
		} else {
			[infoView enterFullScreenMode:infoVScr withOptions:option];
			adjust_subviews_frame(infoView,
				scale_for_rescale(infoViewFrame.size, infoVScr.frame.size) * .9);
			NSSize vSz = infoView.bounds.size;
			shift_subviews(infoView, (NSSize){ vSz.width * .05, vSz.width * .05 });
			[cView enterFullScreenMode:screen withOptions:option];
		}
		fullScreenItem.label = labelFullScreenOff;
		fullScreenItem.image = [NSImage imageNamed:NSImageNameExitFullScreenTemplate];
		[view.menu addItem:dispAdjustItem];
		if (NSPointInRect(NSEvent.mouseLocation, screen.frame) && !display.dispAdjust)
			[NSCursor setHiddenUntilMouseMoves:YES];
	} else {
		[display setInfoView:nil];
		[cView exitFullScreenModeWithOptions:nil];
		if (infoView.inFullScreenMode) [infoView exitFullScreenModeWithOptions:nil];
		for (ViewGeom *vg in infoViewGeom) [vg apply];
		infoView.hidden = !is_info_visible();
		fullScreenItem.label = labelFullScreenOn;
		fullScreenItem.image = [NSImage imageNamed:NSImageNameEnterFullScreenTemplate];
		[view.menu removeItem:dispAdjustItem];
		[self showSteps];
		[NSCursor setHiddenUntilMouseMoves:NO];
	}
}
- (IBAction)printScene:(id)sender {
	NSPrintInfo *prInfo = NSPrintInfo.sharedPrintInfo;
	NSRect pb = prInfo.imageablePageBounds;
	NSSize pSize = prInfo.paperSize;
	prInfo.topMargin = pSize.height - NSMaxY(pb);
	prInfo.bottomMargin = pb.origin.y;
	prInfo.leftMargin = pb.origin.x;
	prInfo.rightMargin = pSize.width - NSMaxX(pb);
	MyViewForCG *view = [MyViewForCG.alloc initWithFrame:pb
		display:display infoView:infoView recordView:recordView];
	NSPrintOperation *prOpe = [NSPrintOperation printOperationWithView:view printInfo:prInfo];
	[prOpe.printPanel addAccessoryController:PrintPanelAccessory.new];
	[prOpe runOperation];
}
- (IBAction)copy:(id)sender {
	NSRect frame = {0., 0., PTCLMaxX, PTCLMaxY};
	MyViewForCG *view = [MyViewForCG.alloc initWithFrame:frame
		display:display infoView:infoView recordView:recordView];
	NSData *data = [view dataWithPDFInsideRect:frame];
	NSPasteboard *pb = NSPasteboard.generalPasteboard;
	[pb declareTypes:@[NSPasteboardTypePDF] owner:NSApp];
	[pb setData:data forType:NSPasteboardTypePDF];
}
- (IBAction)chooseDisplayMode:(id)sender {
	NSInteger newMode;
	if (sender == dispModePopUp) {
		newMode = dispModePopUp.indexOfSelectedItem;
	} else if ([sender isKindOfClass:NSMenuItem.class]) {
		newMode = ((NSMenuItem *)sender).tag;
		[dispModePopUp selectItemAtIndex:newMode];
	} else return;
	display.displayMode = (DisplayMode)newMode;
}
- (IBAction)switchDispAdjust:(id)sender {
	if ((display.dispAdjust = !display.dispAdjust)) {
		if (cursorHidingTimer != nil && cursorHidingTimer.valid)
			[cursorHidingTimer invalidate];
		[NSCursor setHiddenUntilMouseMoves:NO];
	} else {
		[NSCursor.arrowCursor set];
		if (NSPointInRect(NSEvent.mouseLocation, self.window.screen.frame))
			[NSCursor setHiddenUntilMouseMoves:YES];
	}
#ifdef DEBUG
NSLog(@"switchDispAdjust %@", display.dispAdjust? @"ON" : @"OFF");
#endif
	view.window.acceptsMouseMovedEvents = display.dispAdjust;
	view.needsDisplay = YES;
}
- (void)setSendersPacketsPerSec:(float)pps {
	sendingPPS = pps;
}
- (BOOL)keyOperation:(NSEvent *)event {
	if (display.dispAdjust) {
		NSEventModifierFlags flags = event.modifierFlags;
		BOOL shift = (flags & NSEventModifierFlagShift) != 0;
#ifdef DEBUG
NSLog(@"code = %d, shift = %@", event.keyCode, shift? @"YES" : @"NO");
#endif
		switch (event.keyCode) {
			case KeyCodeE: case KeyCodeESC: [self switchDispAdjust:nil]; break;
			case KeyCodeR: [display resetAdjustMatrix]; view.needsDisplay = YES; break;
			case KeyCodeS: if ([display saveAdjustmentCorners]) break; else return YES;
			case KeyCodeUp: [display scaleAdjustMatrix:shift? 5 : 1]; break;
			case KeyCodeDown: [display scaleAdjustMatrix:shift? -5 : -1]; break;
			default: return YES;
		}
	} else if (event.keyCode == KeyCodeESC) [self fullScreen:nil];
	else return YES;
	return NO;
}
- (void)mouseOperation:(NSEvent *)event {
	if (display.dispAdjust) {
		NSPoint msLoc = event.locationInWindow;
		NSPoint pnt1 =[view convertPoint:
			(NSPoint){msLoc.x - event.deltaX, msLoc.y - event.deltaY} fromView:nil],
			pnt2 = [view convertPoint:msLoc fromView:nil];
		NSRect rct = view.bounds;
		simd_float2 pt1 = {pnt1.x, pnt1.y}, pt2 = {pnt2.x, pnt2.y},
			org = {rct.origin.x, rct.origin.y}, sz = {rct.size.width, rct.size.height};
		pt1 -= org; pt2 -= org;
		int orgCorner = [display cornerIndexAtPosition:pt1 size:sz],
			newCorner = [display cornerIndexAtPosition:pt2 size:sz];
		switch (event.type) {
			case NSEventTypeLeftMouseDown: case NSEventTypeRightMouseDown:
			case NSEventTypeOtherMouseDown:
			if (newCorner >= 0) [NSCursor.closedHandCursor set];
			break;
			case NSEventTypeLeftMouseUp: case NSEventTypeRightMouseUp:
			case NSEventTypeOtherMouseUp:
			if (newCorner >= 0) [NSCursor.openHandCursor set];
			else [NSCursor.arrowCursor set];
			break;
			case NSEventTypeMouseMoved:
			if (newCorner >= 0 && NSCursor.currentCursor == NSCursor.arrowCursor)
				[NSCursor.openHandCursor set];
			else if (newCorner < 0 && NSCursor.currentCursor != NSCursor.arrowCursor)
				[NSCursor.arrowCursor set];
			break;
			case NSEventTypeLeftMouseDragged:
			if (orgCorner >= 0) [display moveCorner:orgCorner to:pt2 size:sz];
			default: break;
		}
	} else switch (event.type) {
		case NSEventTypeLeftMouseUp: case NSEventTypeRightMouseUp:
		case NSEventTypeOtherMouseUp:
		cursorHidingTimer = [NSTimer scheduledTimerWithTimeInterval:.5 repeats:NO block:
			^(NSTimer * _Nonnull timer) { [NSCursor setHiddenUntilMouseMoves:YES];}];
		default: break;
	}
}
// Window Delegate
- (NSSize)windowWillResize:(NSWindow *)sender toSize:(NSSize)newSize {
	NSSize orgSz = sender.frame.size;
	if (view.superview.inFullScreenMode) return orgSz;
	if (winScrChanged) { winScrChanged = NO; return orgSz; }
	return newSize;
}
- (void)windowDidChangeScreen:(NSNotification *)notification {
	winScrChanged = YES;
}
- (void)windowWillClose:(NSNotification *)notification {
	if (notification.object == self.window) {
		if (RECORD_IMAGES) [recordView saveImages];
		else [recordView clearImages];
		[NSApp terminate:nil];
	}
}
// Menu item validation
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	SEL action = menuItem.action;
	if (action == @selector(startStop:)) {
		menuItem.title = (_simState == SimRun)? @"Stop" : @"Start";
		return _simState != SimDecay;
	} else if (action == @selector(fullScreen:))
		menuItem.title = view.superview.inFullScreenMode?
			labelFullScreenOff : labelFullScreenOn;
	else if (action == @selector(printScene:) && view.superview.inFullScreenMode)
		return view.window.screen != self.window.screen;
	else if (action == @selector(chooseDisplayMode:))
		menuItem.state = (display.displayMode == menuItem.tag);
	else if (action == @selector(switchDispAdjust:)) {
		menuItem.state = display.dispAdjust;
		return view.superview.isInFullScreenMode;
	}
	return YES;
}
@end

@interface MyContentView : NSView
@end
@implementation MyContentView
// pressing ESC key to exit from full screen mode. 
- (void)keyDown:(NSEvent *)event {
	if (!self.inFullScreenMode) [super keyDown:event];
	else if ([theMainWindow keyOperation:event]) [super keyDown:event];
}
- (void)mouseDown:(NSEvent *)event {
	if (self.inFullScreenMode) [theMainWindow mouseOperation:event];
	[super mouseDown:event];
}
- (void)mouseUp:(NSEvent *)event {
	if (self.inFullScreenMode) [theMainWindow mouseOperation:event];
	[super mouseUp:event];
}
- (void)mouseMoved:(NSEvent *)event {
	if (self.inFullScreenMode) [theMainWindow mouseOperation:event];
	[super mouseMoved:event];
}
- (void)mouseDragged:(NSEvent *)event {
	if (self.inFullScreenMode) [theMainWindow mouseOperation:event];
	[super mouseDragged:event];
}
- (void)drawRect:(NSRect)rect {
	[NSColor.blackColor setFill];
	[NSBezierPath fillRect:rect];
}
@end
