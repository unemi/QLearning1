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

ObstaclesMode obstaclesMode = ObsFixed;
NSString *scrForFullScr = @"Screen the main window placed";
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

static void setup_obstacle_info(void) {
	memset(Obstacles, 0, sizeof(Obstacles));
	for (int i = 0; i < NObstacles; i ++)
		Obstacles[ObsP[i].y][ObsP[i].x] = 1;
	int k1 = 0, k2 = 0;
	for (int j = 0; j < NGridW; j ++)
	for (int i = 0; i < NGridH; i ++) {
		if (k1 < NObstacles && ObsP[k1][0] == j && ObsP[k1][1] == i) k1 ++;
		else { FieldP[k2][0] = j; FieldP[k2][1] = i; k2 ++; }
	}
}
@implementation MainWindow {
	Agent *agent;
	Display *display;
	NSLock *agentEnvLock;
	CGFloat interval;
	BOOL running;
	NSUInteger steps, goalCount;
	NSInteger sendingSPP;
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
}
- (NSString *)windowNibName { return @"MainWindow"; }
- (void)adjustViewFrame:(NSNotification *)note {
	NSSize cSize = view.superview.frame.size;
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
	[view setFrame:vFrame];
}
- (void)adjustForRecordView:(NSNotification *)note {
	if (!view.superview.inFullScreenMode) {
		NSRect wFrame = view.window.frame;
		NSSize cSize = view.superview.frame.size;
		CGFloat deltaWidth = view.frame.size.height *
			(RECORD_IMAGES? 16. / 9. : (CGFloat)NGridW / NGridH) - cSize.width;
		wFrame.origin.x -= deltaWidth / 2.;
		wFrame.size.width += deltaWidth;
		[view.window setFrame:wFrame display:YES];
	}
	[self adjustViewFrame:note];
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
static BOOL is_symbol_color_visible(void) {
	NSInteger nc = colSymbols.numberOfComponents;
	if (nc == 2 || nc == 4) {
		CGFloat c[4];
		[colSymbols getComponents:c];
		return (c[nc - 1] > 0.);
	} else return YES;
}
- (void)windowDidLoad {
	[super windowDidLoad];
	theMainWindow = self;
	setup_obstacle_info();
	interval = 1. / 60.;
	expectedGoals = MAX_GOALCNT / 2.;
	expectedSteps = MAX_STEPS / 2.;
	agentEnvLock = NSLock.new;
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
	if (RECORD_IMAGES && steps > 0 && view.frame.size.height > 700)
		[recordView addImage:display infoText:self.infoText];
}
static float mag_to_scl(float mag, SoundPrm *p) {
	return powf(2.f, mag * (p->mmax - p->mmin) + p->mmin);
}
static void play_agent_sound(Agent *agent, SoundType sndType, float age) {
	SoundPrm *p = &sndData[sndType].v;
	SoundQue sndQue = { sndType, 1., 0., p->vol, 0 };
	simd_float2 aPos = simd_float(agent.position);
	sndQue.pan = aPos.x / (NGridW - 1) * 1.8 - .9;
	sndQue.pitchShift = mag_to_scl((aPos.y / (NGridH - 1) * .2 + 1. - age) / 1.2, p);
	set_audio_events(&sndQue);
}
static void play_sound_effect(SoundType sndType, float pitchShift) {
	set_audio_events(&(SoundQue){ sndType, pitchShift, 0., sndData[sndType].v.vol, 0 });
}
static void feed_env_noise_params(void) {
	SoundEnvParam sep[NGridW];
	int gCnt[NGridW];
	memset(sep, 0, sizeof(sep));
	memset(gCnt, 0, sizeof(gCnt));
	for (NSInteger i = 0; i < NActiveGrids; i ++) {
		simd_int2 pos = FieldP[i];
		int ix = pos[0], iy = pos[1];
		vector_float4 Q = QTable[iy][ix];
		for (NSInteger k = 0; k < NActs; k ++) sep[ix].amp += Q[k];
		sep[ix].pitchShift += hypotf(Q.x - Q.z, Q.y - Q.w);
		gCnt[ix] ++;
	}
	SoundPrm *p = &sndData[SndAmbience].v;
	for (NSInteger i = 0; i < NGridW; i ++) {
		sep[i].amp = ((sep[i].amp / gCnt[i] - 2.f) * .45f + .6f) * p->vol;
		sep[i].pitchShift = mag_to_scl(sep[i].pitchShift / gCnt[i], p);
	}
	set_audio_env_params(sep);
}
- (void)loopThreadForAgent {
	while (running) {
		NSUInteger tm = current_time_us();
		[agentEnvLock lock];
		AgentStepResult result = [agent oneStep];
		[agentEnvLock unlock];
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
		if (sendingSPP > 0 && steps % sendingSPP == 0) [self sendPacket];
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
	if (obstaclesMode == ObsRandom) {
		ObsP[0] = (simd_int2){(drand48() < .5)? 1 : 2, (drand48() < .5)? 1 : 2};
		ObsP[3] = (simd_int2){(drand48() < .5)? 4 : 5, (drand48() < .5)? 1 : 2};
	} else {
		ObsP[0] = (simd_int2){2, 2};
		ObsP[3] = (simd_int2){5, 1};
	}
	ObsP[1][0] = ObsP[2][0] = ObsP[0][0];
	ObsP[2][1] = (ObsP[1][1] = ObsP[0][1] + 1) + 1;
	setup_obstacle_info();
	[agent reset];
	[agent restart];
	[display reset];
	steps = goalCount = 0;
	[self showSteps];
	[self showGoals];
	in_main_thread(^{ [self showSteps]; });
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
	NSRect frame = {0., 0., NGridW * TileSize, NGridH * TileSize};
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
// Comm Delegate
- (void)receive:(char *)buf length:(ssize_t)length {
}
- (void)sendPacket {
}
- (void)setSendersStepsPerPacket:(NSInteger)spp {
	sendingSPP = spp;
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
