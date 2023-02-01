//
//  AppDelegate.m
//  LiLCommSim
//
//  Created by Tatsuo Unemi on 2023/01/29.
//

#import "AppDelegate.h"

@interface AppDelegate ()
@property (strong) IBOutlet NSWindow *window;
@end

@implementation AppDelegate {
	Comm *comm;
	IBOutlet NSTextField *txtMyAddr, *txtMyBcAddr,
		*txtDstAddr, *txtMessage, *txtSentInfo,
		*dgtSndPort, *dgtRcvPort;
	IBOutlet NSTextView *monitoredTexts;
}
- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	if ((comm = Comm.new) != nil) {
		txtMyAddr.stringValue = comm.myAddress;
		txtMyBcAddr.stringValue = comm.myBroadcastAddress;
	} else [NSApp terminate:nil];
}
- (void)applicationWillTerminate:(NSNotification *)aNotification {
	[comm invalidate];
}
- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
	return YES;
}
static NSString *com_info(NSString *prepo, NSString *addr, ssize_t length) {
	static NSDateFormatter *dtFmt = nil;
	if (dtFmt == nil) {
		dtFmt = NSDateFormatter.new;
		dtFmt.dateStyle = NSDateFormatterShortStyle;
		dtFmt.timeStyle = NSDateFormatterMediumStyle;
	}
	NSDate *now = NSDate.date;
	CGFloat subSec = now.timeIntervalSinceReferenceDate;
	int msec = (subSec - floor(subSec)) * 1000.;
	return [NSString stringWithFormat:@"%@.%03d, %ld bytes %@ %@",
		[dtFmt stringFromDate:now], msec, length, prepo, addr];
}
- (IBAction)sendMessage:(id)sender {
	if (txtDstAddr.stringValue.length == 0) return;
	comm.destinationAddress = txtDstAddr.stringValue;
	comm.destinationPort = dgtSndPort.intValue;
	NSString *msgStr = txtMessage.stringValue;
	if (msgStr.length > 0) txtSentInfo.stringValue = com_info(@"to",
		comm.destinationAddress,
		[comm send:msgStr.UTF8String length:(int)msgStr.length]);
}
- (IBAction)startReceiver:(id)sender {
	[comm startReceiverWithPort:dgtRcvPort.intValue delegate:self];
	dgtRcvPort.intValue = comm.receiverPort;
}
- (void)receive:(char *)buf length:(ssize_t)length {
	char *myBuf = malloc(length + 1);
	memcpy(myBuf, buf, length);
	for (int i = 0; i < length; i ++) if (myBuf[i] < ' ') myBuf[i] = '?';
	myBuf[length] = '\0';
	NSString *header = com_info(@"from", comm.senderAddress, length);
	NSMutableAttributedString *msg = [NSMutableAttributedString.alloc
		initWithString:[NSString stringWithFormat:@"%@\n%s\n", header, myBuf]];
	[msg addAttribute:NSForegroundColorAttributeName value:NSColor.darkGrayColor
		range:(NSRange){0, header.length}];
	in_main_thread(^{
		[self->monitoredTexts.textStorage appendAttributedString:msg]; });
}
@end
