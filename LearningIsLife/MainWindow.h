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
typedef enum { SimStop, SimRun, SimDecay } SimState;
@interface MainWindow : NSWindowController <NSWindowDelegate, NSMenuItemValidation>
@property (readonly) SimState simState;
@property (readonly) NSLock *agentEnvLock;
- (void)adjustForRecordView:(NSNotification * _Nullable)note;
- (simd_int2)agentPosition;
- (IBAction)reset:(id _Nullable)sender;
- (IBAction)startStop:(id _Nullable)sender;
- (IBAction)fullScreen:(id _Nullable)sender;
- (IBAction)printScene:(id _Nullable)sender;
- (void)setSendersPacketsPerSec:(float)pps;
@end 

extern NSString *scrForFullScr, *infoViewConf;
extern MainWindow *theMainWindow;
extern ObstaclesMode obstaclesMode, newObsMode;
extern float ManObsLifeSpan;

@interface MyInfoView : NSView
@end

@interface MyProgressBar : NSView
@property CGFloat maxValue, doubleValue;
@property NSColor *background, *foreground, *dimmed;
- (void)setupAsDefault;
@end

@interface PrintPanelAccessory : NSViewController <NSPrintPanelAccessorizing>
@property BOOL figInPaper;
@end

NS_ASSUME_NONNULL_END
