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
	IBOutlet NSButton *intrctPnlBtn, *spdColPnlBtn;
	IBOutlet NSColorWell *cwlBackground, *cwObstacles, *cwAgent,
		*cwGridLines, *cwSymbols, *cwParticles, *cwTracking, *cwInfoFG;
	IBOutlet NSTextField *dgtMemSize, *dgtMemTrials, *dgtNParticles, *dgtLifeSpan;
	IBOutlet NSTextField *dgtT0, *dgtT1, *dgtCoolingRate, *dgtInitQValue, *dgtGamma, *dgtAlpha,
		*dgtStpPS, *dgtMass, *dgtFriction, *dgtStrokeLength, *dgtStrokeWidth, *dgtMaxSpeed;
	IBOutlet NSPopUpButton *ptclColorPopup, *ptclShapePopup, *screenPopUp, *infoVConfPopUp, *obsPopUp;
	IBOutlet NSButton *cboxAltSG, *cboxDrawHand, *cBoxSounds,
		*cboxStartFullScr, *cboxRecordImages, *cBoxShowFPS,
		*btnSaveAsUD, *btnRevertToUD, *btnRevertToFD, *btnExport;
	IBOutlet NSTextField *txtBump, *txtGaol, *txtGood, *txtBad, *txtAmbience;
	IBOutlet NSButton *editBump, *editGoal, *editGood, *editBad, *editAmbience;
	IBOutlet NSButton *playBump, *playGoal, *playGood, *playBad, *playAmbience;
	IBOutlet NSPanel *sndPanel;
	IBOutlet NSTextField *sndPTitle, *sndPInfo, *sndPMMin, *sndPMMax, *sndPVol, *sndPMVal;
	IBOutlet NSSlider *sndPMValSld, *sndPVolSld;
	IBOutlet NSButton *sndPlayStopBtn, *sndPMSetMinBtn, *sndPMSetMaxBtn,
		*sndPRevertBtn, *sndApplyBtn;
	IBOutlet MyProgressBar *sndProgress;
	IBOutlet NSTextField *dgtMaxSteps, *dgtMaxGoalCnt, *dgtFadeoutSec;
}
- (void)checkFDBits:(NSInteger)bitPosition fd:(BOOL)fdc ud:(BOOL)udc;
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
