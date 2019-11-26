//
//  SXCameraController.h
//  PLShortVideoKitDemo
//
//  Created by shenxuecen on 2019/11/21.
//  Copyright © 2019 Pili Engineering, Qiniu Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SXCameraController : NSObject
// Camera Input
- (BOOL)setInputDevice:(AVCaptureDevice *)device;
- (BOOL)switchToDefaultDeviceOfPosition:(AVCaptureDevicePosition)position;
// Camera Output
- (void)setDataOutputWithSettings:(NSDictionary *)videoSetting;
- (void)addDataOutputDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate;
- (void)removeDataOutputDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate;
// Camera Config
- (void)setSessionPreset:(AVCaptureSessionPreset)preset;
- (void)setVideoDataOrientation:(AVCaptureVideoOrientation)orientation;
- (void)setVideoMirror:(BOOL)mirror;
// Camera Control
- (void)startCapture;
- (void)stopCapture;
@end

NS_ASSUME_NONNULL_END
