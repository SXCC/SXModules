//
//  SXVideoRenderView.h
//  SXModules
//
//  Created by shenxuecen on 2019/10/28.
//  Copyright © 2019 sxcc. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <MetalKit/MetalKit.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SXVideoRenderView: MTKView
- (id)initWithFrame:(CGRect)frame
             Device:(id<MTLDevice>)device
        LibraryPath:(NSString * _Nullable)libraryPath
         BufferSize:(CGSize)bufferSize;
- (void)drawPixelBuffer:(CVPixelBufferRef)pixelBuffer;
- (void)drawSampleBuffer:(CMSampleBufferRef)sampleBuffer;
- (void)drawNormalizedPoints:(NSArray *)normalizedPoints;
- (void)blendMask:(unsigned char*)maskBytes Width:(int)width Height:(int)height Channels:(int)channels BytesPerRow:(int)rowBytes;
- (void)renderToScreen;
@end

NS_ASSUME_NONNULL_END

