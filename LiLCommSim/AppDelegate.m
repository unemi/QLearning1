//
//  AppDelegate.m
//  LiLCommSim
//
//  Created by Tatsuo Unemi on 2023/01/29.
//

#import "AppDelegate.h"
#define MAX_RCV_REC 1000

@interface AppDelegate ()
@property (strong) IBOutlet NSWindow *window;
@end
@implementation AppDelegate {
	Comm *comm;
	IBOutlet NSTextField *txtMyAddr, *txtMyBcAddr,
		*txtDstAddr, *txtMessage, *txtSentInfo,
		*dgtSndPort, *dgtRcvPort;
	IBOutlet NSTextView *monitoredTexts;
	NSUInteger rcvCnt, rcvRecLen[MAX_RCV_REC];
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
- (IBAction)startReceiver:(NSButton *)btn {
	if (comm.rcvRunning) {
		[comm stopReceiver];
		btn.title = @"Start";
	} else {
		[comm startReceiverWithPort:dgtRcvPort.intValue delegate:self];
		dgtRcvPort.intValue = comm.receiverPort;
		btn.title = @"Stop";
	}
}
- (IBAction)clearLogText:(id)sender {
	NSTextStorage *tst = monitoredTexts.textStorage;
	[tst deleteCharactersInRange:(NSRange){0, tst.length}];
	rcvCnt = 0;
}
- (void)receive:(char *)buf length:(ssize_t)length {
	if (length <= 0) return;
	NSString *header = com_info(@"from", comm.senderAddress, length), *content;
	BOOL nullp = NO;
	long k;
	for (k = 0; k < length; k ++)
		if (buf[k] == '\0' || buf[k] == ',') { nullp = YES; break; }
	if (!nullp) {
		char *myBuf = malloc(length * 3 + 1);
		int j = 0;
		for (int i = 0; i < length; i ++) {
			if (buf[i] < ' ') {
				sprintf(myBuf + j, "%%%02X", buf[i]);
				j += 3;
			} else if (buf[i] == '%') {
				myBuf[j ++] = '%'; myBuf[j ++] = '%';
			} else myBuf[j ++] = buf[i];
		}
		myBuf[j] = '\0';
		content = [NSString stringWithUTF8String:myBuf];
		free(myBuf);
	} else {
		NSString *path = [NSString.alloc initWithBytes:buf length:k
			encoding:NSUTF8StringEncoding];
		for (; k < length; k ++) if (buf[k] == ',') break;
		char *types = buf + (++ k);
		int nArgs = 0;
		for (; k < length; k ++, nArgs ++) if (buf[k] == '\0') break;
		char *args = buf + (k / 4 + 1) * 4;
		NSMutableString *argsStr = [NSMutableString stringWithString:path];
		union { SInt32 i; Float32 f; } x;
		NSString *str;
		for (int i = 0; i < nArgs; i ++) switch (types[i]) {
			case 'f': x.i = EndianS32_BtoN(((SInt32 *)args)[0]);
				[argsStr appendFormat:@",%.3f", x.f]; args += 4; break;
			case 'i': [argsStr appendFormat:@",%d", EndianS32_BtoN(((SInt32 *)args)[0])];
				args += 4; break;
			case 's': str = [NSString stringWithUTF8String:args];
				[argsStr appendFormat:@",\"%@\"", str];
				args += (str.length / 4 + 1) * 4; break;
		}
		content = argsStr;
	}
	NSMutableAttributedString *msg = [NSMutableAttributedString.alloc
		initWithString:[NSString stringWithFormat:@"%@%@\n%@",
			(rcvCnt > 0)? @"\n" : @"", header, content]];
	[msg addAttribute:NSForegroundColorAttributeName value:NSColor.darkGrayColor
		range:(NSRange){(rcvCnt > 0)? 1 : 0, header.length}];
	BOOL limit = (rcvCnt >= MAX_RCV_REC);
	if (!limit) rcvRecLen[rcvCnt ++] = msg.length;
	NSTextView *txv = monitoredTexts;
	NSUInteger *len = rcvRecLen;
	in_main_thread(^{
		if (limit) {
			[txv.textStorage deleteCharactersInRange:(NSRange){0, len[0]}];
			memmove(len, len + 1, sizeof(NSUInteger) * (MAX_RCV_REC - 1));
			len[MAX_RCV_REC - 1] = msg.length;
		}
		[txv.textStorage appendAttributedString:msg];
		CGFloat h = txv.textStorage.size.height - txv.superview.bounds.size.height;
		if (h > 0.) [(NSClipView *)txv.superview scrollToPoint:(NSPoint){0., h}];
	});
}
@end
