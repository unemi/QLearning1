//
//  MainWindow.m
//  QLearning1
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

NSString *scrForFullScr = @"Screen the main window placed";
static NSString *labelFullScreenOn = @"Full Screen", *labelFullScreenOff = @"Full Screen Off";
@interface MyProgressBar : NSView
@property CGFloat maxValue, doubleValue;
@end
@implementation MyProgressBar
- (void)drawRect:(NSRect)dirtyRect {
	[super drawRect:dirtyRect];
	NSRect rect = self.bounds;
	if (_maxValue > 0.) {
		if (_doubleValue < _maxValue) rect.size.width *= _doubleValue / _maxValue;
		[colSymbols setFill];
		[NSBezierPath fillRect:rect];
		rect.origin.x += rect.size.width;
		rect.size.width = self.bounds.size.width - rect.size.width;
		if (rect.size.width > 0.) {
			[colBackground setFill];
			[NSBezierPath fillRect:rect];
		}
	} else {
		CGFloat r1, r2, g1, g2, b1, b2, a1, a2;
		[colBackground getRed:&r1 green:&g1 blue:&b1 alpha:&a1];
		[colSymbols getRed:&r2 green:&g2 blue:&b2 alpha:&a2];
		[[NSColor colorWithSRGBRed:(r1 + r2) / 2. green:(g1 + g2) / 2.
			blue:(b1 + b2) / 2. alpha:(a1 + a2) / 2.] setFill];
		[NSBezierPath fillRect:rect];
	}
}
@end

static void setup_obstacle_info(void) {
	memset(Obstacles, 0, sizeof(Obstacles));
	for (int i = 0; i < NObstacles; i ++)
		Obstacles[ObsP[i][1]][ObsP[i][0]] = 1;
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
	CGFloat interval;
	BOOL running;
	NSUInteger steps, goalCount;
	NSRect infoViewFrame;
	IBOutlet NSToolbarItem *startStopItem, *fullScreenItem;
	IBOutlet NSPopUpButton *dispModePopUp;
	IBOutlet MTKView *view;
	IBOutlet RecordView *recordView;
	IBOutlet MyProgressBar *stepsPrg, *goalsPrg;
	IBOutlet NSTextField *stepsDgt, *goalsDgt, *stepsUnit, *goalsUnit,
		*fpsDgt, *fpsUnit;
	NSArray<NSTextField *> *infoTexts;
	CGFloat FPS;
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
- (void)windowDidLoad {
	[super windowDidLoad];
	setup_obstacle_info();
	interval = 1. / 60.;
	agent = Agent.new;
	display = [Display.alloc initWithView:(MTKView *)view agent:agent];
	infoTexts = @[stepsDgt, stepsUnit, goalsDgt, goalsUnit, fpsDgt, fpsUnit];
	for (NSTextField *txt in infoTexts) txt.textColor = colSymbols;
	fpsDgt.doubleValue = 0.;
	[recordView loadImages];
	[self adjustMaxStepsOrGoals:MAX_STEPS_TAG];
	[self adjustMaxStepsOrGoals:MAX_GOALCNT_TAG];
//	fullScreenItem.possibleLabels = @[labelFullScreenOn, labelFullScreenOn];
	[NSNotificationCenter.defaultCenter addObserver:self
		selector:@selector(adjustForRecordView:) name:@"recordFinalImage" object:nil];
	[NSNotificationCenter.defaultCenter addObserver:self
		selector:@selector(adjustViewFrame:)
		name:NSViewFrameDidChangeNotification object:view.superview];
	[NSNotificationCenter.defaultCenter addObserverForName:@"maxSteps"
		object:NSApp queue:nil usingBlock:^(NSNotification * _Nonnull note) {
		[self adjustMaxStepsOrGoals:MAX_STEPS_TAG];
	}];
	[NSNotificationCenter.defaultCenter addObserverForName:@"maxGoalCount"
		object:NSApp queue:nil usingBlock:^(NSNotification * _Nonnull note) {
		[self adjustMaxStepsOrGoals:MAX_GOALCNT_TAG];
	}];
	[NSNotificationCenter.defaultCenter addObserverForName:@"colorSymbols"
		object:NSApp queue:nil usingBlock:^(NSNotification * _Nonnull note) {
		for (NSTextField *txt in self->infoTexts) txt.textColor = colSymbols;
	}];
	[NSNotificationCenter.defaultCenter addObserverForName:@"showFPS"
		object:NSApp queue:nil usingBlock:^(NSNotification * _Nonnull note) {
		self->fpsDgt.hidden = self->fpsUnit.hidden = !SHOW_FPS;
	}];
	[NSNotificationCenter.defaultCenter addObserverForName:keySoundTestExited
		object:NSApp queue:nil usingBlock:^(NSNotification * _Nonnull note) {
		if (self->running) start_audio_out();
	}];
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
static float mag_to_scl(float mag, SoundPrm *p) {
	return powf(2.f, mag * (p->mmax - p->mmin) + p->mmin);
}
static void play_agent_sound(Agent *agent, SoundType sndType) {
	int ix, iy;
	SoundPrm *p = &sndData[sndType].v;
	SoundQue sndQue = { sndType, 1., 0., p->vol, 0 };
	[agent getPositionX:&ix Y:&iy];
	sndQue.pan = (float)ix / (NGridW - 1) * 1.8 - .9;
	sndQue.pitchShift = mag_to_scl((float)iy / (NGridH - 1), p);
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
		int *pos = FieldP[i], ix = pos[0], iy = pos[1];
		vector_float4 Q = QTable[iy][ix];
		for (NSInteger k = 0; k < NActs; k ++) sep[ix].amp += Q[k];
		sep[ix].pitchShift += hypotf(Q.x - Q.z, Q.y - Q.w);
		gCnt[ix] ++;
	}
	SoundPrm *p = &sndData[SndEnvNoise].v;
	for (NSInteger i = 0; i < NGridW; i ++) {
		sep[i].amp = ((sep[i].amp / gCnt[i] - 2.f) * .45f + .6f) * p->vol;
		sep[i].pitchShift = mag_to_scl(sep[i].pitchShift / gCnt[i], p);
	}
	set_audio_env_params(sep);
}
- (void)loopThread {
	while (running) {
		NSUInteger tm = current_time_us();
		switch ([agent oneStep]) {
			case AgentStepped: break;
			case AgentBumped: play_agent_sound(agent, SndBump); break;
			case AgentReached:
			goalCount ++;
			in_main_thread(^{ [self showGoals]; });
			SoundPrm *p = &sndData[SndGoal].v;
			play_sound_effect(SndGoal, (MAX_GOALCNT == 0)? 1. :
				mag_to_scl((float)goalCount / MAX_GOALCNT, p));
		}
		steps ++;
		[display oneStep];
		feed_env_noise_params();
		unsigned long elapsed_us = current_time_us() - tm;
		NSInteger timeRemain = (interval - (1./52. - 1 / 60.)) * 1e6 - elapsed_us;
		if (timeRemain > 0) {
			elapsed_us = interval * 1e6;
			usleep((useconds_t)timeRemain);
		}
		FPS += (1e6 / elapsed_us - FPS) * .02;
		in_main_thread(^{
			[self showSteps];
			self->fpsDgt.doubleValue = self->FPS;
		});
		if ((MAX_STEPS > 0 && steps >= MAX_STEPS)
		 || (MAX_GOALCNT > 0 && goalCount >= MAX_GOALCNT)) {
			running = NO;
			in_main_thread(^{
				[self reset:nil];
				[self startStop:nil];
			});
			if (goalCount >= MAX_GOALCNT)
				play_sound_effect(SndGood, 1.);
			else play_sound_effect(SndBad, 1.);
	}}
}
- (IBAction)reset:(id)sender {
	if (RECORD_IMAGES && steps > 0)
		[recordView addImage:display infoText:self.infoText];
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
		[NSThread detachNewThreadSelector:@selector(loopThread)
			toTarget:self withObject:nil];
		startStopItem.image = [NSImage imageNamed:NSImageNameTouchBarPauseTemplate];
		startStopItem.label = @"Stop";
		start_audio_out();
	} else {
		startStopItem.image = [NSImage imageNamed:NSImageNameTouchBarPlayTemplate];
		startStopItem.label = @"Start";
		stop_audio_out();
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
