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
    
    override func viewDidLoad() {
        super.viewDidLoad()
        renderView = SXVideoRenderView(frame: view.frame, device: MTLCreateSystemDefaultDevice()!, libraryPath: nil, bufferSize: CGSize(width: 720, height: 1280))
        view.addSubview(renderView)
        camera = SXCameraController()
        camera.setDataOutputWithSettings([kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA])
        camera.switch(toDefaultDeviceOf: .back)
        camera.setVideoDataOrientation(.portrait)
        camera.setVideoMirror(false)
        camera.addDataOutputDelegate(self)
        setupControls()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        camera.startCapture()
    }
    
    func setupControls() {
        var ptY = 100
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
    }
    
    @objc
    func controlEventHandler(sender: UIControl) {
        if sender.tag == 101 || sender.tag == 102 {
            let tempSlider = view.viewWithTag(101) as! UISlider
            let tintSlider = view.viewWithTag(102) as! UISlider
            let newVal = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: tempSlider.value, tint: tintSlider.value)
            var gains = self.camera.deviceWhiteBalanceGains(for: newVal)
            gains.blueGain = min(gains.blueGain, self.camera.maxiumWhiteBalanceGains())
            gains.redGain = min(gains.redGain, self.camera.maxiumWhiteBalanceGains())
            gains.greenGain = min(gains.greenGain, self.camera.maxiumWhiteBalanceGains())
            
            self.camera.setWhiteBalanceModeLockedWithDeviceWhiteBalanceGains(gains) { (_) in
            }
        }
    }
    
}

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)!
        renderView.draw(pixelBuffer)
        renderView.renderToScreen()
    }
}
