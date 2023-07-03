//
//  ControlPanel.m
//  Learning is Life
//
//  Created by Tatsuo Unemi on 2023/02/01.
//

#import "ControlPanel.h"
#import "InteractionPanel.h"
#import "SpeedColPanel.h"
#import "AppDelegate.h"
#import "MainWindow.h"
#import "Display.h"
#import "MySound.h"
@import UniformTypeIdentifiers;

BOOL prm_equal(SoundPrm *a, SoundPrm *b) {
	return [a->path isEqualToString:b->path] &&
		a->mmin == b->mmin && a->mmax == b->mmax && a->vol == b->vol;
}
static void setup_screen_menu(NSPopUpButton *popup,
	NSString *factoryDefault, NSString *currentName) {
	NSArray<NSScreen *> *screens = NSScreen.screens;
	NSInteger nItems = popup.numberOfItems;
	if (screens.count > 1) {
		[popup itemAtIndex:0].title = factoryDefault;
		for (NSInteger i = 0; i < screens.count; i ++) {
			NSString *name = screens[i].localizedName;
			if (i + 1 < nItems) [popup itemAtIndex:i + 1].title = name;
			else [popup addItemWithTitle:name];
		}
		for (NSInteger i = nItems - 1; i > screens.count; i --)
			[popup removeItemAtIndex:i];
		NSMenuItem *item = [popup itemWithTitle:currentName];
		if (item != nil) [popup selectItem:item];
		else [popup selectItemAtIndex:0];
	} else if (screens.count == 1) {
		[popup itemAtIndex:0].title = screens[0].localizedName;
		for (NSInteger i = nItems - 1; i > 0; i --)
			[popup removeItemAtIndex:i];
		[NSTimer scheduledTimerWithTimeInterval:.1
			repeats:NO block:^(NSTimer * _Nonnull timer) {
			[popup selectItemAtIndex:0];
		}];
	}
	popup.enabled = (screens.count > 1);
}

@implementation ControlPanel {
	NSArray<NSColorWell *> *colWels;
	NSArray<NSTextField *> *ivDgts, *fvDgts, *uvDgts, *sndTxts;
	NSArray<NSButton *> *boolVBtns, *editBtns, *playBtns;
	NSArray<NSStepper *> *ivStps;
	NSArray<NSControl *> *sndContrls, *wrldControls;
	InteractionPanel *intrctPnl;
	SpeedColPanel *spdColPnl;
	NSSound *soundNowPlaying;
	NSUndoManager *undoManager, *undoMng4SndPnl;
	SoundType playingSoundType, openingSoundType;
	SoundPrm orgSndParams;
	int FDBTCol, FDBTInt, FDBTFloat, FDBTUInt, FDBTBool, FDBTDc,
		FDBTDm, FDBTObs, FDBTFulScr, FDBTInfoV;
	UInt64 UDBits, FDBits;
}
- (NSString *)windowNibName { return @"ControlPanel"; }
- (NSArray<NSArray *> *)scrPopUpInfo {
	return @[@[screenPopUp, scrForFullScrFD, scrForFullScr],
		@[infoVConfPopUp, infoViewConfFD, infoViewConf]];
}
static void displayReconfigCB(CGDirectDisplayID display,
	CGDisplayChangeSummaryFlags flags, void *userInfo) {
	if ((flags & kCGDisplayBeginConfigurationFlag) != 0 ||
		(flags & (kCGDisplayAddFlag | kCGDisplayRemoveFlag |
		kCGDisplayEnabledFlag | kCGDisplayDisabledFlag)) == 0) return;
	in_main_thread(^{
		for (NSArray *info in ((__bridge ControlPanel *)userInfo).scrPopUpInfo)
			setup_screen_menu(info[0], info[1], info[2]);
	});
}
static NSString *sound_name(SoundType type) {
	return [sndData[type].key substringFromIndex:5];
}
static NSAttributedString *sound_info(SoundType type) {
	static NSFont *boldFont = nil;
	static NSParagraphStyle *paragraphStyle = nil;
	if (boldFont == nil) {
		boldFont = [NSFont systemFontOfSize:
			NSFont.smallSystemFontSize weight:NSFontWeightBold];
		NSMutableParagraphStyle *prStyle = NSMutableParagraphStyle.new;
		prStyle.paragraphStyle = NSParagraphStyle.defaultParagraphStyle;
		prStyle.lineBreakMode = NSLineBreakByCharWrapping;
		prStyle.alignment = NSTextAlignmentJustified;
		paragraphStyle = prStyle;
	}
	SoundPrm prm = sndData[type].v;
	NSString *name = sound_name(type);
	NSMutableAttributedString *str = [NSMutableAttributedString.alloc
		initWithString:[NSString stringWithFormat:@"%@:\"%@\" %.2f [%.2f,%.2f]",
			name, [prm.path.lastPathComponent stringByDeletingPathExtension],
			prm.vol, prm.mmin, prm.mmax]];
	[str addAttribute:NSParagraphStyleAttributeName
		value:paragraphStyle range:(NSRange){0, str.length}];
	[str addAttribute:NSFontAttributeName
		value:boldFont range:(NSRange){0, name.length}];
	return str;
}
- (void)adjustSoundsCtrls {
	if (SOUNDS_ON) for (SoundType type = 0; type < NVoices; type ++) {
		SoundSrc *s = &sndData[type];
		sndTxts[type].attributedStringValue = sound_info(type);
		editBtns[type].enabled = YES;
		playBtns[type].enabled = (s->v.path.length > 0);
	} else for (SoundType type = 0; type < NVoices; type ++) {
		sndTxts[type].stringValue = @"";
		editBtns[type].enabled = playBtns[type].enabled = NO;
	}
}
static void adjust_position_max_values(NSTextField *dgt, NSStepper *stp, NSInteger mx) {
	((NSNumberFormatter *)dgt.formatter).maximum = @(stp.maxValue = mx - 1);
} 
- (void)adjustControls {
	for (NSColorWell *cwl in colWels) cwl.color = *ColVars[cwl.tag].v;
	for (NSTextField *dgt in ivDgts) dgt.intValue = *IntVars[dgt.tag].v;
	for (NSTextField *dgt in fvDgts) dgt.floatValue = *FloatVars[dgt.tag].v;
	for (NSTextField *dgt in uvDgts) dgt.integerValue = UIntegerVars[dgt.tag].v;
	for (NSStepper *stp in ivStps) stp.intValue = *IntVars[stp.tag].v;
	for (NSButton *btn in boolVBtns) btn.state = BoolVars[btn.tag].v;
	[ptclColorPopup selectItemAtIndex:ptclColorMode];
	[ptclShapePopup selectItemAtIndex:ptclShapeMode];
	dgtStrokeWidth.enabled = (ptclShapeMode != PTCLbyLines);
	[obsPopUp selectItemAtIndex:newObsMode];
	[screenPopUp selectItemWithTitle:scrForFullScr];
	[infoVConfPopUp selectItemWithTitle:infoViewConf];
	[self adjustSoundsCtrls];
	for (NSControl *ctrl in wrldControls) ctrl.enabled = (newObsMode >= ObsPointer);
	cboxRecordImages.enabled = (obstaclesMode != ObsExternal);
	adjust_position_max_values(dgtStartX, stpStartX, newGridW);
	adjust_position_max_values(dgtStartY, stpStartY, newGridH);
	adjust_position_max_values(dgtGoalX, stpGoalX, newGridW);
	adjust_position_max_values(dgtGoalY, stpGoalY, newGridH);
	dgtCoolingRate.enabled = (MAX_STEPS == 0);
	btnRevertToFD.enabled = btnExport.enabled = (FDBits != 0);
	btnSaveAsUD.enabled = btnRevertToUD.enabled = (UDBits != 0);
	spdColPnlBtn.enabled = ptclColorMode == PTCLspeedColor;
}
#define SETUP_CNTRL(b,class,list,fn,var,ref,act)	b = (int)bit; tag = 0;\
	for (class *ctr in list) {\
		if (fn(var ref[tag].v) != fn(ref[tag].fd)) FDBits |= 1 << bit;\
		ctr.target = self;\
		ctr.action = @selector(act:);\
		ctr.tag = tag ++; bit ++;\
	}
#define SETUP_CHOICE(b,var,varFD)	b = (int)bit;\
	if (var != varFD) FDBits |= 1 << bit;\
	bit ++;
- (void)windowDidLoad {
	[super windowDidLoad];
	if (self.window == nil) return;
	undoManager = NSUndoManager.new;
	setup_screen_menu(screenPopUp, scrForFullScrFD, scrForFullScr);
	setup_screen_menu(infoVConfPopUp, infoViewConfFD, infoViewConf);
	CGError error = CGDisplayRegisterReconfigurationCallback
		(displayReconfigCB, (__bridge void *)self);
	if (error != kCGErrorSuccess)
		NSLog(@"CGDisplayRegisterReconfigurationCallback error = %d", error);
	colWels = @[cwlBackground, cwObstacles, cwAgent, cwGridLines, cwSymbols, cwParticles,
		cwTracking, cwInfoFG];
	ivDgts = @[dgtGridW, dgtGridH, dgtTileH, dgtStartX, dgtStartY, dgtGoalX, dgtGoalY,
		dgtMemSize, dgtMemTrials, dgtNParticles, dgtLifeSpan];
	ivStps = @[stpGridW, stpGridH, stpTileH, stpStartX, stpStartY, stpGoalX, stpGoalY];
	fvDgts = @[dgtT0, dgtT1, dgtCoolingRate, dgtInitQValue, dgtGamma, dgtAlpha,
		dgtStpPS, dgtMass, dgtFriction, dgtStrokeLength, dgtStrokeWidth, dgtMaxSpeed, dgtManObsLS,
		dgtFadeoutSec];
	uvDgts = @[dgtMaxSteps, dgtMaxGoalCnt];
	boolVBtns = @[cboxDrawHand, cBoxSounds, cboxStartFullScr, cboxRecordImages, cBoxShowFPS];
	sndTxts = @[txtBump, txtGaol, txtGood, txtBad, txtAmbience];
	editBtns = @[editBump, editGoal, editGood, editBad, editAmbience];
	playBtns = @[playBump, playGoal, playGood, playBad, playAmbience];
	sndContrls = @[sndPMVal, sndPMValSld, sndPVolSld, sndPMSetMinBtn, sndPMSetMaxBtn];
	wrldControls = @[dgtStartX, dgtStartY, dgtGoalX, dgtGoalY,
		stpStartX, stpStartY, stpGoalX, stpGoalY, dgtManObsLS, cwTracking,
		intrctPnlBtn, cboxDrawHand];
	NSInteger bit = 0, tag;
	SETUP_CNTRL(FDBTCol, NSColorWell, colWels, col_to_ulong, *, ColVars, chooseColorWell)
	SETUP_CNTRL(FDBTInt, NSTextField, ivDgts, , *, IntVars, changeIntValue)
	SETUP_CNTRL(FDBTFloat, NSTextField, fvDgts, , *, FloatVars, changeFloatValue)
	bit = [InteractionPanel initParams:bit fdBits:&FDBits];
	SETUP_CNTRL(FDBTUInt, NSTextField, uvDgts, , , UIntegerVars, changeUIntegerValue)
	SETUP_CNTRL(FDBTBool, NSButton, boolVBtns, , , BoolVars, switchBoolValue)
	for (NSInteger i = 0; i < ivStps.count; i ++) {
		ivStps[i].tag = i;
		ivStps[i].target = self;
		ivStps[i].action = @selector(changeIntValue:);
		NSNumberFormatter *fmt = ivDgts[i].formatter;
		ivStps[i].minValue = fmt.minimum.integerValue;
		ivStps[i].maxValue = fmt.maximum.integerValue;
	}
	SETUP_CHOICE(FDBTDc, ptclColorMode, ptclColorModeFD)
	SETUP_CHOICE(FDBTDm, ptclShapeMode, ptclShapeModeFD)
	SETUP_CHOICE(FDBTObs, newObsMode, obsModeFD)
	SETUP_CHOICE(FDBTFulScr, scrForFullScr, scrForFullScrFD)
	SETUP_CHOICE(FDBTInfoV, infoViewConf, infoViewConfFD)
	bit = [SpeedColPanel initParams:bit fdBits:&FDBits];
	for (SoundType type = 0; type < NVoices; type ++, bit ++) {
		SoundSrc *s = &sndData[type];
		s->FDBit = (int)bit;
		if (!prm_equal(&s->v, &s->fd)) FDBits |= 1 << bit;
	}
#ifdef DEBUG
NSLog(@"%ld parameters", bit);
printf("FDBTCol=%d, FDBTInt=%d, FDBTFloat=%d, FDBTUInt=%d, FDBTBool=%d, FDBTDc=%d,\
 FDBTDm=%d, FDBTObs=%d, FDBTFulScr=%d, FDBTInfoV=%d\n",
		FDBTCol, FDBTInt, FDBTFloat, FDBTUInt, FDBTBool, FDBTDc,
		FDBTDm, FDBTObs, FDBTFulScr, FDBTInfoV);
#endif
	[self adjustControls];
	[NSNotificationCenter.defaultCenter addObserverForName:@"obsModeChangedByReset"
		object:NSApp queue:nil usingBlock:^(NSNotification * _Nonnull note) {
		self->cboxRecordImages.enabled = (obstaclesMode != ObsExternal);
	}];
}
- (void)checkFDBits:(NSInteger)bitPosition fd:(BOOL)fdc ud:(BOOL)udc {
	UInt64 mask = 1ULL << bitPosition;
	if (fdc) FDBits &= ~ mask; else FDBits |= mask;
	if (udc) UDBits &= ~ mask; else UDBits |= mask;
	btnRevertToFD.enabled = btnExport.enabled = (FDBits != 0);
	btnSaveAsUD.enabled = btnRevertToUD.enabled = (UDBits != 0);
}
- (IBAction)chooseColorWell:(NSColorWell *)colWl {
	ColVarInfo *info = &ColVars[colWl.tag];
	NSColor * __strong *var = info->v, *newValue = colWl.color;
	NSUInteger newValUlong = col_to_ulong(newValue);
	if (col_to_ulong(*var) == newValUlong) return;
	NSColor *orgValue = *var;
	[undoManager registerUndoWithTarget:self handler:^(id _Nonnull target) {
		colWl.color = orgValue;
		[colWl sendAction:colWl.action to:target];
	}];
	undoManager.actionName = NSLocalizedString(info->key, nil);
	*var = newValue;
	[self checkFDBits:FDBTCol + (int)colWl.tag
		fd:newValUlong == col_to_ulong(info->fd)
		ud:newValUlong == col_to_ulong(info->ud)];
	[NSNotificationCenter.defaultCenter postNotificationName:
		(info->flag & ShouldPostNotification)? info->key : keyShouldRedraw object:NSApp];
}
- (void)checkWorldContrl:(NSControl *)ctl newValue:(int)newValue {
	if (ctl.tag >= ivStps.count) return;
	NSControl *cp;
	if ([ctl isKindOfClass:NSStepper.class]) cp = ivDgts[ctl.tag];
	else cp = ivStps[ctl.tag];
	cp.intValue = newValue;
	if (ctl.tag == GRID_W_TAG) {
		adjust_position_max_values(dgtStartX, stpStartX, newValue);
		adjust_position_max_values(dgtGoalX, stpGoalX, newValue);
	} else if (ctl.tag == GRID_H_TAG) {
		adjust_position_max_values(dgtStartY, stpStartY, newValue);
		adjust_position_max_values(dgtGoalY, stpGoalY, newValue);
	}
}
- (IBAction)changeIntValue:(NSControl *)ctl {
	IntVarInfo *info = &IntVars[ctl.tag];
	int *var = info->v, newValue = ctl.intValue;
	if (*var == newValue) return;
	int orgValue = *var;
	[self checkWorldContrl:ctl newValue:newValue];
	[undoManager registerUndoWithTarget:self handler:^(id _Nonnull target) {
		ctl.intValue = orgValue;
		[ctl sendAction:ctl.action to:target];
	}];
	undoManager.actionName = NSLocalizedString(info->key, nil);
	*var = newValue;
	[self checkFDBits:FDBTInt + ctl.tag
		fd:newValue == info->fd ud:newValue == info->ud];
	if (info->flag & ShouldPostNotification)
		[NSNotificationCenter.defaultCenter postNotificationName:
			info->key object:NSApp userInfo:@{keyOldValue:@(orgValue), keyCntlPnl:self}];
}
- (IBAction)changeFloatValue:(NSTextField *)dgt {
	FloatVarInfo *info = &FloatVars[dgt.tag];
	float *var = info->v, newValue = dgt.floatValue;
	if (*var == newValue) return;
	float orgValue = *var;
	[undoManager registerUndoWithTarget:self handler:^(id _Nonnull target) {
		dgt.floatValue = orgValue;
		[dgt sendAction:dgt.action to:target];
	}];
	undoManager.actionName = NSLocalizedString(info->key, nil);
	*var = newValue;
	[self checkFDBits:FDBTFloat + dgt.tag
		fd:newValue == info->fd ud:newValue == info->ud];
	if (info->flag & ShouldRedrawScreen) [NSNotificationCenter.defaultCenter
		postNotificationName:keyShouldRedraw object:NSApp];
	if (info->flag & ShouldReviseVertices) [NSNotificationCenter.defaultCenter
		postNotificationName:keyShouldReviseVertices object:NSApp];
}
- (IBAction)changeUIntegerValue:(NSTextField *)dgt {
	UIntegerVarInfo *info = &UIntegerVars[dgt.tag];
	NSUInteger newValue = dgt.integerValue, orgValue = info->v;
	if (orgValue == newValue) return;
	[undoManager registerUndoWithTarget:self handler:^(id _Nonnull target) {
		dgt.integerValue = orgValue;
		[dgt sendAction:dgt.action to:target];
	}];
	undoManager.actionName = NSLocalizedString(info->key, nil);
	info->v = newValue;
	[self checkFDBits:FDBTUInt + dgt.tag
		fd:newValue == info->fd ud:newValue == info->ud];
	if (dgt.tag == MAX_STEPS_TAG)
		dgtCoolingRate.enabled = (MAX_STEPS == 0);
	if (info->flag & ShouldPostNotification) [NSNotificationCenter.defaultCenter
		postNotificationName:info->key object:NSApp];
}
- (IBAction)switchBoolValue:(NSButton *)btn {
	BoolVarInfo *info = &BoolVars[btn.tag];
	BOOL newValue = btn.state, orgValue = info->v;
	if (newValue == orgValue) return;
	[undoManager registerUndoWithTarget:self handler:^(id _Nonnull target) {
		btn.state = orgValue;
		[btn sendAction:btn.action to:target];
	}];
	undoManager.actionName = btn.title;
	info->v = newValue;
	[self checkFDBits:FDBTBool + btn.tag
		fd:newValue == info->fd ud:newValue == info->ud];
	if (info->flag & ShouldPostNotification)
		[NSNotificationCenter.defaultCenter
			postNotificationName:info->key object:NSApp];
	if (info->flag & ShouldRedrawScreen) [NSNotificationCenter.defaultCenter
		postNotificationName:keyShouldRedraw object:NSApp];
	if ([info->key isEqualToString:@"sounds"]) [self adjustSoundsCtrls];
}
- (IBAction)chooseColorMode:(NSPopUpButton *)popUp {
	PTCLColorMode newValue = (PTCLColorMode)popUp.indexOfSelectedItem;
	if (ptclColorMode == newValue) return;
	PTCLColorMode orgValue = ptclColorMode;
	[undoManager registerUndoWithTarget:self handler:^(id _Nonnull target) {
		[popUp selectItemAtIndex:orgValue];
		[popUp sendAction:popUp.action to:popUp.target];
	}];
	undoManager.actionName = NSLocalizedString(keyColorMode, nil);
	ptclColorMode = newValue;
	[self checkFDBits:FDBTDc fd:newValue == ptclColorModeFD ud:newValue == ptclColorModeUD];
	[NSNotificationCenter.defaultCenter postNotificationName:
		keyColorMode object:NSApp userInfo:@{keyCntlPnl:self}];
	spdColPnlBtn.enabled = newValue == PTCLspeedColor;
}
- (IBAction)chooseShapeMode:(NSPopUpButton *)popUp {
	PTCLShapeMode newValue = (PTCLShapeMode)popUp.indexOfSelectedItem;
	if (ptclShapeMode == newValue) return;
	PTCLShapeMode orgValue = ptclShapeMode;
	[undoManager registerUndoWithTarget:self handler:^(id _Nonnull target) {
		[popUp selectItemAtIndex:orgValue];
		[popUp sendAction:popUp.action to:popUp.target];
	}];
	undoManager.actionName = NSLocalizedString(keyShapeMode, nil);
	ptclShapeMode = newValue;
	dgtStrokeWidth.enabled = (newValue != PTCLbyLines);
	[self checkFDBits:FDBTDm fd:newValue == ptclShapeModeFD ud:newValue == ptclShapeModeUD];
	[NSNotificationCenter.defaultCenter postNotificationName:
		keyShapeMode object:NSApp userInfo:@{keyCntlPnl:self}];
}
- (IBAction)chooseObstaclesMode:(NSPopUpButton *)popUp {
	ObstaclesMode newValue = (ObstaclesMode)popUp.indexOfSelectedItem;
	if (newObsMode == newValue) return;
	ObstaclesMode orgValue = newObsMode;
	[undoManager registerUndoWithTarget:self handler:^(id _Nonnull target) {
		[popUp selectItemAtIndex:orgValue];
		[popUp sendAction:popUp.action to:popUp.target];
	}];
	undoManager.actionName = NSLocalizedString(keyObsMode, nil);
	newObsMode = newValue;
	for (NSControl *cntrl in wrldControls) cntrl.enabled = (newValue >= ObsPointer);
	[NSNotificationCenter.defaultCenter postNotificationName:keyObsMode object:NSApp];
}
- (IBAction)openInteractPanel:(id)sender {
	if (intrctPnl == nil) intrctPnl =
		[InteractionPanel.alloc initWithWindow:nil];
	if (intrctPnl.window != nil) [intrctPnl setupControls];
	[self.window beginSheet:intrctPnl.window completionHandler:
		^(NSModalResponse returnCode) {	}];
}
- (IBAction)openSpeedColPanel:(id)sender {
	if (spdColPnl == nil) spdColPnl =
		[SpeedColPanel.alloc initWithWindow:nil];
	if (spdColPnl.window != nil) [spdColPnl setupControls];
	[self.window beginSheet:spdColPnl.window completionHandler:
		^(NSModalResponse returnCode) {}];
}
- (NSString *)chooseScreenName:(NSPopUpButton *)popUp key:(NSString *)key
	orgValue:(NSString *)orgValue fd:(NSString *)fd ud:(NSString *)ud bit:(int)bit {
	NSString *newValue = popUp.titleOfSelectedItem;
	if ([scrForFullScr isEqualToString:newValue]) return orgValue;
	[undoManager registerUndoWithTarget:self handler:^(id _Nonnull target) {
		if ([popUp itemWithTitle:orgValue] != nil)
			[popUp selectItemWithTitle:orgValue];
		else [popUp selectItemAtIndex:0];
		[popUp sendAction:popUp.action to:target];
	}];
	undoManager.actionName = NSLocalizedString(key, nil);
	[self checkFDBits:bit fd:newValue == fd ud:newValue == ud];
	return newValue;
}
- (IBAction)chooseScreenForFullScreen:(NSPopUpButton *)popUp {
	scrForFullScr = [self chooseScreenName:popUp key:keyScrForFullScr
		orgValue:scrForFullScr fd:scrForFullScrFD ud:scrForFullScrUD bit:FDBTFulScr];
}
- (IBAction)chooseInfoViewConf:(NSPopUpButton *)popUp {
	infoViewConf = [self chooseScreenName:popUp key:keyInfoViewConf
		orgValue:infoViewConf fd:infoViewConfFD ud:infoViewConfUD bit:FDBTInfoV];
}
- (void)setSoundType:(SoundType)type prm:(SoundPrm)prm {
	SoundSrc *s = &sndData[type];
	if (prm_equal(&prm, &s->v)) return;
	SoundPrm orgPrm = s->v;
	change_sound_data(type, prm.path);
	s->v = prm;
	sndTxts[type].attributedStringValue = sound_info(type);
	[self checkFDBits:sndData[type].FDBit
		fd:prm_equal(&prm, &s->fd) ud:prm_equal(&prm, &s->ud)];
	[undoManager registerUndoWithTarget:self handler:^(id _Nonnull target) {
		[self setSoundType:type prm:orgPrm];
	}];
}
- (SoundPrm)getSoundParamsFromPanel {
	return (SoundPrm){ sndPInfo.stringValue,
		sndPMMin.doubleValue, sndPMMax.doubleValue, sndPVol.doubleValue };
}
- (void)stopIfNeeded {
	if (sndPlayStopBtn.state == NSControlStateValueOn) {
		sndPlayStopBtn.state = NSControlStateValueOff;
		[sndPlayStopBtn sendAction:sndPlayStopBtn.action to:sndPlayStopBtn.target];
	}
}
- (void)beginSoundPanel {
	SoundType type = openingSoundType;
	SoundSrc *s = &sndData[type];
	orgSndParams = [self getSoundParamsFromPanel];
	sndPRevertBtn.enabled = !prm_equal(&orgSndParams, &s->fd);
	[self.window beginSheet:sndPanel completionHandler:^(NSModalResponse returnCode) {
		switch (returnCode) {
			case NSModalResponseOK:
			[self setSoundType:type prm:[self getSoundParamsFromPanel]];
			self->undoManager.actionName = NSLocalizedString(@"Sound Settings", nil);
			case NSModalResponseCancel:
			self->undoMng4SndPnl = nil;
			[self stopIfNeeded];
			default: break;
		}
	}];
}
- (void)checkSndPrmsChanged {
	SoundPrm newPrm = [self getSoundParamsFromPanel];
	sndPRevertBtn.enabled = !prm_equal(&newPrm, &sndData[openingSoundType].fd);
	sndApplyBtn.enabled = !prm_equal(&newPrm, &orgSndParams);
}
- (void)setSoundParamToPanel:(SoundPrm *)p {
	sndPInfo.stringValue = p->path;
	sndPMMin.doubleValue = sndPMValSld.minValue = p->mmin;
	sndPMMax.doubleValue = sndPMValSld.maxValue = p->mmax;
	sndPVol.doubleValue = sndPVolSld.doubleValue = p->vol;
	((NSNumberFormatter *)sndPMMin.formatter).maximum = @(p->mmax);
	((NSNumberFormatter *)sndPMMax.formatter).minimum = @(p->mmin);
	sndPMVal.doubleValue = sndPMValSld.doubleValue =
		fmaxf(p->mmin, fminf(p->mmax, 0.));
	[self checkSndPrmsChanged];
}
static NSString *keyPath = @"path", *keyPMMin = @"pmMin", *keyPMMax = @"pmMax",
	*keyPM = @"pm", *keyVol = @"vol";
- (NSDictionary *)sndParamDict {
	return @{keyPath:sndPInfo.stringValue,
		keyPMMin:@(sndPMMin.doubleValue), keyPMMax:@(sndPMMax.doubleValue),
		keyPM:@(sndPMVal.doubleValue), keyVol:@(sndPVol.doubleValue)};
}
- (void)setDictToPanel:(NSDictionary *)dict {
	[undoMng4SndPnl registerUndoWithTarget:self
		selector:@selector(setDictToPanel:) object:[self sndParamDict]];
	SoundPrm prm = {dict[keyPath],
		[dict[keyPMMin] doubleValue], [dict[keyPMMax] doubleValue],
		[dict[keyVol] doubleValue] };
	[self setSoundParamToPanel:&prm];
	sndPMVal.doubleValue = sndPMValSld.doubleValue = [dict[keyPM] doubleValue];
}
- (IBAction)openSoundPanel:(NSButton *)btn {
	SoundType type = openingSoundType = (SoundType)btn.tag;
	sndPTitle.stringValue = [NSString stringWithFormat:@"%@ Sound Settings", sound_name(type)];
	[self setSoundParamToPanel:&sndData[type].v];
	undoMng4SndPnl = NSUndoManager.new;
	sndProgress.maxValue = 0.;
	sndProgress.needsDisplay = YES;
	sndApplyBtn.enabled = NO;
	[self beginSoundPanel];
}
- (IBAction)soundPanelOK:(id)sender {
	[self.window endSheet:sndPanel returnCode:NSModalResponseOK];
}
- (IBAction)soundPanelCancel:(id)sender {
	[self.window endSheet:sndPanel returnCode:NSModalResponseCancel];
}
- (void)setSndPInfoPath:(NSString *)newPath {
	[undoMng4SndPnl registerUndoWithTarget:self
		selector:@selector(setSndPInfoPath:) object:sndPInfo.stringValue];
	sndPInfo.stringValue = newPath;
	[self checkSndPrmsChanged];
	[self stopIfNeeded];
}
- (IBAction)chooseSound:(NSButton *)btn {
	[self.window endSheet:sndPanel returnCode:NSModalResponseStop];
	NSOpenPanel *op = NSOpenPanel.openPanel;
	op.allowedContentTypes = @[UTTypeAudio];
	op.directoryURL = [NSURL fileURLWithPath:
		sndPInfo.stringValue.stringByDeletingLastPathComponent];
	op.message = [NSString stringWithFormat:
		@"Choose a sound file for %@.", sound_name(openingSoundType)];
	op.delegate = self;
	op.treatsFilePackagesAsDirectories = YES;
	[op beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
		if (result == NSModalResponseOK) {
			[self setSndPInfoPath:op.URL.path];
			self->undoMng4SndPnl.actionName = NSLocalizedString(@"Sound File Path", nil);
		}
		[self beginSoundPanel];
	}];
}
- (IBAction)defaultFile:(NSButton *)sender {
	[undoMng4SndPnl registerUndoWithTarget:self
		selector:@selector(setDictToPanel:) object:[self sndParamDict]];
	undoMng4SndPnl.actionName = sender.title;
	SoundSrc *s = &sndData[openingSoundType];
	[self setSoundParamToPanel:&s->fd];
}
- (IBAction)playStopSound:(NSButton *)btn {
	if (btn.state == NSControlStateValueOn) {
		for (NSControl *ctrl in sndContrls) ctrl.enabled = YES;
		sndProgress.maxValue = enter_test_mode(sndPInfo.stringValue,
			sndPMVal.floatValue, sndPVol.floatValue, ^(CGFloat value){
				self->sndProgress.doubleValue = value;
				in_main_thread(^{self->sndProgress.needsDisplay = YES;});
		});
		sndProgress.needsDisplay = YES;
	} else {
		exit_test_mode();
		for (NSControl *ctrl in sndContrls) ctrl.enabled = NO;
		sndProgress.maxValue = 0.;
		sndProgress.needsDisplay = YES;
		[NSNotificationCenter.defaultCenter
			postNotificationName:keySoundTestExited object:NSApp];
	}
}
- (IBAction)assignPMMin:(NSTextField *)sender {
	NSTextField *dgt = [sender isKindOfClass:NSTextField.class]? sender : sndPMVal;
	CGFloat value = dgt.doubleValue, orgValue = sndPMValSld.minValue;
	if (value == orgValue) return;
	[undoMng4SndPnl registerUndoWithTarget:sndPMMin handler:^(NSTextField *tf) {
		tf.doubleValue = orgValue;
		[tf sendAction:tf.action to:tf.target];
	}];
	undoMng4SndPnl.actionName = NSLocalizedString(@"min", nil);
	((NSNumberFormatter *)sndPMMax.formatter).minimum = 
	((NSNumberFormatter *)sndPMVal.formatter).minimum = @(value);
	sndPMValSld.minValue = value;
	if (dgt == sndPMVal) sndPMMin.doubleValue = value;
	else if (sndPMVal.doubleValue < value)
		sndPMVal.doubleValue = sndPMValSld.doubleValue = value;
	[self checkSndPrmsChanged];
}
- (IBAction)assignPMMax:(NSTextField *)sender {
	NSTextField *dgt = [sender isKindOfClass:NSTextField.class]? sender : sndPMVal;
	CGFloat value = dgt.doubleValue, orgValue = sndPMValSld.maxValue;
	if (value == orgValue) return;
	[undoMng4SndPnl registerUndoWithTarget:sndPMMax handler:^(NSTextField *tf) {
		tf.doubleValue = orgValue;
		[tf sendAction:tf.action to:tf.target];
	}];
	undoMng4SndPnl.actionName = NSLocalizedString(@"max", nil);
	((NSNumberFormatter *)sndPMMin.formatter).maximum = 
	((NSNumberFormatter *)sndPMVal.formatter).maximum = @(value);
	sndPMValSld.maxValue = value;
	if (dgt == sndPMVal) sndPMMax.doubleValue = value;
	else if (sndPMVal.doubleValue > value)
		sndPMVal.doubleValue = sndPMValSld.doubleValue = value;
	[self checkSndPrmsChanged];
}
- (void)changeSldDgtValue:(NSControl *)sender sld:(NSSlider *)sld dgt:(NSTextField *)dgt {
	NSControl *pc = (sender == sld)? dgt : sld;
	CGFloat value = sender.doubleValue, orgValue = pc.doubleValue;
	if (value == orgValue) return;
	[undoMng4SndPnl registerUndoWithTarget:sender handler:^(NSControl *ctl) {
		ctl.doubleValue = orgValue;
		[ctl sendAction:ctl.action to:ctl.target];
	}];
	pc.doubleValue = value;
}
- (IBAction)changePMValue:(NSControl *)sender {
	[self changeSldDgtValue:sender sld:sndPMValSld dgt:sndPMVal];
	undoMng4SndPnl.actionName = NSLocalizedString(@"Modulation", nil);
	set_test_mode_pm(sender.floatValue);
}
- (IBAction)changePVolume:(NSControl *)sender {
	[self changeSldDgtValue:sender sld:sndPVolSld dgt:sndPVol];
	undoMng4SndPnl.actionName = NSLocalizedString(@"Volume", nil);
	[self checkSndPrmsChanged];
	set_test_mode_vol(sender.floatValue);
}
// Delegate method for NSOpenPanel to disable MIDI files.
- (BOOL)panel:(id)sender shouldEnableURL:(NSURL *)url {
	return ![@[@"mid", @"midi"] containsObject:url.pathExtension];
}
- (IBAction)listenSound:(NSButton *)btn {
	SoundType type = (SoundType)btn.tag;
	if (soundNowPlaying != nil) {
		[soundNowPlaying stop];
		if (playingSoundType == type) { soundNowPlaying = nil; return; }
	}
	playingSoundType = type;
	soundNowPlaying = [NSSound.alloc initWithContentsOfFile:sndData[type].v.path byReference:YES];
	soundNowPlaying.delegate = self;
	[soundNowPlaying play];
}
- (void)sound:(NSSound *)sound didFinishPlaying:(BOOL)flag {
	playBtns[playingSoundType].state = NSControlStateValueOff;
	soundNowPlaying = nil;
}
static NSDictionary *param_diff_dict(SoundPrm *a, SoundPrm *b) {
	NSMutableDictionary *md = NSMutableDictionary.new;
	if (![a->path isEqualToString:b->path]) md[@"path"] = b->path;
	if (a->mmin != b->mmin) md[@"mmin"] = @(b->mmin);
	if (a->mmax != b->mmax) md[@"mmax"] = @(b->mmax);
	if (a->vol != b->vol) md[@"vol"] = @(b->vol);
	return md;
}
void set_param_from_dict(SoundPrm *prm, NSDictionary *dict) {
	NSNumber *num; NSString *str;
	if ((str = dict[@"path"]) != nil) prm->path = str;
	if ((num = dict[@"mmin"]) != nil) prm->mmin = num.floatValue;
	if ((num = dict[@"mmax"]) != nil) prm->mmax = num.floatValue;
	if ((num = dict[@"vol"]) != nil) prm->vol = num.floatValue;
}
- (IBAction)exhibitionMode:(id)sender {
	NSColor *transparent = [NSColor colorWithWhite:0. alpha:0.];
	[self setParamValuesFromDict:@{
		@"colorGridLines":transparent, @"colorSymbols":transparent,
		@"sounds":@NO, @"recordFinalImage":@NO,@"startWithFullScreenMode":@YES,
		keyObsMode:@(ObsExternal)
	}];
}
#define CLCT_DF(elm,forAll,infoType,valType,valGetter,star)	forAll(^(infoType *p) {\
	if (star p->v != p->elm) md[p->key] = @(p->elm); });
#define CLCT_DF_ENM(key,dfVar,var)	if (var != dfVar) md[key] = @(dfVar);
#define CLCT_DF_STR(key,dfVar,var) if (![var isEqualToString:dfVar]) md[key] = dfVar;
#define REVERT_TO_DF(elm) \
	NSMutableDictionary *md = NSMutableDictionary.new;\
	CLCT_DF(elm, for_all_int_vars, IntVarInfo, int, intValue, *)\
	CLCT_DF(elm, for_all_float_vars, FloatVarInfo, float, floatValue, *)\
	CLCT_DF(elm, for_all_uint_vars, UIntegerVarInfo, NSUInteger, integerValue, )\
	CLCT_DF(elm, for_all_bool_vars, BoolVarInfo, BOOL, boolValue, )\
	for_all_color_vars(^(ColVarInfo *p) {\
		if (col_to_ulong(*p->v) != col_to_ulong(p->elm)) md[p->key] = p->elm; });\
	for (SoundType type = 0; type < NVoices; type ++) {\
		SoundSrc *s = &sndData[type];\
		if (!prm_equal(&s->v, &s->elm)) md[s->key] = param_diff_dict(&s->v, &s->elm); }
- (IBAction)revertToUserDefault:(id)sender {
	REVERT_TO_DF(ud)
	CLCT_DF_ENM(keyColorMode, ptclColorModeUD, ptclColorMode)
	CLCT_DF_ENM(keyShapeMode, ptclShapeModeUD, ptclShapeMode)
	CLCT_DF_ENM(keyObsMode, obsModeUD, newObsMode)
	CLCT_DF_STR(keyScrForFullScr, scrForFullScrUD, scrForFullScr)
	CLCT_DF_STR(keyInfoViewConf, infoViewConfUD, infoViewConf)
	if (!spdcol_is_equal_to(spdColUD)) md[keySpeedColors] = spdColUD;
	[self setParamValuesFromDict:md];
	undoManager.actionName = btnRevertToUD.title;
}
- (IBAction)revertToFactoryDefault:(id)sender {
	REVERT_TO_DF(fd)
	CLCT_DF_ENM(keyColorMode, ptclColorModeFD, ptclColorMode)
	CLCT_DF_ENM(keyShapeMode, ptclShapeModeFD, ptclShapeMode)
	CLCT_DF_ENM(keyObsMode, obsModeFD, newObsMode)
	CLCT_DF_STR(keyScrForFullScr, scrForFullScrFD, scrForFullScr)
	CLCT_DF_STR(keyInfoViewConf, infoViewConfFD, infoViewConf)
	if (!spdcol_is_equal_to(spdColFD)) md[keySpeedColors] = spdColFD;
	[self setParamValuesFromDict:md];
	undoManager.actionName = btnRevertToFD.title;
}
#define SETPRM_DICT(forAll,iType,vType,getter,tbl,bt,star)	forAll(^(iType *p) {\
		NSNumber *num = dict[p->key]; if (num == nil) return;\
		vType newValue = num.getter; if (star p->v == newValue) return;\
		if (p->flag & ShouldPostNotification) [postKeys addObject:p->key];\
		orgValues[p->key] = @(star p->v);\
		UInt64 bit = 1 << (self->bt + (p - tbl));\
		if (newValue == p->fd || star p->v == p->fd) *fbP |= bit;\
		if (newValue == p->ud || star p->v == p->ud) *ubP |= bit;\
		star p->v = newValue; });
#define SETENM_DICT(key,type,fdVar,udVar,var,bt) 	if ((num = dict[key]) != nil) {\
	type newValue = num.intValue;\
	if (var != newValue) {\
		orgValues[key] = @(var);\
		UInt64 bit = 1 << bt;\
		if (var == fdVar || newValue == fdVar) *fbP |= bit;\
		if (var == udVar || newValue == udVar) *ubP |= bit;\
		var = newValue;\
		[postKeys addObject:key]; }}
#define SETSTR_DICT(key,fdVar,udVar,var,bt)	newValue = dict[key];\
	if (newValue != nil && ![var isEqualToString:newValue]) {\
		orgValues[key] = var;\
		UInt64 bit = 1 << bt;\
		if (var == fdVar || newValue == fdVar) fdFlipBits |= bit;\
		if (var == udVar || newValue == udVar) udFlipBits |= bit;\
		var = newValue;\
	}

- (void)setParamValuesFromDict:(NSDictionary *)dict {
	NSMutableArray<NSString *> *postKeys = NSMutableArray.new;
	NSMutableDictionary *orgValues = NSMutableDictionary.new;
	BOOL shouldRedraw = NO, *srP = &shouldRedraw;
	UInt64 fdFlipBits = 0, *fbP = &fdFlipBits, udFlipBits = 0, *ubP = &udFlipBits;
	SETPRM_DICT(for_all_int_vars, IntVarInfo, int, intValue, IntVars, FDBTInt, *)
	SETPRM_DICT(for_all_float_vars, FloatVarInfo, float, floatValue, FloatVars, FDBTFloat, *)
	SETPRM_DICT(for_all_uint_vars, UIntegerVarInfo, NSUInteger, integerValue, UIntegerVars, FDBTUInt, )
	SETPRM_DICT(for_all_bool_vars, BoolVarInfo, BOOL, boolValue, BoolVars, FDBTBool, )
	for_all_color_vars(^(ColVarInfo *p) {
		NSObject *newValue = dict[p->key];
		if (newValue == nil) return;
		NSUInteger uIntCol; NSColor *newCol = nil;
		if ([newValue isKindOfClass:NSColor.class]) {
			newCol = (NSColor *)newValue;
			uIntCol = col_to_ulong(newCol);
		} else if ([newValue isKindOfClass:NSString.class]) {
			uIntCol = hex_string_to_ulong((NSString *)newValue);
		} else return;
		NSInteger vCol = col_to_ulong(*p->v);
		if (vCol == uIntCol) return;
		if (p->flag & ShouldPostNotification) [postKeys addObject:p->key];
		else *srP = YES;
		orgValues[p->key] = *p->v;
		UInt64 bit = 1 << (self->FDBTCol + (p - ColVars));
		NSInteger fdCol = col_to_ulong(p->fd), udCol = col_to_ulong(p->ud);
		if (uIntCol == fdCol || vCol == fdCol) *fbP |= bit; 
		if (uIntCol == udCol || vCol == udCol) *ubP |= bit; 
		*p->v = (newCol != nil)? newCol : ulong_to_col(uIntCol); });
	NSNumber *num;
	SETENM_DICT(keyColorMode, PTCLColorMode, ptclColorModeFD, ptclColorModeUD, ptclColorMode, FDBTDc)
	SETENM_DICT(keyShapeMode, PTCLShapeMode, ptclShapeModeFD, ptclShapeModeUD, ptclShapeMode, FDBTDm)
	SETENM_DICT(keyObsMode, ObstaclesMode, obsModeFD, obsModeUD, newObsMode, FDBTObs)
	NSString *newValue;
	SETSTR_DICT(keyScrForFullScr, scrForFullScrFD, scrForFullScrUD, scrForFullScr, FDBTFulScr)
	SETSTR_DICT(keyInfoViewConf, infoViewConfFD, infoViewConfUD, infoViewConf, FDBTInfoV)
	NSData *spdColData = dict[keySpeedColors];
	if (spdColData != nil && !spdcol_is_equal_to(spdColData)) {
		orgValues[keySpeedColors] = data_from_spdCols();
		if (spdcol_is_equal_to(spdColFD) || [spdColData isEqualToData:spdColFD])
			fdFlipBits |= 1 << FDBTSpdCol;
		if (spdcol_is_equal_to(spdColUD) || [spdColData isEqualToData:spdColUD])
			udFlipBits |= 1 << FDBTSpdCol;
		spdCols_from_data(spdColData);
		[postKeys addObject:keySpeedColors];
	}
	for (SoundType type = 0; type < NVoices; type ++) {
		SoundSrc *s = &sndData[type];
		NSDictionary *dc = dict[s->key];
		if (dc == nil) continue;
		SoundPrm prm = s->v;
		set_param_from_dict(&prm, dc);
		if (prm_equal(&s->v, &prm)) continue;
		orgValues[s->key] = param_diff_dict(&prm, &s->v);
		UInt64 bit = 1 << s->FDBit;
		if (prm_equal(&prm, &s->fd) || prm_equal(&s->v, &s->fd)) fdFlipBits |= bit;
		if (prm_equal(&prm, &s->ud) || prm_equal(&s->v, &s->ud)) udFlipBits |= bit;
		if (![prm.path isEqualToString:s->v.path])
			change_sound_data(type, prm.path);
	}
	FDBits ^= fdFlipBits;
	UDBits ^= udFlipBits;
	[self adjustControls];
	[undoManager registerUndoWithTarget:self handler:^(id _Nonnull target) {
		[self setParamValuesFromDict:orgValues];
	}];
	for (NSString *key in postKeys) [NSNotificationCenter.defaultCenter
		postNotificationName:key object:NSApp
		userInfo:@{keyCntlPnl:self, keyOldValue:orgValues[key]}];
	if (shouldRedraw) [NSNotificationCenter.defaultCenter
		postNotificationName:keyShouldRedraw object:NSApp];
}
- (NSDictionary *)propertyListOfParamValues {
	NSMutableDictionary *md = NSMutableDictionary.new;
	for_all_int_vars(^(IntVarInfo *p) { md[p->key] = @(*p->v); });
	for_all_float_vars(^(FloatVarInfo *p) { md[p->key] = @(*p->v); });
	for_all_uint_vars(^(UIntegerVarInfo *p) { md[p->key] = @(p->v); });
	for_all_bool_vars(^(BoolVarInfo *p) { md[p->key] = @(p->v); });
	for_all_color_vars(^(ColVarInfo *p) {
		md[p->key] = [NSString stringWithFormat:@"%08lX", col_to_ulong(*p->v)];
	});
	md[keyColorMode] = @(ptclColorMode);
	md[keyShapeMode] = @(ptclShapeMode);
	md[keyObsMode] = @(newObsMode);
	md[keyScrForFullScr] = scrForFullScr;
	md[keyInfoViewConf] = infoViewConf;
	return md;
}

- (IBAction)importSettings:(NSButton *)sender {
	NSOpenPanel *op = NSOpenPanel.new;
	op.allowedContentTypes = @[UTTypeXMLPropertyList];
	[op beginSheetModalForWindow:self.window
		completionHandler:^(NSModalResponse result) {
		if (result != NSModalResponseOK) return;
		NSError *error;
		NSData *data = [NSData dataWithContentsOfURL:op.URL options:0 error:&error];
		if (data == nil) { error_msg(error, self.window); return; }
		NSDictionary *plist = [NSPropertyListSerialization
			propertyListWithData:data options:0 format:NULL error:&error];
		if (plist == nil) { error_msg(error, self.window); return; }
		[self setParamValuesFromDict:plist];
		self->undoManager.actionName = sender.title;
	}];
}
- (IBAction)exportSettings:(id)sender {
	static UTType *settingsUTI = nil;
	if (settingsUTI == nil) settingsUTI =
		[UTType exportedTypeWithIdentifier:
			@"jp.ac.soka.unemi.LearningIsLife-settings"];
	NSSavePanel *sp = NSSavePanel.new;
	sp.allowedContentTypes = @[settingsUTI];
	[sp beginSheetModalForWindow:self.window
		completionHandler:^(NSModalResponse result) {
		if (result != NSModalResponseOK) return;
		NSError *error;
		NSDictionary *plist = [self propertyListOfParamValues];
		NSData *data = [NSPropertyListSerialization
			dataWithPropertyList:plist format:NSPropertyListXMLFormat_v1_0
			options:0 error:&error];
		if (data == nil) { error_msg(error, self.window); return; }
		if (![data writeToURL:sp.URL options:0 error:&error])
			error_msg(error, self.window);
	}];
}
- (IBAction)saveAsUserDefaults:(id)sender {
	save_as_user_defaults();
	UDBits = 0;
	btnSaveAsUD.enabled = btnRevertToUD.enabled = NO;
}
- (void)adjustNParticleDgt { // called when memory allocation failed.
	dgtNParticles.integerValue = NParticles;
	int idx;
	for (idx = 0; IntVars[idx].key != nil; idx ++)
		if (IntVars[idx].v == &NParticles) break;
	[self checkFDBits:FDBTInt + idx
		fd:NParticles == IntVars[idx].fd ud:NParticles == IntVars[idx].ud];
}
- (void)adjustColorMode:(NSDictionary *)info { // called when buffer allocation failed.
	NSNumber *num = info[keyOldValue];
	if (num != nil) {
		ptclColorMode = (PTCLColorMode)num.intValue;
		[ptclColorPopup selectItemAtIndex:ptclColorMode];
		[self checkFDBits:FDBTDc
			fd:ptclColorMode == ptclColorModeFD ud:ptclColorMode == ptclColorModeUD];
	} else [undoManager undo];
}
- (void)adjustShapeMode:(NSDictionary *)info { // called when buffer allocation failed.
	NSNumber *num = info[keyOldValue];
	if (num != nil) {
		ptclShapeMode = (PTCLShapeMode)num.intValue;
		[ptclShapePopup selectItemAtIndex:ptclShapeMode];
		[self checkFDBits:FDBTDm
			fd:ptclShapeMode == ptclShapeModeFD ud:ptclShapeMode == ptclShapeModeUD];
	} else [undoManager undo];
}
//
- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window {
	return (window == self.window)? undoManager : undoMng4SndPnl;
}
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	SEL action = menuItem.action;
	if (action == @selector(exportSettings:)
	 || action == @selector(revertToFactoryDefault:)) return btnExport.enabled;
	return YES;
}
@end
