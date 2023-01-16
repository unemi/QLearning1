//
//  AppDelegateS.m
//  MySoundTest4QL1
//
//  Created by Tatsuo Unemi on 2023/01/16.
//

#import "AppDelegate.h"
#import "MySound.h"

SoundSrc sndData[] = {
	{ @"Cave and Wind.mp3", @"iMovie", 2 }
};
static SoundEnvParam params[NGridW];

void err_msg(NSString *msg, OSStatus err, BOOL isFatal) {
	NSAlert *alt = NSAlert.new;
	alt.alertStyle = isFatal? NSAlertStyleCritical : NSAlertStyleWarning;
	alt.messageText = msg;
	alt.informativeText = [NSString stringWithFormat:@"Error code = %d", err];
	[alt runModal];
	if (isFatal) [NSApp terminate:nil];
}

@interface AppDelegate () {
	IBOutlet NSTextField *ampDgt, *pitchDgt, *bandDgt;
	IBOutlet NSSlider *ampSld, *pitchSld, *bandSld;
	NSArray<NSTextField *> *dgts;
	NSArray<NSSlider *> *slds;
}
@property (strong) IBOutlet NSWindow *window;
@end

@implementation AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	dgts = @[ampDgt, pitchDgt, bandDgt];
	slds = @[ampSld, pitchSld, bandSld];
	for (NSInteger i = 0; i < dgts.count; i ++) {
		NSControl *c1 = dgts[i], *c2 = slds[i];
		c1.target = c2.target = self;
		c1.action = c2.action = @selector(changeValue:);
		c1.tag = c2.tag = i;
	}
	ampDgt.doubleValue = ampSld.doubleValue = 1.;
	pitchDgt.doubleValue = pitchSld.doubleValue = 0.;
	for (NSInteger i = 0; i < NGridW; i ++)
		params[i].amp = params[i].pitchShift = 1.;
	init_audio_out(sndData, 1);
	set_audio_env_params(params);
	start_audio_out();
}
- (IBAction)changeValue:(NSControl *)control {
	CGFloat value = control.doubleValue;
	if ([control isKindOfClass:NSTextField.class])
		slds[control.tag].doubleValue = value;
	else dgts[control.tag].doubleValue = value;
	if (control.tag == 0)
		for (NSInteger i = 0; i < NGridW; i ++) params[i].amp = value;
	else for (NSInteger i = 0; i < NGridW; i ++)
		params[i].pitchShift = pow(2., value);
	set_audio_env_params(params);
}
@end
