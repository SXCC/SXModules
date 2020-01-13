//
//  SXCameraUtil.m
//  SXModules
//
//  Created by shenxuecen on 2019/11/29.
//  Copyright © 2019 sxcc. All rights reserved.
//

#import "SXCameraUtil.h"

@implementation SXCameraUtil
+ (NSArray<AVCaptureDeviceFormat *> *)videoDataFormatsFromCandidates:(NSArray<AVCaptureDeviceFormat *> *)candidates
                                                         SatisfySize:(CGSize)targetSize
                                                        MinFrameRate:(NSInteger)minFrameRate
                                                        MaxFrameRate:(NSInteger)maxFrameRate
                                                    SupportDepthData:(BOOL)supportDepth {
    NSArray<AVCaptureDeviceFormat *>* curCandidates = candidates;
    NSMutableArray<AVCaptureDeviceFormat *>* filterResutls = [@[] mutableCopy];
    // meida type
    [curCandidates enumerateObjectsUsingBlock:^(AVCaptureDeviceFormat * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        CMFormatDescriptionRef desc = obj.formatDescription;
        if (CMFormatDescriptionGetMediaType(desc) == kCMMediaType_Video) {
            [filterResutls addObject:obj];
        }
    }];
    // target size
    if (!supportDepth) {
        filterResutls = [candidates mutableCopy];
    } else {
        [curCandidates enumerateObjectsUsingBlock:^(AVCaptureDeviceFormat * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            if (@available(iOS 11.0, *)) {
                if (obj.supportedDepthDataFormats.count > 0) {
                    [filterResutls addObject:obj];
                }
            } else {
                // Fallback on earlier versions
            }
        }];
    }
    curCandidates = [filterResutls copy];
    filterResutls = [@[] mutableCopy];
    // target size
    [curCandidates enumerateObjectsUsingBlock:^(AVCaptureDeviceFormat * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        CMFormatDescriptionRef desc = obj.formatDescription;
        if (CMVideoFormatDescriptionGetDimensions(desc).width == targetSize.width && CMVideoFormatDescriptionGetDimensions(desc).height) {
            [filterResutls addObject:obj];
        }
    }];
    curCandidates = [filterResutls copy];
    filterResutls = [@[] mutableCopy];
    // frame rate
    [curCandidates enumerateObjectsUsingBlock:^(AVCaptureDeviceFormat * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [obj.videoSupportedFrameRateRanges enumerateObjectsUsingBlock:^(AVFrameRateRange * _Nonnull range, NSUInteger idx, BOOL * _Nonnull stop) {
            if (range.minFrameRate <= minFrameRate && range.maxFrameRate >= maxFrameRate) {
                [filterResutls addObject:obj];
                *stop = true;
            }
        }];
    }];
    curCandidates = [filterResutls copy];
    filterResutls = [@[] mutableCopy];
    return curCandidates;
}

+ (AVCaptureDeviceFormat *)depthDataFormat:(NSArray<AVCaptureDeviceFormat *> *)candidates {
    if (candidates.count == 0) {
        return nil;
    }
    AVCaptureDeviceFormat* r = candidates[0];
    int w = CMVideoFormatDescriptionGetDimensions(r.formatDescription).width;
    for (int i = 1; i < candidates.count; i++) {
        if (CMVideoFormatDescriptionGetDimensions(candidates[i].formatDescription).width) {
            w = CMVideoFormatDescriptionGetDimensions(candidates[i].formatDescription).width;
            r = candidates[i];
        }
    }
    return r;
}


@end
