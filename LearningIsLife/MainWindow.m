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
NSString *scrForFullScr = @"Main window's screen";
static NSString *labelFullScreenOn = @"Full Screen", *labelFullScreenOff = @"Full Screen Off";
MainWindow *theMainWindow = nil;

@implementation MyProgressBar
- (void)setupAsDefault {
	_background = colBackground;
	_foreground = colSymbols;
	CGFloat r1, r2, g1, g2, b1, b2, a1, a2;
	NSColorSpace *colspc = NSColorSpace.genericRGBColorSpace;
	[[_background colorUsingColorSpace:colspc] getRed:&r1 green:&g1 blue:&b1 alpha:&a1];
	[[_foreground colorUsingColorSpace:colspc] getRed:&r2 green:&g2 blue:&b2 alpha:&a2];
	_dimmed = [NSColor colorWithSRGBRed:(r1 + r2) / 2. green:(g1 + g2) / 2.
		blue:(b1 + b2) / 2. alpha:(a1 + a2) / 2.];
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

typedef enum { TrackRight, TrackFront, TrackLeft, NTrackings } TrackingIndex;

@implementation MainWindow {
	Agent *agent;
	Display *display;
	CGFloat interval;
	BOOL running;
	NSUInteger steps, goalCount;
	float sendingPPS;
	NSRect infoViewFrame;
	IBOutlet NSToolbarItem *startStopItem, *fullScreenItem;
	IBOutlet NSPopUpButton *dispModePopUp;
	IBOutlet MTKView *view;
	IBOutlet RecordView *recordView;
	IBOutlet MyProgressBar *stepsPrg, *goalsPrg;
	IBOutlet NSTextField *stepsDgt, *goalsDgt, *stepsUnit, *goalsUnit,
		*fpsDgt, *fpsUnit;
	NSArray<NSTextField *> *infoTexts;
	CGFloat FPS, expectedGoals, expectedSteps;
	unsigned long *manObsTOB;	// time in micro second of birth
}
- (NSString *)windowNibName { return @"MainWindow"; }
static inline BOOL rec_enabled(void) {
	return RECORD_IMAGES && obstaclesMode != ObsExternal;
}
static inline CGFloat field_aspect_ratio(void) {
	return (CGFloat)nGridW * tileSize.x / (nGridH * tileSize.y);
}
static CGFloat drawn_area_aspaect_ratio(void) {
	CGFloat far = field_aspect_ratio();
	return (!rec_enabled())? far : far + 5. / 18.;
}
- (void)adjustViewFrame:(NSNotification *)note {	// called when contentview size changed
	NSSize cSize = view.superview.frame.size;
	CGFloat cAspect = cSize.width / cSize.height,
		iAspect = drawn_area_aspaect_ratio();
	NSRect vFrame = (cAspect == iAspect)? (NSRect){0., 0., cSize} :
		(cAspect > iAspect)?
			(NSRect){(cSize.width - cSize.height * iAspect) / 2., 0.,
				cSize.height * iAspect, cSize.height} :
			(NSRect){0., (cSize.height - cSize.width / iAspect) / 2.,
				cSize.width, cSize.width / iAspect};
	if (rec_enabled()) {
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
		CGFloat deltaWidth = view.frame.size.height * drawn_area_aspaect_ratio() - cSize.width;
		wFrame.origin.x -= deltaWidth / 2.;
		wFrame.size.width += deltaWidth;
		[view.window setFrame:wFrame display:YES];
	} else [self adjustViewFrame:note];
	recordView.hidden = !rec_enabled();
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
static BOOL is_symbol_color_visible(void) {
	NSInteger nc = colSymbols.numberOfComponents;
	if (nc == 2 || nc == 4) {
		CGFloat c[4];
		[colSymbols getComponents:c];
		return (c[nc - 1] > 0.);
	} else return YES;
}
static void organize_work_mems(void) {
	Obstacles = realloc(Obstacles, sizeof(int) * nGrids);
	FieldP = realloc(FieldP, sizeof(simd_int2) * nActiveGrids);
	memset(Obstacles, 0, sizeof(int) * nGrids);
	for (int i = 0; i < nObstacles; i ++)
		Obstacles[ij_to_idx(ObsP[i])] = 1;
	simd_int2 ixy; int k = 0;
	for (ixy.y = 0; ixy.y < nGridH; ixy.y ++)
	for (ixy.x = 0; ixy.x < nGridW; ixy.x ++)
		if (Obstacles[ij_to_idx(ixy)] == 0 && k < nActiveGrids) FieldP[k ++] = ixy;
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
		case ObsExternal:
		StartP = simd_min((simd_int2){newStartX, newStartY}, (simd_int2){nGridW, nGridH} - 1);
		GoalP = simd_min((simd_int2){newGoalX, newGoalY}, (simd_int2){nGridW, nGridH} - 1);
		nObstacles = 0;
		ObsP = realloc(ObsP, sizeof(simd_int2) * nGrids);
		organize_work_mems();
		manObsTOB = realloc(manObsTOB, sizeof(unsigned long) * nGrids);
	}
	if (obsModeChanged) [NSNotificationCenter.defaultCenter
		postNotificationName:@"obsModeChangedByReset" object:NSApp];
}
- (void)windowDidLoad {
	[super windowDidLoad];
	theMainWindow = self;
	interval = 1. / 60.;
	expectedGoals = MAX_GOALCNT / 2.;
	expectedSteps = MAX_STEPS / 2.;
	_agentEnvLock = NSLock.new;
	agent = Agent.new;
	display = [Display.alloc initWithView:(MTKView *)view agent:agent];
	infoTexts = @[stepsDgt, stepsUnit, goalsDgt, goalsUnit, fpsDgt, fpsUnit];
	for (NSTextField *txt in infoTexts) txt.textColor = colSymbols;
	[recordView loadImages];
	[self adjustMaxStepsOrGoals:MAX_STEPS_TAG];
	[self adjustMaxStepsOrGoals:MAX_GOALCNT_TAG];
	[stepsPrg setupAsDefault];
	[goalsPrg setupAsDefault];
	fpsDgt.hidden = fpsUnit.hidden = !SHOW_FPS;
	stepsDgt.superview.hidden = !is_symbol_color_visible();
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
		for (NSTextField *txt in self->infoTexts) txt.textColor = colSymbols;
		[self->stepsPrg setupAsDefault]; [self->goalsPrg setupAsDefault];
		self->stepsDgt.superview.hidden = !is_symbol_color_visible();
	});
	add_observer(@"showFPS", ^(NSNotification * _Nonnull note) {
		self->fpsDgt.hidden = self->fpsUnit.hidden = !SHOW_FPS; });
	add_observer(@"sounds", ^(NSNotification * _Nonnull note) {
		if (self->running) {
			if (SOUNDS_ON) start_audio_out();
			else stop_audio_out();
		}});
	add_observer(keySoundTestExited, ^(NSNotification * _Nonnull note) {
		if (SOUNDS_ON && self->running) start_audio_out(); });
	add_observer(keyObsMode, ^(NSNotification * _Nonnull note) {
		if (self->steps > 0) return;
		[self setupObstacles];
		[self->display reset]; });
	[NSNotificationCenter.defaultCenter addObserverForName:NSMenuDidEndTrackingNotification
		object:view.superview.menu queue:nil usingBlock:^(NSNotification * _Nonnull note) {
		if (self->view.superview.inFullScreenMode)
			[NSTimer scheduledTimerWithTimeInterval:.5 repeats:NO block:
				^(NSTimer * _Nonnull timer) { [NSCursor setHiddenUntilMouseMoves:YES];}];
	}];
	[view.window makeFirstResponder:self];
	[self reset:nil];
}
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
	for (NSInteger i = 0; i < nActiveGrids; i ++) {
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
- (void)stepTracking {
	[_agentEnvLock lock];
	unsigned long now = current_time_us(), lifeSpan = ManObsLifeSpan * 1e6;
	int k = 0;
	for (int i = 0; i < nObstacles; i ++)
		if (now - manObsTOB[i] < lifeSpan) {
			if (k < i) { ObsP[k] = ObsP[i]; manObsTOB[k] = manObsTOB[i]; }
			k ++;
		} else Obstacles[ij_to_idx(ObsP[i])] = 0;
	nObstacles = k;
	[_agentEnvLock unlock];
}
- (void)loopThreadForAgent {
	while (running) {
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
			[self sendAgentInfo];
			if (sendingPPS > 0.) {
				NSInteger spp = StepsPerSec / sendingPPS;
				if (spp <= 1 || steps % spp == 0) [self sendVectorFieldInfo];
			}
		}
		steps ++;
		unsigned long elapsed_us = current_time_us() - tm;
		NSInteger timeRemain = (StepsPerSec > 0.)? 1e6 / StepsPerSec - elapsed_us : 0;
		if (timeRemain > 0) {
			elapsed_us = 1e6 / StepsPerSec;
			usleep((useconds_t)timeRemain);
		}
		FPS += (1e6 / elapsed_us - FPS) * fmax(.05, 1. / steps);
		in_main_thread(^{ [self showSteps]; });
		if ((MAX_STEPS > 0 && steps >= MAX_STEPS)
		 || (MAX_GOALCNT > 0 && goalCount >= MAX_GOALCNT)) {
			running = NO;
			in_main_thread(^{
				[self recordImageIfNeeded];
				[self reset:nil];
				[self startStop:nil];
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
	while (running) {
		NSUInteger tm = current_time_us();
		if (obstaclesMode == ObsExternal && communication_is_running())
			[self stepTracking];
		[display oneStep];
		feed_env_noise_params();
		unsigned long elapsed_us = current_time_us() - tm;
		NSInteger timeRemain = (interval - (1./52. - 1 / 60.)) * 1e6 - elapsed_us;
		if (timeRemain > 0) {
			elapsed_us = interval * 1e6;
			usleep((useconds_t)timeRemain);
		}
		in_main_thread(^{ if (SHOW_FPS) self->fpsDgt.stringValue =
			[NSString stringWithFormat:@"%5.2f/%5.2f", self->FPS, self->display.FPS];
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
- (IBAction)startStop:(id)sender {
	if ((running = !running)) {
		[NSThread detachNewThreadSelector:@selector(loopThreadForDisplay)
			toTarget:self withObject:nil];
		[NSThread detachNewThreadSelector:@selector(loopThreadForAgent)
			toTarget:self withObject:nil];
		startStopItem.image = [NSImage imageNamed:NSImageNameTouchBarPauseTemplate];
		startStopItem.label = @"Stop";
		if (SOUNDS_ON) start_audio_out();
	} else {
		startStopItem.image = [NSImage imageNamed:NSImageNameTouchBarPlayTemplate];
		startStopItem.label = @"Start";
		if (SOUNDS_ON) stop_audio_out();
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
- (IBAction)fullScreen:(id)sender {
	NSView *cView = view.superview, *infoView = stepsDgt.superview;
	if (!cView.inFullScreenMode) {
		NSScreen *screen = self.window.screen;
		if (scrForFullScr != nil) for (NSScreen *scr in NSScreen.screens)
			if ([scrForFullScr isEqualToString:scr.localizedName])
				{ screen = scr; break; }
		infoViewFrame = infoView.frame;
		NSRect scrFrm = screen.frame;
		NSSize orgVSz = view.frame.size;
		[cView enterFullScreenMode:screen
			withOptions:@{NSFullScreenModeAllScreens:@NO}];
		NSSize newVSz = view.frame.size;
		CGFloat scale = (orgVSz.width / orgVSz.height <= newVSz.width / newVSz.height)?
			newVSz.height / orgVSz.height : newVSz.width / orgVSz.width;
		[infoView setFrame:(NSRect){
			infoViewFrame.origin.x * scale, infoViewFrame.origin.y * scale,
			infoViewFrame.size.width * scale, infoViewFrame.size.height * scale
		}];
		adjust_subviews_frame(infoView, scale);
		fullScreenItem.label = labelFullScreenOff;
		fullScreenItem.image = [NSImage imageNamed:NSImageNameExitFullScreenTemplate];
		if (NSPointInRect(NSEvent.mouseLocation, scrFrm))
			[NSCursor setHiddenUntilMouseMoves:YES];
	} else {
		CGFloat scale = infoViewFrame.size.width / infoView.frame.size.width;
		[cView exitFullScreenModeWithOptions:nil];
		[infoView setFrame:infoViewFrame];
		adjust_subviews_frame(infoView, scale);
		fullScreenItem.label = labelFullScreenOn;
		fullScreenItem.image = [NSImage imageNamed:NSImageNameEnterFullScreenTemplate];
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
		display:display infoView:stepsDgt.superview recordView:recordView];
	NSPrintOperation *prOpe = [NSPrintOperation printOperationWithView:view printInfo:prInfo];
	[prOpe runOperation];
}
- (IBAction)copy:(id)sender {
	NSRect frame = {0., 0., PTCLMaxX, PTCLMaxY};
	MyViewForCG *view = [MyViewForCG.alloc initWithFrame:frame
		display:display infoView:stepsDgt.superview recordView:recordView];
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
- (void)interpreteMessage:(char *)buf length:(ssize_t)length {
	if (memcmp(buf, "/point\0\0,iffi\0\0\0", 16) != 0) return;
	union { struct { SInt32 idx; Float32 x, y; SInt32 nPts; } d; SInt32 i[4]; } b;
	memcpy(b.i, buf + 16, 16);
	for (int i = 0; i < 4; i ++) b.i[i] = EndianS32_BtoN(b.i[i]);
	if (b.d.idx < 0 || b.d.idx >= NTrackings) return;
	simd_float2 pos = (simd_float2){b.d.x, b.d.y} * (simd_float2){nGridW, nGridH};
	simd_int2 ixy = simd_int(floor(pos));
	if (ixy.x < 0 || ixy.x >= nGridW || ixy.y < 0 || ixy.y >= nGridH
	 || simd_equal(ixy, GoalP) || simd_equal(ixy, StartP)) return;
	[_agentEnvLock lock];
	if (!simd_equal(ixy, agent.position)) {
		int idx = -1;
		for (int i = 0; i < nObstacles; i ++)
			if (simd_equal(ixy, ObsP[i])) { idx = i; break; }
		if (idx < 0) {
			ObsP[(idx = nObstacles ++)] = ixy;
			Obstacles[ij_to_idx(ixy)] = 1;
		}
		manObsTOB[idx] = current_time_us();
	}
	[_agentEnvLock unlock];
}
// Comm Delegate
- (void)receive:(char *)buf length:(ssize_t)length {
	if (memcmp(buf, "#bundle\0", 8) == 0) {
		UInt32 *p = (UInt32 *)(buf + 8);
//		struct { UInt32 sec, subsec; } tm = {p[0], p[1]};
		length -= 16;
		for (p += 2; length > p[0] && p[0] > 0; p += p[0] / 4 + 1) {
			[self receive:(char *)(p + 1) length:p[0]];
			length -= p[0] + 4;
		}
	} else [self interpreteMessage:buf length:length];
}
- (void)sendAgentInfo {
	static char addr[] = "/agent\0\0,ii";
	union { char c[64]; SInt32 i[16]; } b;
	memset(b.c, 0, sizeof(b.c));
	memcpy(b.c, addr, sizeof(addr));
	int idx = (sizeof(addr) + 3) / 4;
	simd_int2 p = agent.position;
	b.i[idx ++] = EndianS32_NtoB(p.x);
	b.i[idx ++] = EndianS32_NtoB(p.y);
	send_packet(b.c, idx * 4);
}
- (void)sendVectorFieldInfo {
	static char addr[] = "/cell\0\0\0,iiffff";
	union { char c[128]; SInt32 i[32]; } b;
	union { simd_float4 Q; SInt32 i[4]; } q;
	memset(b.c, 0, sizeof(b.c));
	memcpy(b.c, addr, sizeof(addr));
	simd_int2 ixy;
	for (ixy.y = 0; ixy.y < nGridH; ixy.y ++)
	for (ixy.x = 0; ixy.x < nGridW; ixy.x ++) {
		int idx = (sizeof(addr) + 3) / 4;
		b.i[idx ++] = EndianS32_NtoB(ixy.x);
		b.i[idx ++] = EndianS32_NtoB(ixy.y);
		q.Q = QTable[ij_to_idx(ixy)];
		for (int i = 0; i < 4; i ++)
			b.i[idx ++] = EndianS32_NtoB(q.i[i]);
		send_packet(b.c, idx * 4);
	}
}
- (void)setSendersPacketsPerSec:(float)pps {
	sendingPPS = pps;
}
// Window Delegate
- (NSSize)windowWillResize:(NSWindow *)sender toSize:(NSSize)frameSize {
	return view.superview.inFullScreenMode? sender.frame.size : frameSize;
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
	if (action == @selector(startStop:))
		menuItem.title = running? @"Stop" : @"Start";
	else if (action == @selector(fullScreen:))
		menuItem.title = view.superview.inFullScreenMode?
			labelFullScreenOff : labelFullScreenOn;
	else if (action == @selector(printScene:) && view.superview.inFullScreenMode)
		return view.window.screen != self.window.screen;
	else if (action == @selector(chooseDisplayMode:))
		menuItem.state = (display.displayMode == menuItem.tag);
	return YES;
}
@end

@interface MyContentView : NSView {
	IBOutlet MainWindow * __weak mainWindow;
}
@end
@implementation MyContentView
// pressing ESC key to exit from full screen mode. 
- (void)keyDown:(NSEvent *)event {
	if (event.keyCode == 53 && self.inFullScreenMode)
		[mainWindow fullScreen:nil];
	else [super keyDown:event];
}
- (void)mouseUp:(NSEvent *)event {
	if (self.inFullScreenMode)
		[NSTimer scheduledTimerWithTimeInterval:.5 repeats:NO block:
			^(NSTimer * _Nonnull timer) { [NSCursor setHiddenUntilMouseMoves:YES];}];
}
- (void)drawRect:(NSRect)rect {
	[NSColor.blackColor setFill];
	[NSBezierPath fillRect:rect];
}
@end
