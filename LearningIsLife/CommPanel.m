//
//  CommPanel.m
//  Learning is Life
//
//  Created by Tatsuo Unemi on 2023/01/30.
//

#import "CommPanel.h"
#import "MainWindow.h"

static Comm *theComm = nil;
static NSString *keyCommEnabled = @"commEnabled", *keyDstAddress = @"dstAddress",
	*keyDstPort = @"dstPort", *keyRcvPort = @"rcvPort",
	*keyPktPerSec = @"dstPktPerSec";
static void comm_setup_defaults(void) {
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	NSString *str; NSNumber *num;
	if ((str = [ud objectForKey:keyDstAddress]) != nil)
		theComm.destinationAddress = str;
	if ((num = [ud objectForKey:keyDstPort]) != nil)
		theComm.destinationPort = num.intValue;
}
BOOL start_communication(in_port_t rcvPort, float pktPerSec) {
	if (theComm == nil) {
		theComm = Comm.new;
		comm_setup_defaults();
	}
	if (![theComm startReceiverWithPort:rcvPort delegate:theMainWindow]) return NO;
	[theMainWindow setSendersPacketsPerSec:pktPerSec];
	return YES;
}
void stop_communication(void) {
	[theMainWindow setSendersPacketsPerSec:0];
	[theComm invalidate]; theComm = nil;
}
void check_initial_communication(void) {
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	NSNumber *num;
	if ((num = [ud objectForKey:keyCommEnabled]) == nil) return;
	if (!num.boolValue) return;
	in_port_t rcvPort = (num = [ud objectForKey:keyRcvPort])? num.intValue : OSC_PORT;
	float pps = (num = [ud objectForKey:keyPktPerSec])? num.floatValue : DST_PKT_PER_SEC;
	start_communication(rcvPort, pps);
}
BOOL communication_is_running(void) {
	return (theComm != nil && theComm.valid);
}
ssize_t send_packet(const char *buf, int length) {
	if (theComm == nil || !theComm.valid) return 0;
	return [theComm send:buf length:length];
}
typedef struct {
	unsigned long prevTime;
	CGFloat pps, bps;
} TraficMeasure;
static void measure_trafic(TraficMeasure *tm, ssize_t nBytes) {
	unsigned long t = current_time_us(), interval = t - tm->prevTime;
	CGFloat a = fmin(1., interval / 1e6);
	tm->pps += (1e6 / interval - tm->pps) * a;
	tm->bps += (nBytes * 1e6 / interval - tm->bps) * a;
	tm->prevTime = t;
}
@interface CommPanel () {
	IBOutlet NSButton *cboxCommEnabled, *btnDelUsrDflt;
	IBOutlet NSTextField *txtMyAddr, *txtMyBcAdr,
		*txtDstAddr, *txtDstPort, *txtSndInfo, *txtRcvPort, *txtRcvInfo,
		*dgtPktPerSec, *dgtSndPPS, *dgtSndBPS, *dgtRcvPPS, *dgtRcvBPS;
	TraficMeasure sndTM, rcvTM;
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
	} else txtMyAddr.stringValue = txtMyBcAdr.stringValue = @"";
	if (theComm != nil) {
		txtDstAddr.stringValue = theComm.destinationAddress;
		txtDstPort.intValue = theComm.destinationPort;
		txtRcvPort.intValue = theComm.receiverPort;
	}
	dgtSndPPS.doubleValue = dgtRcvPPS.doubleValue = 0.;
	dgtSndBPS.stringValue = dgtRcvBPS.stringValue = bytes_number(0);
}
- (void)windowDidLoad {
    [super windowDidLoad];
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	NSString *str = [ud objectForKey:keyDstAddress]; 
	NSNumber *num;
    if (theComm == nil) {
		txtDstAddr.stringValue = (str != nil)? str : @"";
		txtDstPort.intValue = (num = [ud objectForKey:keyDstPort])?
			num.intValue : OSC_PORT;
		txtRcvPort.intValue = (num = [ud objectForKey:keyRcvPort])?
			num.intValue : OSC_PORT;
	}
	dgtPktPerSec.floatValue = (num = [ud objectForKey:keyPktPerSec])?
		num.floatValue : DST_PKT_PER_SEC;
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
		start_communication(txtRcvPort.intValue, dgtPktPerSec.floatValue);
	} else stop_communication();
	[self adjustControls];
}
- (IBAction)saveAsDefaults:(id)sender {
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	[ud setBool:cboxCommEnabled.state forKey:keyCommEnabled];
	[ud setObject:txtDstAddr.stringValue forKey:keyDstAddress];
	[ud setInteger:txtDstPort.intValue forKey:keyDstPort];
	[ud setInteger:txtRcvPort.intValue forKey:keyRcvPort];
	[ud setFloat:dgtPktPerSec.floatValue forKey:keyPktPerSec];
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
				@[keyCommEnabled, keyDstAddress, keyDstPort, keyRcvPort, keyPktPerSec])
				[ud removeObjectForKey:key];
			self->btnDelUsrDflt.enabled = NO;
	}];
}
- (NSString *)commInfoString:(ssize_t)nBytes
	propo:(NSString *)propo addr:(NSString *)addr {
	static NSDateFormatter *dtFmt = nil;
	if (dtFmt == nil) {
		dtFmt = NSDateFormatter.new;
		dtFmt.dateStyle = NSDateFormatterNoStyle;
		dtFmt.timeStyle = NSDateFormatterShortStyle;
	}
	NSDate *now = NSDate.now;
	NSTimeInterval msec = now.timeIntervalSinceReferenceDate;
	msec = (msec - floor(msec)) * 1000.;
	return [NSString stringWithFormat:@"%@.%03.0f: %ld bytes %@ %@.",
		[dtFmt stringFromDate:now], msec, nBytes, propo, addr];
}
//
- (void)windowDidBecomeMain:(NSNotification *)notification {
	if (handlersReady) return;
	[theComm setStatHandlersSnd:^(ssize_t nBytes) {
		measure_trafic(&self->sndTM, nBytes);
		NSString *bpsStr = bytes_number(self->sndTM.bps), *info =
			[self commInfoString:nBytes propo:@"to" addr:theComm.destinationAddress];
		in_main_thread(^{
			self->dgtSndPPS.doubleValue = self->sndTM.pps;
			self->dgtSndBPS.stringValue = bpsStr;
			self->txtSndInfo.stringValue = info;
		});
	} rcv:^(ssize_t nBytes) {
		measure_trafic(&self->rcvTM, nBytes);
		NSString *bpsStr = bytes_number(self->rcvTM.bps), *info =
			[self commInfoString:nBytes propo:@"from" addr:theComm.senderAddress];
		in_main_thread(^{
			self->dgtRcvPPS.doubleValue = self->rcvTM.pps;
			self->dgtRcvBPS.stringValue = bpsStr;
			self->txtRcvInfo.stringValue = info;
		});
	}];
	handlersReady = YES;
}
- (void)windowWillClose:(NSNotification *)notification {
	[theComm setStatHandlersSnd:nil rcv:nil];
	handlersReady = NO;
}
@end
