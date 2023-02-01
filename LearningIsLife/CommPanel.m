//
//  CommPanel.m
//  Learning is Life
//
//  Created by Tatsuo Unemi on 2023/01/30.
//

#import "CommPanel.h"
#import "AppDelegate.h"
#import "MainWindow.h"

static Comm *theComm = nil;
static NSString *keyCommEnabled = @"commEnabled", *keyDstAddress = @"dstAddress",
	*keyDstPort = @"dstPort", *keyRcvPort = @"rcvPort",
	*keyStepsPerPkt = @"sndStepsPerPkt";
static void comm_setup_defaults(void) {
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	NSString *str; NSNumber *num;
	if ((str = [ud objectForKey:keyDstAddress]) != nil)
		theComm.destinationAddress = str;
	if ((num = [ud objectForKey:keyDstPort]) != nil)
		theComm.destinationPort = num.intValue;
}
BOOL start_communication(in_port_t rcvPort, NSInteger sndStepsPerPkt) {
	if (theComm == nil) {
		theComm = Comm.new;
		comm_setup_defaults();
	}
	if (![theComm startReceiverWithPort:rcvPort delegate:theMainWindow]) return NO;
	[theMainWindow setSendersStepsPerPacket:sndStepsPerPkt];
	return YES;
}
void stop_communication(void) {
	[theMainWindow setSendersStepsPerPacket:0];
	[theComm invalidate]; theComm = nil;
}
void check_initial_communication(void) {
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	NSNumber *num;
	if ((num = [ud objectForKey:keyCommEnabled]) == nil) return;
	if (!num.boolValue) return;
	in_port_t rcvPort = (num = [ud objectForKey:keyRcvPort])? num.intValue : OSC_PORT;
	NSInteger spp = (num = [ud objectForKey:keyStepsPerPkt])? num.doubleValue : SND_STEPS_PER_PKT;
	start_communication(rcvPort, spp);
}
@interface CommPanel () {
	IBOutlet NSButton *cboxCommEnabled, *btnDelUsrDflt;
	IBOutlet NSTextField *txtMyAddr, *txtMyBcAdr,
		*txtDstAddr, *txtDstPort, *txtSndInfo, *txtRcvPort, *txtRcvInfo,
		*dgtStepsPerPkt, *dgtSndPPS, *dgtSndBPS, *dgtRcvPPS, *dgtRcvBPS;
	BOOL handlersReady;
}
@end
@implementation CommPanel
- (NSString *)windowNibName { return @"CommPanel"; }
static NSString *bytes_number(CGFloat b) {
	CGFloat exp = (b <= 1.)? 0. : fmin(floor(log10(b) / 3.), 5.);
	NSString *unit = @[@"",@"k",@"M",@"G",@"T",@"P"][(int)exp];
	b /= pow(1e3, exp);
	return [NSString stringWithFormat:
		(b < 10.)? @"%.3f%@" : (b < 100.)? @"%.2f%@" : @"%.1f%@", b, unit];
}
- (void)adjustControls {
	BOOL enabled = (theComm != nil && theComm.valid);
    cboxCommEnabled.state = enabled;
    if (enabled) {
		txtMyAddr.stringValue = theComm.myAddress;
		txtMyBcAdr.stringValue = theComm.myBroadcastAddress;
		txtDstAddr.stringValue = theComm.destinationAddress;
		txtDstPort.intValue = theComm.destinationPort;
		txtRcvPort.intValue = theComm.receiverPort;
	} else txtMyAddr.stringValue = txtMyBcAdr.stringValue = @"";
	dgtSndPPS.doubleValue = dgtRcvPPS.doubleValue = 0.;
	dgtSndBPS.stringValue = dgtRcvBPS.stringValue = bytes_number(0);
}
- (void)windowDidLoad {
    [super windowDidLoad];
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	NSString *str = [ud objectForKey:keyDstAddress]; 
    if (theComm == nil) {
		NSNumber *num;
		txtDstAddr.stringValue = (str != nil)? str : @"";
		txtDstPort.intValue = (num = [ud objectForKey:keyDstPort])?
			num.intValue : OSC_PORT;
		txtRcvPort.intValue = (num = [ud objectForKey:keyRcvPort])?
			num.intValue : OSC_PORT;
		dgtStepsPerPkt.integerValue = (num = [ud objectForKey:keyStepsPerPkt])?
			num.integerValue : SND_STEPS_PER_PKT;
	}
	[self adjustControls];
    btnDelUsrDflt.enabled = (str != nil);
}
- (IBAction)switchEnabled:(NSButton *)cbox {
	if (cbox.state) {
		if (theComm == nil) {
			theComm = Comm.new;
			comm_setup_defaults();
			theComm.destinationAddress = txtDstAddr.stringValue;
			theComm.destinationPort = txtDstPort.intValue;
			txtRcvPort.intValue = OSC_PORT;
		}
		start_communication(txtRcvPort.intValue, dgtStepsPerPkt.integerValue);
	} else stop_communication();
	[self adjustControls];
}
- (IBAction)saveAsDefaults:(id)sender {
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	[ud setBool:cboxCommEnabled.state forKey:keyCommEnabled];
	[ud setObject:txtDstAddr.stringValue forKey:keyDstAddress];
	[ud setInteger:txtDstPort.intValue forKey:keyDstPort];
	[ud setInteger:txtRcvPort.intValue forKey:keyRcvPort];
	[ud setDouble:dgtStepsPerPkt.integerValue forKey:keyStepsPerPkt];
	btnDelUsrDflt.enabled = YES;
}
- (IBAction)deleteDefaults:(id)sender {
	NSAlert *alt = NSAlert.new;
	alt.alertStyle = NSAlertStyleWarning;
	alt.messageText = @"Default settings of the communication are going to removed.";
	alt.informativeText = @"You cannot undo this operation.";
	[alt addButtonWithTitle:@"OK"];
	[alt addButtonWithTitle:@"Cancel"];
	[alt beginSheetModalForWindow:self.window completionHandler:
		^(NSModalResponse returnCode) {
			if (returnCode != NSAlertFirstButtonReturn) return;
			NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
			for (NSString *key in
				@[keyCommEnabled, keyDstAddress, keyDstPort, keyRcvPort, keyStepsPerPkt])
				[ud removeObjectForKey:key];
			self->btnDelUsrDflt.enabled = NO;
	}];
}
//
- (void)windowDidBecomeMain:(NSNotification *)notification {
	if (handlersReady) return;
	[theComm setStatHandlersSnd:^(CGFloat pps, CGFloat bps) {
		in_main_thread(^{
			self->dgtSndPPS.doubleValue = pps;
			self->dgtSndBPS.stringValue = bytes_number(bps);
		});
	} rcv:^(CGFloat pps, CGFloat bps) {
		in_main_thread(^{
			self->dgtRcvPPS.doubleValue = pps;
			self->dgtRcvBPS.stringValue = bytes_number(bps);
		});
	}];
	handlersReady = YES;
}
- (void)windowWillClose:(NSNotification *)notification {
	[theComm setStatHandlersSnd:nil rcv:nil];
	handlersReady = NO;
}
@end
