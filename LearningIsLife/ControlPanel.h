//
//  ControlPanel.h
//  Learning is Life
//
//  Created by Tatsuo Unemi on 2023/02/01.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class MyProgressBar;
@interface ControlPanel : NSWindowController
	<NSOpenSavePanelDelegate, NSSoundDelegate, NSWindowDelegate, NSMenuItemValidation> {
	IBOutlet NSColorWell *cwlBackground, *cwObstacles, *cwAgent,
		*cwGridLines, *cwSymbols, *cwParticles;
	IBOutlet NSTextField *dgtMemSize, *dgtMemTrials, *dgtNParticles, *dgtLifeSpan;
	IBOutlet NSTextField *dgtT0, *dgtT1, *dgtCoolingRate, *dgtInitQValue, *dgtGamma, *dgtAlpha,
		*dgtStpPS, *dgtMass, *dgtFriction, *dgtStrokeLength, *dgtStrokeWidth, *dgtMaxSpeed;
	IBOutlet NSButton *btnDrawByRects, *btnDrawByTriangles, *btnDrawByLines,
		*btnColConst, *btnColAngle, *btnColSpeed;
	IBOutlet NSButton *cBoxSounds, *cboxStartFullScr, *cboxRecordImages, *cBoxShowFPS,
		*btnRevertToFD, *btnExport;
	IBOutlet NSPopUpButton *screenPopUp, *obsPopUp;
	IBOutlet NSTextField *txtBump, *txtGaol, *txtGood, *txtBad, *txtAmbience;
	IBOutlet NSButton *editBump, *editGoal, *editGood, *editBad, *editAmbience;
	IBOutlet NSButton *playBump, *playGoal, *playGood, *playBad, *playAmbience;
	IBOutlet NSPanel *sndPanel;
	IBOutlet NSTextField *sndPTitle, *sndPInfo, *sndPMMin, *sndPMMax, *sndPVol, *sndPMVal;
	IBOutlet NSSlider *sndPMValSld, *sndPVolSld;
	IBOutlet NSButton *sndPlayStopBtn, *sndPMSetMinBtn, *sndPMSetMaxBtn,
		*sndPRevertBtn, *sndApplyBtn;
	IBOutlet MyProgressBar *sndProgress;
	IBOutlet NSTextField *dgtMaxSteps, *dgtMaxGoalCnt;
}
- (void)adjustNParticleDgt;
- (void)adjustColorMode:(NSDictionary *)info;
- (void)adjustShapeMode:(NSDictionary *)info;
@end

NS_ASSUME_NONNULL_END
