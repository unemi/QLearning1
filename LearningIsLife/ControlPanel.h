//
//  ControlPanel.h
//  Learning is Life
//
//  Created by Tatsuo Unemi on 2023/02/01.
//

@import Cocoa;
#import "CommonTypes.h"
NS_ASSUME_NONNULL_BEGIN

extern BOOL prm_equal(SoundPrm *a, SoundPrm *b);
extern void set_param_from_dict(SoundPrm *prm, NSDictionary *dict);
@class MyProgressBar;
@interface ControlPanel : NSWindowController
	<NSOpenSavePanelDelegate, NSSoundDelegate, NSWindowDelegate, NSMenuItemValidation> {
	IBOutlet NSTextField *dgtGridW, *dgtGridH, *dgtTileH,
		*dgtStartX, *dgtStartY, *dgtGoalX, *dgtGoalY, *dgtManObsLS;
	IBOutlet NSStepper *stpGridW, *stpGridH, *stpTileH,
		*stpStartX, *stpStartY, *stpGoalX, *stpGoalY;
	IBOutlet NSColorWell *cwlBackground, *cwObstacles, *cwAgent,
		*cwGridLines, *cwSymbols, *cwParticles, *cwTracking;
	IBOutlet NSTextField *dgtMemSize, *dgtMemTrials, *dgtNParticles, *dgtLifeSpan;
	IBOutlet NSTextField *dgtT0, *dgtT1, *dgtCoolingRate, *dgtInitQValue, *dgtGamma, *dgtAlpha,
		*dgtStpPS, *dgtMass, *dgtFriction, *dgtStrokeLength, *dgtStrokeWidth, *dgtMaxSpeed;
	IBOutlet NSButton *btnDrawByRects, *btnDrawByTriangles, *btnDrawByLines,
		*btnColConst, *btnColAngle, *btnColSpeed;
	IBOutlet NSButton *cBoxSounds, *cboxStartFullScr, *cboxRecordImages, *cBoxShowFPS, *cBoxSAUDWT,
		*btnSaveAsUD, *btnRevertToUD, *btnRevertToFD, *btnExport;
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
- (IBAction)importSettings:(NSButton *)sender;
- (IBAction)exportSettings:(id)sender;
- (IBAction)saveAsUserDefaults:(id)sender;
- (IBAction)revertToUserDefault:(id)sender;
- (IBAction)revertToFactoryDefault:(id)sender;
- (void)adjustNParticleDgt;
- (void)adjustColorMode:(NSDictionary *)info;
- (void)adjustShapeMode:(NSDictionary *)info;
@end

NS_ASSUME_NONNULL_END
