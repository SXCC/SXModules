//
//  SXCameraUtil.h
//  SXModules
//
//  Created by shenxuecen on 2019/11/29.
//  Copyright © 2019 sxcc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>


@interface SXCameraUtil : NSObject

+ (AVCaptureDeviceFormat *)depthDataFormat:(NSArray<AVCaptureDeviceFormat *> *) candidates;
+ (NSArray<AVCaptureDeviceFormat *> *)videoDataFormatsFromCandidates:(NSArray<AVCaptureDeviceFormat *> *) candidates
                                                         SatisfySize:(CGSize)targetSize
                                                        MinFrameRate:(NSInteger)minFrameRate
                                                        MaxFrameRate:(NSInteger)maxFrameRate
                                                    SupportDepthData:(BOOL)supportDepth;
@end

