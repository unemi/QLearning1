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
	NSDateFormatter *dtFmt;
	NSMutableDictionary *attributes;
	CGFloat yOffset, oldHeight;
}
- (NSSize)imageSize {
	CGFloat w = self.bounds.size.width;
	return (NSSize){w, w * (CGFloat)NGridH / NGridW};
}
- (void)addImage:(Display *)display infoText:(NSString *)infoText {
	NSSize size = self.imageSize;
	if (images == nil) {
		images = NSMutableArray.new;
		dtFmt = NSDateFormatter.new;
		dtFmt.dateStyle = NSDateFormatterMediumStyle;
		dtFmt.timeStyle = NSDateFormatterMediumStyle;
		NSShadow *shadow = NSShadow.new;
		shadow.shadowOffset = (NSSize){3, -3};
		shadow.shadowBlurRadius = 5.;
		shadow.shadowColor = NSColor.blackColor;
		attributes = [NSMutableDictionary dictionaryWithDictionary:@{
			NSForegroundColorAttributeName:
			[NSColor colorWithWhite:1. alpha:.667],
			NSShadowAttributeName:shadow}];
	}
	if (oldHeight != size.height) attributes[NSFontAttributeName] =
		[NSFont userFontOfSize:(oldHeight = size.height) * .1];
	NSString *str = [NSString stringWithFormat:@"%@\n%@",
		[dtFmt stringFromDate:NSDate.date], infoText];
	NSDictionary *attr = attributes;
	[images addObject:[display
		imageBitmapWithSize:size scaleFactor:self.window.backingScaleFactor
		drawBlock:^(NSBitmapImageRep * _Nonnull bm) {
		NSSize vSize = bm.size, txSize = [str sizeWithAttributes:attr];
		[str drawAtPoint:(NSPoint){(vSize.width - txSize.width) / 2.,
			(vSize.height - txSize.height) / 2.}
			withAttributes:attr];
	}]];
#ifdef DEBUG
	NSBitmapImageRep *bm = (NSBitmapImageRep *)images.lastObject;
	NSLog(@"Image size = %.0f x %.0f, bitmap pixels = %ld x %ld",
	size.width, size.height, bm.pixelsWide, bm.pixelsHigh);
#endif
	yOffset = 1.;
	[NSTimer scheduledTimerWithTimeInterval:1./30. repeats:YES block:
		^(NSTimer * _Nonnull timer) {
		if ((self->yOffset -= 1./30./1.5) <= 0.)
			{ self->yOffset = 0.; [timer invalidate]; }
		self.needsDisplay = YES;
	}];
	in_main_thread(^{ self.needsDisplay = YES; });
}
- (void)drawRect:(NSRect)dirtyRect {
	[colBackground setFill];
	[NSBezierPath fillRect:dirtyRect];
	NSRect bounds = self.bounds, imgRect = {1., 0., [self imageSize]};
	imgRect.origin.y -= imgRect.size.height * yOffset;
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
