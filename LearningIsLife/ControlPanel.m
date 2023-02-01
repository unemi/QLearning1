//
//  ControlPanel.m
//  Learning is Life
//
//  Created by Tatsuo Unemi on 2023/02/01.
//

#import "ControlPanel.h"
#import "AppDelegate.h"
#import "MainWindow.h"
#import "Display.h"
#import "MySound.h"
@import UniformTypeIdentifiers;

static BOOL prm_equal(SoundPrm *a, SoundPrm *b) {
	return [a->path isEqualToString:b->path] &&
		a->mmin == b->mmin && a->mmax == b->mmax && a->vol == b->vol;
}
static void setup_screen_menu(NSPopUpButton *popup) {
	NSArray<NSScreen *> *screens = NSScreen.screens;
	NSInteger nItems = popup.numberOfItems;
	if (screens.count > 1) {
		[popup itemAtIndex:0].title = scrForFullScrFD;
		for (NSInteger i = 0; i < screens.count; i ++) {
			NSString *name = screens[i].localizedName;
			if (i + 1 < nItems) [popup itemAtIndex:i + 1].title = name;
			else [popup addItemWithTitle:name];
		}
		for (NSInteger i = nItems - 1; i > screens.count; i --)
			[popup removeItemAtIndex:i];
		NSMenuItem *item = [popup itemWithTitle:scrForFullScr];
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
static void displayReconfigCB(CGDirectDisplayID display,
	CGDisplayChangeSummaryFlags flags, void *userInfo) {
	if ((flags & kCGDisplayBeginConfigurationFlag) != 0 ||
		(flags & (kCGDisplayAddFlag | kCGDisplayRemoveFlag |
		kCGDisplayEnabledFlag | kCGDisplayDisabledFlag)) == 0) return;
	in_main_thread(^{
		setup_screen_menu((__bridge NSPopUpButton *)userInfo);
	});
}

@implementation ControlPanel {
	NSArray<NSColorWell *> *colWels;
	NSArray<NSTextField *> *ivDgts, *fvDgts, *uvDgts, *sndTxts;
	NSArray<NSButton *> *colBtns, *dmBtns, *boolVBtns, *editBtns, *playBtns;
	NSArray<NSControl *> *sndContrls;
	NSSound *soundNowPlaying;
	NSUndoManager *undoManager, *undoMng4SndPnl;
	SoundType playingSoundType, openingSoundType;
	SoundPrm orgSndParams;
	int FDBTCol, FDBTInt, FDBTFloat, FDBTUInt, FDBTBool, FDBTDc,
		FDBTDm, FDBTObs, FDBTFulScr;
	UInt64 FDBits;
}
- (NSString *)windowNibName { return @"ControlPanel"; }
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
- (void)adjustControls {
	for (NSColorWell *cwl in colWels) cwl.color = *ColVars[cwl.tag].v;
	for (NSTextField *dgt in ivDgts) dgt.intValue = *IntVars[dgt.tag].v;
	for (NSTextField *dgt in fvDgts) dgt.floatValue = *FloatVars[dgt.tag].v;
	for (NSTextField *dgt in uvDgts) dgt.integerValue = UIntegerVars[dgt.tag].v;
	for (NSButton *btn in boolVBtns) btn.state = BoolVars[btn.tag].v;
	for (NSButton *btn in colBtns) btn.state = (ptclColorMode == btn.tag);
	for (NSButton *btn in dmBtns) btn.state = (ptclShapeMode == btn.tag);
	dgtStrokeWidth.enabled = (ptclShapeMode != PTCLbyLines);
	[obsPopUp selectItemAtIndex:obstaclesMode];
	[screenPopUp selectItemWithTitle:scrForFullScr];
	[self adjustSoundsCtrls];
	dgtCoolingRate.enabled = (MAX_STEPS == 0);
	btnRevertToFD.enabled = btnExport.enabled = (FDBits != 0);
}
#define SETUP_CNTRL(b,class,list,fn,var,ref,act)	b = (int)bit; tag = 0;\
	for (class *ctr in list) {\
		if (fn(var ref[tag].v) != fn(ref[tag].fd)) FDBits |= 1 << bit;\
		ctr.target = self;\
		ctr.action = @selector(act:);\
		ctr.tag = tag ++; bit ++;\
	}
#define SETUP_RADIOBTN(b,var,fd,list,act)	b = (int)(bit ++); tag = 0;\
	if (var != fd) FDBits |= 1 << b;\
	for (NSButton *btn in list) {\
		btn.target = self;\
		btn.action = @selector(act:);\
		btn.tag = tag ++;\
	}
- (void)windowDidLoad {
	[super windowDidLoad];
	if (self.window == nil) return;
	undoManager = NSUndoManager.new;
	setup_screen_menu(screenPopUp);
	CGError error = CGDisplayRegisterReconfigurationCallback
		(displayReconfigCB, (__bridge void *)screenPopUp);
	if (error != kCGErrorSuccess)
		NSLog(@"CGDisplayRegisterReconfigurationCallback error = %d", error);
	colWels = @[cwlBackground, cwObstacles, cwAgent, cwGridLines, cwSymbols, cwParticles];
	ivDgts = @[dgtMemSize, dgtMemTrials, dgtNParticles, dgtLifeSpan];
	fvDgts = @[dgtT0, dgtT1, dgtCoolingRate, dgtInitQValue, dgtGamma, dgtAlpha,
		dgtStpPS, dgtMass, dgtFriction, dgtStrokeLength, dgtStrokeWidth, dgtMaxSpeed];
	uvDgts = @[dgtMaxSteps, dgtMaxGoalCnt];
	boolVBtns = @[cBoxSounds, cboxStartFullScr, cboxRecordImages, cBoxShowFPS];
	colBtns = @[btnColConst, btnColAngle, btnColSpeed];
	dmBtns = @[btnDrawByRects, btnDrawByTriangles, btnDrawByLines];
	sndTxts = @[txtBump, txtGaol, txtGood, txtBad, txtAmbience];
	editBtns = @[editBump, editGoal, editGood, editBad, editAmbience];
	playBtns = @[playBump, playGoal, playGood, playBad, playAmbience];
	sndContrls = @[sndPMVal, sndPMValSld, sndPVolSld, sndPMSetMinBtn, sndPMSetMaxBtn];
	NSInteger bit = 0, tag;
	SETUP_CNTRL(FDBTCol, NSColorWell, colWels, col_to_ulong, *, ColVars, chooseColorWell)
	SETUP_CNTRL(FDBTInt, NSTextField, ivDgts, , *, IntVars, changeIntValue)
	SETUP_CNTRL(FDBTFloat, NSTextField, fvDgts, , *, FloatVars, changeFloatValue)
	SETUP_CNTRL(FDBTUInt, NSTextField, uvDgts, , , UIntegerVars, changeUIntegerValue)
	SETUP_CNTRL(FDBTBool, NSButton, boolVBtns, , , BoolVars, switchBoolValue)
	SETUP_RADIOBTN(FDBTDc, ptclColorMode, ptclColorModeFD, colBtns, chooseColorMode)
	SETUP_RADIOBTN(FDBTDm, ptclShapeMode, ptclShapeModeFD, dmBtns, chooseShapeMode)
	FDBTObs = (int)bit;
	if (obstaclesMode != obsModeFD) FDBits |= 1 << bit;
	FDBTFulScr = (int)(++ bit);
	if (scrForFullScr != scrForFullScrFD) FDBits |= 1 << bit;
	for (SoundType type = 0; type < NVoices; type ++) {
		SoundSrc *s = &sndData[type];
		s->FDBit = (int)(++ bit);
		if (!prm_equal(&s->v, &s->fd)) FDBits |= 1 << bit;
	}
	[self adjustControls];
}
- (void)checkFDBits:(NSInteger)bitPosition cond:(BOOL)cond {
	UInt64 mask = 1ULL << bitPosition;
	if (cond) FDBits &= ~ mask;
	else FDBits |= mask;
	btnRevertToFD.enabled = btnExport.enabled = (FDBits != 0);
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
		cond:newValUlong == col_to_ulong(info->fd)];
	[NSNotificationCenter.defaultCenter postNotificationName:
		(info->flag & ShouldPostNotification)? info->key : keyShouldRedraw object:NSApp];
}
- (IBAction)changeIntValue:(NSTextField *)dgt {
	IntVarInfo *info = &IntVars[dgt.tag];
	int *var = info->v, newValue = dgt.intValue;
	if (*var == newValue) return;
	int orgValue = *var;
	[undoManager registerUndoWithTarget:self handler:^(id _Nonnull target) {
		dgt.intValue = orgValue;
		[dgt sendAction:dgt.action to:target];
	}];
	undoManager.actionName = NSLocalizedString(info->key, nil);
	*var = newValue;
	[self checkFDBits:FDBTInt + dgt.tag cond:newValue == info->fd];
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
	[self checkFDBits:FDBTFloat + dgt.tag cond:newValue == info->fd];
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
	[self checkFDBits:FDBTUInt + dgt.tag cond:newValue == info->fd];
	if (dgt.tag == MAX_STEPS_TAG)
		dgtCoolingRate.enabled = (MAX_STEPS == 0);
	[NSNotificationCenter.defaultCenter
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
	[self checkFDBits:FDBTBool + btn.tag cond:newValue == info->fd];
	if (info->flag & ShouldPostNotification)
		[NSNotificationCenter.defaultCenter
			postNotificationName:info->key object:NSApp];
	if ([info->key isEqualToString:@"sounds"]) [self adjustSoundsCtrls];
}
- (IBAction)chooseColorMode:(NSButton *)btn {
	PTCLColorMode newValue = (PTCLColorMode)btn.tag;
	if (ptclColorMode == newValue) return;
	NSButton *orgBtn = colBtns[ptclColorMode];
	[undoManager registerUndoWithTarget:self handler:^(id _Nonnull target) {
		[orgBtn performClick:nil];
	}];
	undoManager.actionName = NSLocalizedString(keyColorMode, nil);
	ptclColorMode = newValue;
	[self checkFDBits:FDBTDc cond:newValue == ptclColorModeFD];
	[NSNotificationCenter.defaultCenter postNotificationName:
		keyColorMode object:NSApp userInfo:@{keyCntlPnl:self}];
}
- (IBAction)chooseShapeMode:(NSButton *)btn {
	PTCLShapeMode newValue = (PTCLShapeMode)btn.tag;
	if (ptclShapeMode == newValue) return;
	NSButton *orgBtn = dmBtns[ptclShapeMode];
	[undoManager registerUndoWithTarget:self handler:^(id _Nonnull target) {
		[orgBtn performClick:nil];
	}];
	undoManager.actionName = NSLocalizedString(keyShapeMode, nil);
	ptclShapeMode = newValue;
	dgtStrokeWidth.enabled = (newValue != PTCLbyLines);
	[self checkFDBits:FDBTDm cond:newValue == ptclShapeModeFD];
	[NSNotificationCenter.defaultCenter postNotificationName:
		keyShapeMode object:NSApp userInfo:@{keyCntlPnl:self}];
}
- (IBAction)chooseObstaclesMode:(NSPopUpButton *)popUp {
	ObstaclesMode newValue = (ObstaclesMode)popUp.indexOfSelectedItem;
	if (obstaclesMode == newValue) return;
	ObstaclesMode orgValue = obstaclesMode;
	[undoManager registerUndoWithTarget:self handler:^(id _Nonnull target) {
		[popUp selectItemAtIndex:orgValue];
		[popUp sendAction:popUp.action to:popUp.target];
	}];
	undoManager.actionName = NSLocalizedString(keyObsMode, nil);
	obstaclesMode = newValue;
	[NSNotificationCenter.defaultCenter postNotificationName:keyObsMode object:NSApp];
}
- (IBAction)chooseScreenForFullScreen:(NSPopUpButton *)popUp {
	NSString *newValue = popUp.titleOfSelectedItem;
	if ([scrForFullScr isEqualToString:newValue]) return;
	NSString *orgValue = scrForFullScr;
	[undoManager registerUndoWithTarget:self handler:^(id _Nonnull target) {
		if ([popUp itemWithTitle:orgValue] != nil)
			[popUp selectItemWithTitle:orgValue];
		else [popUp selectItemAtIndex:0];
		[popUp sendAction:popUp.action to:target];
	}];
	undoManager.actionName = NSLocalizedString(keyScrForFullScr, nil);
	scrForFullScr = newValue;
	[self checkFDBits:FDBTFulScr cond:newValue == scrForFullScrFD];
}
- (void)setSoundType:(SoundType)type prm:(SoundPrm)prm {
	SoundSrc *s = &sndData[type];
	SoundPrm orgPrm = s->v;
	change_sound_data(type, prm.path);
	s->v = prm;
	sndTxts[type].attributedStringValue = sound_info(type);
	[self checkFDBits:sndData[type].FDBit cond:prm_equal(&orgPrm, &prm)];
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
- (IBAction)revertToFactoryDefault:(id)sender {
	NSMutableDictionary *md = NSMutableDictionary.new;
	for_all_int_vars(^(IntVarInfo *p) {
		if (*p->v != p->fd) md[p->key] = @(p->fd);
	});
	for_all_float_vars(^(FloatVarInfo *p) {
		if (*p->v != p->fd) md[p->key] = @(p->fd);
	});
	for_all_uint_vars(^(UIntegerVarInfo *p) {
		if (p->v != p->fd) md[p->key] = @(p->fd);
	});
	for_all_bool_vars(^(BoolVarInfo *p) {
		if (p->v != p->fd) md[p->key] = @(p->fd);
	});
	for_all_color_vars(^(ColVarInfo *p) {
		if (col_to_ulong(*p->v) != col_to_ulong(p->fd)) md[p->key] = p->fd;
	});
	if (ptclColorMode != ptclColorModeFD) md[keyColorMode] = @(ptclColorModeFD);
	if (ptclShapeMode != ptclShapeModeFD) md[keyShapeMode] = @(ptclShapeModeFD);
	if (obstaclesMode != obsModeFD) md[keyObsMode] = @(obsModeFD);
	if (![scrForFullScr isEqualToString:scrForFullScrFD])
		md[keyScrForFullScr] = scrForFullScrFD;
	for (SoundType type = 0; type < NVoices; type ++) {
		SoundSrc *s = &sndData[type];
		if (!prm_equal(&s->v, &s->fd)) md[s->key] = param_diff_dict(&s->v, &s->fd);
	}
	[self setParamValuesFromDict:md];
	undoManager.actionName = btnRevertToFD.title;
}
- (void)setParamValuesFromDict:(NSDictionary *)dict {
	NSMutableArray<NSString *> *postKeys = NSMutableArray.new;
	NSMutableDictionary *orgValues = NSMutableDictionary.new;
	BOOL shouldRedraw = NO, *srP = &shouldRedraw;
	UInt64 fdFlipBits = 0, *fbP = &fdFlipBits;
	for_all_int_vars(^(IntVarInfo *p) {
		NSNumber *num = dict[p->key]; if (num == nil) return;
		int newValue = num.intValue; if (*p->v == newValue) return;
		if (p->flag & ShouldPostNotification) [postKeys addObject:p->key];
		orgValues[p->key] = @(*p->v);
		if (newValue == p->fd || *p->v == p->fd)
			*fbP |= 1 << (self->FDBTInt + (p - IntVars));
		*p->v = newValue;
	});
	for_all_float_vars(^(FloatVarInfo *p) {
		NSNumber *num = dict[p->key]; if (num == nil) return;
		float newValue = num.floatValue; if (*p->v == newValue) return;
		if (p->flag & ShouldRedrawScreen) *srP = YES;
		orgValues[p->key] = @(*p->v);
		if (newValue == p->fd || *p->v == p->fd)
			*fbP |= 1 << (self->FDBTFloat + (p - FloatVars));
		*p->v = newValue;
	});
	for_all_uint_vars(^(UIntegerVarInfo *p) {
		NSNumber *num = dict[p->key]; if (num == nil) return;
		NSUInteger newValue = num.integerValue; if (p->v == newValue) return;
		[postKeys addObject:p->key];
		orgValues[p->key] = @(p->v);
		if (newValue == p->fd || p->v == p->fd)
			*fbP |= 1 << (self->FDBTUInt + (p - UIntegerVars));
		p->v = newValue;
	});
	for_all_bool_vars(^(BoolVarInfo *p) {
		NSNumber *num = dict[p->key]; if (num == nil) return;
		BOOL newValue = num.boolValue; if (p->v == newValue) return;
		if (p->flag & ShouldPostNotification) [postKeys addObject:p->key];
		orgValues[p->key] = @(p->v);
		if (newValue == p->fd || p->v == p->fd)
			*fbP |= 1 << (self->FDBTBool + (p - BoolVars));
		p->v = newValue;
	});
	for_all_color_vars(^(ColVarInfo *p) {
		NSObject *newValue = dict[p->key];
		if (newValue == nil) return;
		NSUInteger uIntCol; NSColor *newCol = nil;
		if ([newValue isKindOfClass:NSColor.class]) {
			newCol = (NSColor *)newValue;
			uIntCol = col_to_ulong(newCol);
		} else if ([newValue isKindOfClass:NSString.class]) {
			uIntCol = hex_string_to_uint((NSString *)newValue);
		} else return;
		if (col_to_ulong(*p->v) == uIntCol) return;
		if (p->flag & ShouldPostNotification) [postKeys addObject:p->key];
		else *srP = YES;
		orgValues[p->key] = *p->v;
		NSInteger fdCol = col_to_ulong(p->fd);
		if (uIntCol == fdCol || col_to_ulong(*p->v) == fdCol)
			*fbP |= 1 << (self->FDBTCol + (p - ColVars));
		*p->v = (newCol != nil)? newCol : ulong_to_col(uIntCol); });
	NSNumber *num;
	if ((num = dict[keyColorMode]) != nil) {
		PTCLColorMode newValue = num.intValue;
		if (ptclColorMode != newValue) {
			orgValues[keyColorMode] = @(ptclColorMode);
			if (ptclColorMode == ptclColorModeFD || newValue == ptclColorModeFD)
				*fbP |= 1 << FDBTDc;
			ptclColorMode = newValue;
			[postKeys addObject:keyColorMode];
		}
	}
	if ((num = dict[keyShapeMode]) != nil) {
		PTCLShapeMode newValue = num.intValue;
		if (ptclShapeMode != newValue) {
			orgValues[keyShapeMode] = @(ptclShapeMode);
			if (ptclShapeMode == ptclShapeModeFD || newValue == ptclShapeModeFD)
				fdFlipBits |= 1 << FDBTDm;
			ptclShapeMode = newValue;
			[postKeys addObject:keyShapeMode];
		}
	}
	if ((num = dict[keyObsMode]) != nil) {
		ObstaclesMode newValue = num.intValue;
		if (obstaclesMode != newValue) {
			orgValues[keyObsMode] = @(obstaclesMode);
			if (obstaclesMode == obsModeFD || newValue == obsModeFD)
				fdFlipBits |= 1 << FDBTObs;
			obstaclesMode = newValue;
			[postKeys addObject:keyObsMode];
		}
	}
	NSString *newValue = dict[keyScrForFullScr];
	if (newValue != nil && ![scrForFullScr isEqualToString:newValue]) {
		orgValues[keyScrForFullScr] = scrForFullScr;
		if (scrForFullScr == scrForFullScrFD || newValue == scrForFullScrFD)
			fdFlipBits |= 1 << FDBTFulScr;
		scrForFullScr = newValue;
	}
	for (SoundType type = 0; type < NVoices; type ++) {
		SoundSrc *s = &sndData[type];
		NSDictionary *dc = dict[s->key];
		if (dc == nil) continue;
		SoundPrm prm = s->v;
		if ((newValue = dc[@"path"]) != nil) prm.path = newValue;
		if ((num = dc[@"mmin"]) != nil) prm.mmin = num.floatValue;
		if ((num = dc[@"mmax"]) != nil) prm.mmax = num.floatValue;
		if ((num = dc[@"vol"]) != nil) prm.vol = num.floatValue;
		if (prm_equal(&s->v, &prm)) continue;
		orgValues[s->key] = param_diff_dict(&prm, &s->v);
		if (prm_equal(&prm, &s->fd) || prm_equal(&s->v, &s->fd))
			fdFlipBits |= 1 << s->FDBit;
		if (![prm.path isEqualToString:s->v.path])
			change_sound_data(type, prm.path);
	}
	FDBits ^= fdFlipBits;
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
	md[keyObsMode] = @(obstaclesMode);
	md[keyScrForFullScr] = scrForFullScr;
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
- (void)adjustNParticleDgt { // called when memory allocation failed.
	dgtNParticles.integerValue = NParticles;
	int idx;
	for (idx = 0; IntVars[idx].key != nil; idx ++)
		if (IntVars[idx].v == &NParticles) break;
	[self checkFDBits:FDBTInt + idx cond:NParticles == IntVars[idx].fd];
}
- (void)adjustColorMode:(NSDictionary *)info { // called when buffer allocation failed.
	NSNumber *num = info[keyOldValue];
	if (num != nil) {
		ptclColorMode = (PTCLColorMode)num.intValue;
		for (NSButton *btn in colBtns) btn.state = (ptclColorMode == btn.tag);
		[self checkFDBits:FDBTDc cond:ptclColorMode == ptclColorModeFD];
	} else [undoManager undo];
}
- (void)adjustShapeMode:(NSDictionary *)info { // called when buffer allocation failed.
	NSNumber *num = info[keyOldValue];
	if (num != nil) {
		ptclShapeMode = (PTCLShapeMode)num.intValue;
		for (NSButton *btn in dmBtns) btn.state = (ptclShapeMode == btn.tag);
		[self checkFDBits:FDBTDm cond:ptclShapeMode == ptclShapeModeFD];
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
