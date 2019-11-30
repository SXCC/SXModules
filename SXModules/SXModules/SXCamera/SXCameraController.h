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

@protocol SXCameraControllerDataDelegate <NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureDepthDataOutputDelegate>
@end

@interface SXCameraController : NSObject
// Camera Input
//   Device
- (BOOL)setInputDevice:(AVCaptureDevice *)device;
- (BOOL)switchToDefaultDeviceOfPosition:(AVCaptureDevicePosition)position;
//   Device Format & Depth Format
- (NSArray<AVCaptureDeviceFormat *> *)supportedDeviceFormatsForCurrentDevice;
- (AVCaptureDeviceFormat *)activeDeviceFormat;
- (AVCaptureDeviceFormat *)activeDepthDataFormat;
- (void)setActiveDeviceFormat:(AVCaptureDeviceFormat *)deviceFormat;
- (void)setActiveDepthDataFormat:(AVCaptureDeviceFormat *)depthFormat;
// Camera Output
//  Video Output
- (void)setDataOutputWithSettings:(NSDictionary *)videoSetting;
- (void)addDataOutputDelegate:(id<SXCameraControllerDataDelegate>)delegate;
- (void)removeDataOutputDelegate:(id<SXCameraControllerDataDelegate>)delegate;
//  Depth Output
- (void)setDepthDataOutput;
// Camera Config
- (void)setSessionPreset:(AVCaptureSessionPreset)preset;
- (void)setVideoDataOrientation:(AVCaptureVideoOrientation)orientation;
- (void)setVideoMirror:(BOOL)mirror;
//   White Balance
- (BOOL)supportsLockWhiteBalanceToCustomValue;
- (void)setWhiteBalanceModeLockedWithDeviceWhiteBalanceGains:(AVCaptureWhiteBalanceGains)gains completionHandler:(void (^)(CMTime syncTime))handler;
- (AVCaptureWhiteBalanceGains)currentDeviceWhiteBalanceGains;
- (float)maxiumWhiteBalanceGains;
- (AVCaptureWhiteBalanceTemperatureAndTintValues)temperatureAndTintValuesForDeviceWhiteBalanceGains:(AVCaptureWhiteBalanceGains)gains;
- (AVCaptureWhiteBalanceGains)deviceWhiteBalanceGainsForTemperatureAndTintValues:(AVCaptureWhiteBalanceTemperatureAndTintValues)temperateTint;
- (void)setWhiteBalanceModel:(AVCaptureWhiteBalanceMode)model;
//   Zoom
- (CGFloat)currentZoomFactor;
- (CGFloat)miniumZoomFactor;
- (CGFloat)maxiumZoomFactor;
- (void)setZoomFactor:(CGFloat)newZoomFactor;

// Camera Control
- (void)startCapture;
- (void)stopCapture;
@end

NS_ASSUME_NONNULL_END
