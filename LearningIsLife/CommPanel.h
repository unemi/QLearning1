//
//  CommPanel.h
//  Learning is Life
//
//  Created by Tatsuo Unemi on 2023/01/30.
//

@import Cocoa;
#import "Comm.h"

NS_ASSUME_NONNULL_BEGIN

@interface CommPanel : NSWindowController <NSWindowDelegate>
@end

extern BOOL start_communication(in_port_t rcvPort, float pktPerSec);
extern void stop_communication(void);
extern void check_initial_communication(void);
extern BOOL communication_is_running(void);
extern ssize_t send_packet(const char *buf, int length);

NS_ASSUME_NONNULL_END
