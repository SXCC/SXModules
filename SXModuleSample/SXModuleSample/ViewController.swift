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
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        camera.startCapture()
    }
}

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)!
        renderView.draw(pixelBuffer)
        renderView.renderToScreen()
    }
}
