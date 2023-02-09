//
//  Comm.m
//  Learning is Life
//
//  Created by Tatsuo Unemi on 2023/01/28.
//

#import "Comm.h"
#import <sys/socket.h>
#import <sys/ioctl.h>
#import <arpa/inet.h>
#import <net/if.h>

void in_main_thread(void (^block)(void)) {
	if (NSThread.isMainThread) block();
	else dispatch_async(dispatch_get_main_queue(), block);
}
void error_msg(NSObject *obj, NSWindow *window) {
	NSAlert *alt = NSAlert.new;
	alt.alertStyle = NSAlertStyleCritical;
	if ([obj isKindOfClass:NSError.class]) {
		NSError *error = (NSError *)obj;
		alt.messageText = error.localizedDescription;
		alt.informativeText = [NSString stringWithFormat:@"%@\n%@",
			error.localizedFailureReason, error.localizedRecoverySuggestion];
	} else if ([obj isKindOfClass:NSString.class])
		alt.messageText = (NSString *)obj;
	else alt.messageText = @"Unknown error.";
	if (window == nil) [alt runModal];
	else [alt beginSheetModalForWindow:window
		completionHandler:^(NSModalResponse returnCode) {
	}];
}
void err_msg(NSString *msg, OSStatus err, BOOL isFatal) {
	union { OSStatus e; char c[4]; } u = { .e = EndianU32_NtoB(err) };
	char s[8];
	for (int i = 0; i < 4; i ++) s[i] = (u.c[i] < ' ' || u.c[i] >= 127)? ' ' : u.c[i];
	s[4] = '\0';
	NSAlert *alt = NSAlert.new;
	alt.alertStyle = isFatal? NSAlertStyleCritical : NSAlertStyleWarning;
	alt.messageText = msg;
	alt.informativeText = [NSString stringWithFormat:@"Error code = %s", s];
	[alt runModal];
	if (isFatal) [NSApp terminate:nil];
}
static void unix_error_msg(NSString *msg) {
	err_msg([NSString stringWithFormat:@"%@: %s.", msg, strerror(errno)], errno, NO);
}
@implementation Comm {
	int sndSoc, rcvSoc;	// socket
	in_addr_t myAddr, myBcAddr, senderAddr;
	struct sockaddr_in dstName;
	NSThread *rcvThread;
	void (^sndHandler)(ssize_t);
	void (^rcvHandler)(ssize_t);
}
static NSString *address_string(in_addr_t addr) {
	union { UInt8 c[4]; UInt32 i; } u = { .i = addr }; 
	return [NSString stringWithFormat:@"%d.%d.%d.%d",u.c[0],u.c[1],u.c[2],u.c[3]];
}
- (NSString *)myAddress { return address_string(myAddr); }
- (NSString *)myBroadcastAddress { return address_string(myBcAddr); }
- (NSString *)senderAddress { return address_string(senderAddr); }
- (NSString *)destinationAddress { return address_string(dstName.sin_addr.s_addr); }
- (void)setDestinationAddress:(NSString *)IPv4addr {
	if (!inet_aton(IPv4addr.UTF8String, &dstName.sin_addr))
		err_msg([NSString stringWithFormat:
			@"Failed to interprete IP address \"%@\"", IPv4addr], 0, NO);
}
- (in_port_t)destinationPort { return EndianU16_BtoN(dstName.sin_port); }
- (void)setDestinationPort:(in_port_t)port { dstName.sin_port = EndianU16_NtoB(port); }
- (void)setStatHandlersSnd:(void (^)(ssize_t))sndHdl rcv:(void (^)(ssize_t))rcvHdl {
	sndHandler = sndHdl;
	rcvHandler = rcvHdl;
}
- (ssize_t)send:(const char *)buf length:(int)len {
	@try {
		if (sndSoc < 0) {
			sndSoc = socket(PF_INET, SOCK_DGRAM, IPPROTO_UDP);
			if (sndSoc < 0) @throw @"Couldn't make sender's socket";
			int enable = true;
			if (setsockopt(sndSoc, SOL_SOCKET, SO_BROADCAST, &enable, sizeof(enable)))
				@throw @"Enable broadcast";
		}
		ssize_t n = sendto(sndSoc, buf, len, 0, (struct sockaddr *)&dstName, sizeof(dstName));
		if (n < 0) @throw @"Failed to send data";
		if (sndHandler != nil) sndHandler(n);
		return n;
	} @catch (NSString *msg) { unix_error_msg(msg); }
	return 0;
}
- (void)receiverThread:(id<CommDelegate>)delegate {
	struct sockaddr name;
	char buf[BUFSIZ];
	NSThread *myThread = rcvThread = NSThread.currentThread;
	while (!myThread.cancelled) {
		socklen_t len = sizeof(name);
		ssize_t n = recvfrom(rcvSoc, buf, BUFSIZ, 0, &name, &len);
		if (n == 0) continue;
		senderAddr = ((struct sockaddr_in *)&name)->sin_addr.s_addr;
		[delegate receive:buf length:n];
		if (rcvHandler != nil) rcvHandler(n);
	}
}
#define N_PORTS_TO_TRY 100
- (BOOL)startReceiverWithPort:(in_port_t)rcvPort delegate:(id<CommDelegate>)dlgt {
	int newSoc = -1;
	in_port_t maxPort = rcvPort + N_PORTS_TO_TRY - 1;
	if (maxPort < rcvPort) maxPort = 65535;
	@try {
		if (rcvThread != nil && rcvThread.executing) {
			if (_receiverPort >= rcvPort && _receiverPort < maxPort) return YES;
			[rcvThread cancel];
			if (close(rcvSoc) < 0) @throw @"Couldn't close receiver's socket";
		}
		newSoc = socket(PF_INET, SOCK_DGRAM, IPPROTO_UDP);
		if (newSoc < 0) @throw @"Couldn't make receiver's socket";
		struct sockaddr_in name = {sizeof(name), AF_INET, 0, {INADDR_ANY}};
		for (in_port_t port = rcvPort; port <= maxPort; port ++) {
			name.sin_port = EndianU16_NtoB(port);
			if (bind(newSoc, (struct sockaddr *)&name, sizeof(name)) == noErr)
				{ _receiverPort = port; @throw @YES; }
		} @throw [NSString stringWithFormat:
			@"Port %d - %d seems busy.", rcvPort, maxPort];
	} @catch (NSString *msg) {
		if (newSoc >= 0) close(newSoc);
		err_msg(msg, errno, NO); return NO;
	} @catch (NSNumber *num) {
		rcvSoc = newSoc;
		[NSThread detachNewThreadSelector:
			@selector(receiverThread:) toTarget:self withObject:dlgt];
		_rcvRunning = YES;
		return YES;
	}
	return NO;
}
- (void)stopReceiver {
	if (rcvSoc >= 0 && close(rcvSoc) != noErr)
		unix_error_msg(@"Couldn't close receiver's socket");
	else rcvSoc = -1;
	if (rcvThread != nil && rcvThread.executing) {
		[rcvThread cancel];
		rcvThread = nil;
	}
	_rcvRunning = NO;
}
- (instancetype)init {
	if (!(self = [super init])) return nil;
	rcvSoc = sndSoc = -1;
	int soc = socket(PF_INET, SOCK_DGRAM, IPPROTO_UDP);
	@try {
		if (soc < 0) @throw @"UDP socket";
		struct ifreq ifReq = { "en0" };
		for (int i = 0; i < 8; i ++) {
			ifReq.ifr_name[2] = '0' + i;
			if (ioctl(soc, SIOCGIFADDR, &ifReq) < 0) continue;
			myAddr = ((struct sockaddr_in *)&ifReq.ifr_ifru.ifru_addr)->sin_addr.s_addr;
			break;
		}
		if (myAddr == 0) @throw @"No IP addresses";
		if (ioctl(soc, SIOCGIFNETMASK, &ifReq) < 0) @throw @"Get my netmask";
		in_addr_t mask = ((struct sockaddr_in *)&ifReq.ifr_ifru.ifru_addr)->sin_addr.s_addr;
		myBcAddr = myAddr | ~ mask;
	} @catch (NSString *msg) {
		if (soc >= 0) close(soc);
		unix_error_msg(msg);
		return nil;
	}
	_valid = YES;
	close(soc);
	struct sockaddr_in *np = (struct sockaddr_in *)&dstName;
	np->sin_len = sizeof(struct sockaddr_in);
	np->sin_family = AF_INET;
	np->sin_addr.s_addr = myBcAddr;
	np->sin_port = EndianU16_NtoB((_receiverPort = OSC_PORT));	// default port;
	return self;
}
- (void)invalidate {
	if (!_valid) return;
	[self stopReceiver];
	if (sndSoc >= 0 && close(sndSoc) != noErr)
		unix_error_msg(@"Couldn't close sender's socket");
	_valid = NO;
}
@end
