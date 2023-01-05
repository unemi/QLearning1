//
//  RecordView.m
//  QLearning1
//
//  Created by Tatsuo Unemi on 2023/01/05.
//

#import "RecordView.h"
#import "AppDelegate.h"
#import "Display.h"
#import "MyViewForCG.h"

@implementation RecordView {
	NSMutableArray<NSImageRep *> *images;
	MyViewForCG *view;
	NSDateFormatter *dtFmt;
}
- (NSSize)imageSize {
	CGFloat w = self.bounds.size.width;
	return (NSSize){w, w * (CGFloat)NGridH / NGridW};
}
- (void)addImage:(Display *)display {
	NSSize size = self.imageSize;
	if (view == nil || !NSEqualSizes(view.frame.size, size))
		view = [MyViewForCG.alloc initWithFrame:(NSRect){0., 0., size} display:display];
	if (images == nil) {
		images = NSMutableArray.new;
		dtFmt = NSDateFormatter.new;
		dtFmt.dateStyle = NSDateFormatterMediumStyle;
		dtFmt.timeStyle = NSDateFormatterMediumStyle;
	}
	NSString *str = [dtFmt stringFromDate:NSDate.date];
	[images addObject:[view bitmapImageChache:^(NSView *view) {
		NSSize vSize = view.bounds.size;
		NSDictionary *attr = @{NSFontAttributeName:
			[NSFont systemFontOfSize:vSize.height * .1],
			NSForegroundColorAttributeName:
			[NSColor colorWithWhite:1. alpha:.667]};
		NSSize txSize = [str sizeWithAttributes:attr];
		[str drawAtPoint:(NSPoint){(vSize.width - txSize.width) / 2.,
			(vSize.height - txSize.height) / 2.}
			withAttributes:attr];
	}]];
	in_main_thread(^{ self.needsDisplay = YES; });
}
- (void)drawRect:(NSRect)dirtyRect {
	[colBackground setFill];
	[NSBezierPath fillRect:dirtyRect];
	NSRect bounds = self.bounds, imgRect = {1., 0., [self imageSize]};
	for (NSInteger i = images.count - 1; i >= 0; i --) {
		if (imgRect.origin.y < bounds.size.height) {
			if (NSIntersectsRect(dirtyRect, imgRect)) [images[i] drawInRect:imgRect];
			imgRect.origin.y += imgRect.size.height;
		} else [images removeObjectAtIndex:i];
	}
	if (dirtyRect.origin.x < 1.) {
		[colGridLines setStroke];
		[NSBezierPath strokeLineFromPoint:
			(NSPoint){.5, NSMinY(dirtyRect)} toPoint:
			(NSPoint){.5, NSMaxY(dirtyRect)}];
	}
}
@end
