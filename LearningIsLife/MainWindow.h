//
//  MainWindow.h
//  LearningIsLife
//
//  Created by Tatsuo Unemi on 2023/01/07.
//

@import Cocoa;
#import "CommonTypes.h"
#import "Comm.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString *scrForFullScr;
@interface MainWindow : NSWindowController
	<NSWindowDelegate, NSMenuItemValidation, CommDelegate>
- (void)adjustForRecordView:(NSNotification * _Nullable)note;
- (IBAction)reset:(id _Nullable)sender;
- (IBAction)startStop:(id _Nullable)sender;
- (IBAction)fullScreen:(id _Nullable)sender;
- (IBAction)printScene:(id _Nullable)sender;
- (void)setSendersStepsPerPacket:(NSInteger)spp;
@end 

extern MainWindow *theMainWindow;
extern ObstaclesMode obstaclesMode;

@interface MyProgressBar : NSView
@property CGFloat maxValue, doubleValue;
@property NSColor *background, *foreground, *dimmed;
- (void)setupAsDefault;
@end

NS_ASSUME_NONNULL_END
