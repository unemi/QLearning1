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

NSString *scrForFullScr = @"Screen the main window placed";
static NSString *labelFullScreenOn = @"Full Screen", *labelFullScreenOff = @"Full Screen Off";
@interface TextFieldForToolBarItem : NSTextField
@end
@implementation TextFieldForToolBarItem
- (void)setFont:(NSFont *)font {
	[super setFont:[NSFont fontWithName:@"Menlo Regular" size:font.pointSize]];
}
@end

@implementation MainWindow {
	Agent *agent;
	Display *display;
	CGFloat interval;
	BOOL running;
	NSUInteger steps, goalCount;
	IBOutlet NSToolbarItem *startStopItem, *fullScreenItem, *infoTextItem;
	IBOutlet NSPopUpButton *dispModePopUp;
	IBOutlet MTKView *view;
	IBOutlet RecordView *recordView;
	IBOutlet NSTextField *infoText;
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
- (void)windowDidLoad {
	[super windowDidLoad];
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
	display = [Display.alloc initWithView:(MTKView *)view agent:agent];
//	fullScreenItem.possibleLabels = @[labelFullScreenOn, labelFullScreenOn];
	[NSNotificationCenter.defaultCenter addObserver:self
		selector:@selector(adjustForRecordView:) name:@"recordFinalImage" object:nil];
	[NSNotificationCenter.defaultCenter addObserver:self
		selector:@selector(adjustViewFrame:)
		name:NSViewFrameDidChangeNotification object:view.superview];
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
- (void)showSteps {
	NSString *infoStr = self.infoText;
	if (!view.superview.inFullScreenMode ||
		self.window.screen != view.window.screen)
		((NSTextField *)infoTextItem.view).stringValue = infoStr;
	if (!infoText.hidden) infoText.stringValue = infoStr;
}
- (void)loopThread {
	while (running) {
		NSUInteger tm = current_time_us();
		if ([agent oneStep]) goalCount ++;
		steps ++;
		in_main_thread(^{ [self showSteps]; });
		[display oneStep];
		NSInteger timeRemain = (interval- (1./52. - 1 / 60.)) * 1e6
			- (current_time_us() - tm);
		if (timeRemain > 0) usleep((useconds_t)timeRemain);
		if ((MAX_STEPS > 0 && steps >= MAX_STEPS)
		 || (MAX_GOALCNT > 0 && goalCount >= MAX_GOALCNT)) {
			running = NO;
			in_main_thread(^{
				[self reset:nil];
				[self startStop:nil];
			});
	}}
}
- (IBAction)reset:(id)sender {
	if (RECORD_IMAGES && steps > 0)
		[recordView addImage:display infoText:self.infoText];
	[agent reset];
	[agent restart];
	[display reset];
	steps = goalCount = 0;
	in_main_thread(^{ [self showSteps]; });
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
	NSView *cView = view.superview;
	if (!cView.inFullScreenMode) {
		NSScreen *screen = self.window.screen;
		if (scrForFullScr != nil) for (NSScreen *scr in NSScreen.screens)
			if ([scrForFullScr isEqualToString:scr.localizedName])
				{ screen = scr; break; }
		[cView enterFullScreenMode:screen
			withOptions:@{NSFullScreenModeAllScreens:@NO}];
		fullScreenItem.label = labelFullScreenOff;
		fullScreenItem.image = [NSImage imageNamed:NSImageNameExitFullScreenTemplate];
		infoText.hidden = NO;
		infoText.textColor = colSymbols;
		infoText.font = [NSFont fontWithName:@"Menlo Regular" size:
			screen.frame.size.width / 1920. * 24.];
		infoText.stringValue = self.infoText;
		if (NSPointInRect(NSEvent.mouseLocation, screen.frame))
			[NSCursor setHiddenUntilMouseMoves:YES];
	} else {
		[cView exitFullScreenModeWithOptions:nil];
		fullScreenItem.label = labelFullScreenOn;
		fullScreenItem.image = [NSImage imageNamed:NSImageNameEnterFullScreenTemplate];
		infoText.hidden = YES;
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
	MyViewForCG *view = [MyViewForCG.alloc initWithFrame:pb display:display];
	NSPrintOperation *prOpe = [NSPrintOperation printOperationWithView:view printInfo:prInfo];
	[prOpe runOperation];
}
- (IBAction)copy:(id)sender {
	NSRect frame = {0., 0., NGridW * TileSize, NGridH * TileSize};
	MyViewForCG *view = [MyViewForCG.alloc initWithFrame:frame display:display];
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
	if (notification.object == self.window)
		[NSApp terminate:nil];
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
