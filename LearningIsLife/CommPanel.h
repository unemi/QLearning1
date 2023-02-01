//
//  CommPanel.h
//  Learning is Life
//
//  Created by Tatsuo Unemi on 2023/01/30.
//

#import <Cocoa/Cocoa.h>
#import "Comm.h"

NS_ASSUME_NONNULL_BEGIN

@interface CommPanel : NSWindowController <NSWindowDelegate>
@end

extern BOOL start_communication(in_port_t rcvPort, NSInteger sndStepsPerPkt);
extern void stop_communication(void);
extern void check_initial_communication(void);

NS_ASSUME_NONNULL_END
