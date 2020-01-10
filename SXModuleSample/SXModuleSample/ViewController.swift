//
//  ViewController.swift
//  SXModuleSample
//
//  Created by 雪岑申 on 2019/11/23.
//  Copyright © 2019 sxcc. All rights reserved.
//

import UIKit
import MetalKit
import SXModules

class ViewController: UIViewController {
    
    var renderView: SXVideoRenderView!
    var camera: SXCameraController!
    var movieRecorder: SXMovieRecorder!
    
    var recordCount = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        renderView = SXVideoRenderView(frame: view.frame, device: MTLCreateSystemDefaultDevice()!, libraryPath: nil, bufferSize: CGSize(width: 720, height: 1280))
        view.addSubview(renderView)
        camera = SXCameraController()
        camera.setDataOutputWithSettings([kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA])
        camera.switch(toDefaultDeviceOf: .front)
        camera.setVideoDataOrientation(.portrait)
        camera.setVideoMirror(false)
        camera.addDataOutputDelegate(self)
        
        let formats = camera.supportedDeviceFormatsForCurrentDevice()
        let targetFormats = SXCameraUtil.videoDataFormats(fromCandidates: formats, satisfy: CGSize(width: 1280, height: 720), minFrameRate: 30, maxFrameRate: 30, supportDepthData: true)!
        if targetFormats.count > 0 {
            let targetFormat = targetFormats.first!
            camera.setActiveDeviceFormat(targetFormat)
        }
    
        setupControls()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        camera.startCapture()
    }
    
    func setupControls() {
        var ptY = 100
        
        // white balance
        let temperatureLabel = UILabel(frame: CGRect(x: 12, y: ptY, width: 80, height: 80))
        temperatureLabel.text = "Temp:"
        view.addSubview(temperatureLabel)
        let temperatureSlider = UISlider(frame: CGRect(x: 75, y: ptY, width: 300, height: 80));
        temperatureSlider.minimumValue = 1000
        temperatureSlider.maximumValue = 8000
        temperatureSlider.tag = 101
        temperatureSlider.addTarget(self, action: #selector(controlEventHandler(sender:)), for: .valueChanged)
        view.addSubview(temperatureSlider)
        
        ptY = ptY + 100
        let tintLabel = UILabel(frame: CGRect(x: 12, y: ptY, width: 80, height: 80))
        tintLabel.text = "Tint:"
        view.addSubview(tintLabel)
        let tintSlider = UISlider(frame: CGRect(x: 75, y: ptY, width: 300, height: 80));
        tintSlider.minimumValue = -150
        tintSlider.maximumValue = 150
        tintSlider.tag = 102
        tintSlider.addTarget(self, action: #selector(controlEventHandler(sender:)), for: .valueChanged)
        view.addSubview(tintSlider)
        
        // set default values
        let gains = self.camera.currentDeviceWhiteBalanceGains()
        let tempAndTint = self.camera.temperatureAndTintValues(forDeviceWhiteBalanceGains: gains)
        temperatureSlider.value = tempAndTint.temperature
        tintSlider.value = tempAndTint.tint
        
        // zoom
        ptY = ptY + 100
        let zoomLabel = UILabel(frame: CGRect(x: 12, y: ptY, width: 80, height: 80))
        zoomLabel.text = "Zoom:"
        view.addSubview(zoomLabel)
        let zoomSlider = UISlider(frame: CGRect(x: 75, y: ptY, width: 300, height: 80))
        zoomSlider.minimumValue = Float(self.camera.miniumZoomFactor())
        zoomSlider.maximumValue = Float(self.camera.maxiumZoomFactor())
        zoomSlider.value = Float(self.camera.currentZoomFactor())
        zoomSlider.tag = 103
        zoomSlider.addTarget(self, action: #selector(controlEventHandler(sender:)), for: .valueChanged)
        view.addSubview(zoomSlider)
        
        // movie record
        ptY = ptY + 100
        let recordBtn = UIButton(frame: CGRect(x: 12, y: ptY, width: 100, height: 80))
        recordBtn.layer.borderWidth = 1.0
        recordBtn.setTitle("start", for: .normal)
        recordBtn.addTarget(self, action: #selector(controlEventHandler(sender:)), for: .touchUpInside)
        recordBtn.tag = 104
        view.addSubview(recordBtn)
        
    }
    
    @objc
    func controlEventHandler(sender: UIControl) {
        if sender.tag == 101 || sender.tag == 102 {
            if !self.camera.supportsLockWhiteBalanceToCustomValue() {
                return
            }
            let tempSlider = view.viewWithTag(101) as! UISlider
            let tintSlider = view.viewWithTag(102) as! UISlider
            let newVal = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: tempSlider.value, tint: tintSlider.value)
            var gains = self.camera.deviceWhiteBalanceGains(for: newVal)
            gains.blueGain = min(gains.blueGain, self.camera.maxiumWhiteBalanceGains())
            gains.redGain = min(gains.redGain, self.camera.maxiumWhiteBalanceGains())
            gains.greenGain = min(gains.greenGain, self.camera.maxiumWhiteBalanceGains())
            self.camera.setWhiteBalanceModeLockedWithDeviceWhiteBalanceGains(gains) { (_) in
            }
        } else if sender.tag == 103 {
            self.camera.setZoomFactor(CGFloat((sender as! UISlider).value))
        } else if sender.tag == 104 {
            if (sender as! UIButton).titleLabel?.text == "start" {
                self.startRecord()
                (sender as! UIButton).setTitle("end", for: .normal)
            } else {
                (sender as! UIButton).setTitle("start", for: .normal)
                self.finishRecord {
                    print("Record Finished")
                }
            }
        }
    }
}

extension ViewController: SXCameraControllerDataDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)!
        renderView.draw(pixelBuffer, cleanBuffer: true)
        if (view.viewWithTag(104) as! UIButton).titleLabel?.text == "end" {
            let recordBuffer = self.self.movieRecorder.generatePixelBuffer()!.takeRetainedValue()
            renderView.render(to: recordBuffer)
            if self.movieRecorder.append(recordBuffer) {
                recordCount = recordCount + 1
            }
        }
        renderView.renderToScreen()
    }
    
    func createPixelBuffer() -> CVPixelBuffer {
        var buffer: CVPixelBuffer? = nil
        CVPixelBufferCreate(kCFAllocatorDefault, 720, 1280, kCVPixelFormatType_32BGRA, [kCVPixelBufferMetalCompatibilityKey: true] as CFDictionary
            , &buffer)
        return buffer!
    }
}

extension ViewController {
    
    func startRecord() {
        let filePath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first! + "/video.mov"
        do { try FileManager.default.removeItem(atPath: filePath) } catch {} // remove file if already exists
        movieRecorder = SXMovieRecorder(path: filePath, fileType: .mov, videoSize: CGSize(width: 720, height: 1280), frameRate: 30, bitRate: 3500000)
        self.movieRecorder.startWriting()
    }
    
    func finishRecord(handler:@escaping ()->()) {
        self.movieRecorder.finishWriting(handler)
    }
}
