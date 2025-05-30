//
//  ZLCustomCamera.swift
//  ZLPhotoBrowser
//
//  Created by long on 2020/8/11.
//
//  Copyright (c) 2020 Long Zhang <495181165@qq.com>
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

import UIKit
import AVFoundation
import CoreMotion
import Photos
import ReversibleCommon
open class ZLCustomCamera: UIViewController, CAAnimationDelegate {

    struct Layout {
        
        static let bottomViewH: CGFloat = 100
        
        static let largeCircleRadius: CGFloat = 85
        
        static let smallCircleRadius: CGFloat = 62
        
        static let largeCircleRecordScale: CGFloat = 1.2
        
        static let smallCircleRecordScale: CGFloat = 0.7
        
    }
    
    @objc public var takeDoneBlock: ( (UIImage?, URL?) -> Void )?
    
    @objc public var cancelBlock: ( () -> Void )?
    
    public lazy var tipsLabel = UILabel()
    
    public lazy var bottomView = UIView()
    
    public lazy var largeCircleView: UIVisualEffectView = {
        if #available(iOS 13.0, *) {
            return UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialLight))
        } else {
            return UIVisualEffectView(effect: UIBlurEffect(style: .light))
        }
    }()
    
    public lazy var smallCircleView = UIView()
    
    public lazy var animateLayer = CAShapeLayer()
    
    public lazy var retakeBtn = UIButton(type: .custom)
    
    public lazy var doneBtn = UIButton(type: .custom)
    
    public lazy var dismissBtn = UIButton(type: .custom)
    
    public lazy var switchCameraBtn = UIButton(type: .custom)
    
    public lazy var focusCursorView = UIImageView(image: getImage("zl_focus"))
    
    public lazy var takedImageView = UIImageView()
    
    lazy var topBgView = UIView()
    lazy var topShadowLayer: CAGradientLayer = CAGradientLayer()
    

    var hideTipsTimer: Timer?
    
    var takedImage: UIImage?
    
    var videoUrl: URL?
    
    var motionManager: CMMotionManager?
    
    var orientation: AVCaptureVideoOrientation = .portrait
    
    let sessionQueue = DispatchQueue(label: "com.zl.camera.sessionQueue")
    
    let session = AVCaptureSession()
    
    var videoInput: AVCaptureDeviceInput?
    
    var imageOutput: AVCapturePhotoOutput!
    
    var movieFileOutput: AVCaptureMovieFileOutput!
    
    var previewLayer: AVCaptureVideoPreviewLayer?
    
    var recordVideoPlayerLayer: AVPlayerLayer?
    
    var cameraConfigureFinish = false
    
    var layoutOK = false
    
    var dragStart = false
    
    var viewDidAppearCount = 0
    
    var restartRecordAfterSwitchCamera = false
    
    var cacheVideoOrientation: AVCaptureVideoOrientation = .portrait
    
    var recordUrls: [URL] = []
    
    var microPhontIsAvailable = true
    
    weak var thumbnailsVC: ZLThumbnailViewController?
    
    // 仅支持竖屏
    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
    
    public override var prefersStatusBarHidden: Bool {
        return true
    }
    
    deinit {
        zl_debugPrint("ZLCustomCamera deinit")
        self.cleanTimer()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    
    @objc public init() {
        super.init(nibName: nil, bundle: nil)
        self.modalPresentationStyle = .fullScreen
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        
        self.setupUI()
        if !UIImagePickerController.isSourceTypeAvailable(.camera) {
            return
        }
        
        self.observerDeviceMotion()
        
        AVCaptureDevice.requestAccess(for: .video) { (videoGranted) in
            guard videoGranted else {
                ZLMainAsync(after: 1) {
                    self.showAlertAndDismissAfterDoneAction(message: String(format: localLanguageTextValue(.noCameraAuthority), getAppName()), type: .camera)
                }
                return
            }
            guard ZLPhotoConfiguration.default().allowRecordVideo else {
                self.addNotification()
                return
            }
            
            AVCaptureDevice.requestAccess(for: .audio) { (audioGranted) in
                self.addNotification()
                if !audioGranted {
                    ZLMainAsync(after: 1) {
                        self.showNoMicrophoneAuthorityAlert()
                    }
                }
            }
        }
        
        if ZLPhotoConfiguration.default().allowRecordVideo {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .videoRecording, options: .mixWithOthers)
                try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
            } catch {
                let err = error as NSError
                if err.code == AVAudioSession.ErrorCode.insufficientPriority.rawValue ||
                    err.code == AVAudioSession.ErrorCode.isBusy.rawValue {
                    self.microPhontIsAvailable = false
                }
            }
        }
        
        self.setupCamera()
        self.sessionQueue.async {
            self.session.startRunning()
        }
    }
    
    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !UIImagePickerController.isSourceTypeAvailable(.camera) {
            showAlertAndDismissAfterDoneAction(message: localLanguageTextValue(.cameraUnavailable), type: .camera)
        } else if !ZLPhotoConfiguration.default().allowTakePhoto, !ZLPhotoConfiguration.default().allowRecordVideo {
            #if DEBUG
            fatalError("Error configuration of camera")
            #else
            showAlertAndDismissAfterDoneAction(message: "Error configuration of camera", type: nil)
            #endif
        } else if self.cameraConfigureFinish, self.viewDidAppearCount == 0 {
            self.showTipsLabel(animate: true)
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.toValue = 1
            animation.duration = 0.15
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
            self.previewLayer?.add(animation, forKey: nil)
            self.setFocusCusor(point: self.view.center)
        }
        self.viewDidAppearCount += 1
    }
    
    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.motionManager?.stopDeviceMotionUpdates()
        self.motionManager = nil
    }
    
    open override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if self.session.isRunning {
            self.session.stopRunning()
        }
    }
    
    func hideVC() {
        if self.session.isRunning {
            self.session.stopRunning()
        }
        if self.videoUrl != nil, let player = self.recordVideoPlayerLayer?.player {
            player.pause()
        }
    }
    
    func showVC() {
        if self.session.isRunning == false {
            self.session.startRunning()
        }
        if self.videoUrl != nil, let player = self.recordVideoPlayerLayer?.player {
            player.play()
        }
    }
    
    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !self.layoutOK else { return }
        self.layoutOK = true
        
        var insets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        if #available(iOS 11.0, *) {
            insets = self.view.safeAreaInsets
        }
        let previewLayerY: CGFloat = deviceSafeAreaInsets().top > 0 ? 20 : 0
        self.previewLayer?.frame = CGRect(x: 0, y: 0, width: self.view.bounds.width, height: self.view.bounds.height)
        self.recordVideoPlayerLayer?.frame = self.view.bounds
        self.takedImageView.frame = self.view.bounds
        self.bottomView.frame = CGRect(x: 0, y: self.view.bounds.height-insets.bottom-ZLCustomCamera.Layout.bottomViewH-20, width: self.view.bounds.width, height: ZLCustomCamera.Layout.bottomViewH)
        let largeCircleH = ZLCustomCamera.Layout.largeCircleRadius
        self.largeCircleView.frame = CGRect(x: (self.view.bounds.width-largeCircleH)/2, y: (ZLCustomCamera.Layout.bottomViewH-largeCircleH)/2, width: largeCircleH, height: largeCircleH)
        let smallCircleH = ZLCustomCamera.Layout.smallCircleRadius
        self.smallCircleView.frame = CGRect(x: (self.view.bounds.width-smallCircleH)/2, y: (ZLCustomCamera.Layout.bottomViewH-smallCircleH)/2, width: smallCircleH, height: smallCircleH)
        
        
        let tipsTextHeight = (self.tipsLabel.text ?? " ").boundingRect(font: getFont(14), limitSize: CGSize(width: self.view.bounds.width - 20, height: .greatestFiniteMagnitude)).height
        self.tipsLabel.frame = CGRect(x: 10, y: self.bottomView.frame.minY - tipsTextHeight, width: self.view.bounds.width - 20, height: tipsTextHeight)
        
        self.retakeBtn.frame = CGRect(x: 15, y: insets.top+10, width: 25, height: 25)
        self.dismissBtn.frame = CGRect(x: 15, y: insets.top+10, width: 25, height: 25)
        self.switchCameraBtn.frame = CGRect(x: self.view.bounds.width-15-28, y: insets.top+10, width: 28, height: 28)
        self.topBgView.frame = CGRect(x: 0, y: 0, width: view.frame.width, height: self.switchCameraBtn.frame.maxY + 10)
        self.topShadowLayer.frame = self.topBgView.bounds
        
        let doneBtnW = "confirm".localized("Confirm").boundingRect(font: ZLLayout.bottomToolTitleFont, limitSize: CGSize(width: CGFloat.greatestFiniteMagnitude, height: 40)).width + 20
        let doneBtnY = self.view.bounds.height - 57 - insets.bottom
        self.doneBtn.frame = CGRect(x: self.view.bounds.width - doneBtnW - 20, y: doneBtnY, width: doneBtnW, height: ZLLayout.bottomToolBtnH)
    }
    
    func setupUI() {
        self.view.backgroundColor = .black
        
        self.takedImageView.backgroundColor = .black
        self.takedImageView.isHidden = true
        self.takedImageView.contentMode = .scaleAspectFit
        self.view.addSubview(self.takedImageView)
        
        self.focusCursorView.contentMode = .scaleAspectFit
        self.focusCursorView.clipsToBounds = true
        self.focusCursorView.frame = CGRect(x: 0, y: 0, width: 70, height: 70)
        self.focusCursorView.alpha = 0
        self.view.addSubview(self.focusCursorView)
        
        self.tipsLabel.font = getFont(14)
        self.tipsLabel.textColor = .white
        self.tipsLabel.textAlignment = .center
        self.tipsLabel.numberOfLines = 2
        self.tipsLabel.lineBreakMode = .byWordWrapping
        self.tipsLabel.alpha = 0
        if ZLPhotoConfiguration.default().allowTakePhoto, ZLPhotoConfiguration.default().allowRecordVideo {
            self.tipsLabel.text = localLanguageTextValue(.customCameraTips)
        } else if ZLPhotoConfiguration.default().allowTakePhoto {
            self.tipsLabel.text = localLanguageTextValue(.customCameraTakePhotoTips)
        } else if ZLPhotoConfiguration.default().allowRecordVideo {
            self.tipsLabel.text = localLanguageTextValue(.customCameraRecordVideoTips)
        }
        
        self.view.addSubview(self.tipsLabel)
        self.view.addSubview(self.bottomView)
        
        let color1 = UIColor.black.withAlphaComponent(0.3).cgColor
        let color2 = UIColor.black.withAlphaComponent(0.0).cgColor
        self.topShadowLayer.colors = [color1, color2]
        self.topShadowLayer.locations = [0, 1]
        self.topBgView.layer.addSublayer(self.topShadowLayer)
        
        
        self.view.addSubview(self.topBgView)
        self.dismissBtn.setImage(getImage("page_close"), for: .normal)
        self.dismissBtn.addTarget(self, action: #selector(dismissBtnClick), for: .touchUpInside)
        self.dismissBtn.adjustsImageWhenHighlighted = false
        self.dismissBtn.zl_enlargeValidTouchArea(inset: 30)
        self.view.addSubview(self.dismissBtn)
        
        self.largeCircleView.layer.masksToBounds = true
        self.largeCircleView.layer.cornerRadius = ZLCustomCamera.Layout.largeCircleRadius / 2
        self.bottomView.addSubview(self.largeCircleView)
        
        self.smallCircleView.layer.masksToBounds = true
        self.smallCircleView.layer.cornerRadius = ZLCustomCamera.Layout.smallCircleRadius / 2
        self.smallCircleView.isUserInteractionEnabled = false
        self.smallCircleView.backgroundColor = .white
        self.bottomView.addSubview(self.smallCircleView)
        
        let animateLayerRadius = ZLCustomCamera.Layout.largeCircleRadius
        let path = UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: animateLayerRadius, height: animateLayerRadius), cornerRadius: animateLayerRadius/2)
        self.animateLayer.path = path.cgPath
        self.animateLayer.strokeColor = UIColor.cameraRecodeProgressColor.cgColor
        self.animateLayer.fillColor = UIColor.clear.cgColor
        self.animateLayer.lineWidth = 8
        
        var takePictureTap: UITapGestureRecognizer?
        if ZLPhotoConfiguration.default().allowTakePhoto {
            takePictureTap = UITapGestureRecognizer(target: self, action: #selector(takePicture))
            self.largeCircleView.addGestureRecognizer(takePictureTap!)
        }
        if ZLPhotoConfiguration.default().allowRecordVideo {
            let recordLongPress = UILongPressGestureRecognizer(target: self, action: #selector(longPressAction(_:)))
            recordLongPress.minimumPressDuration = 0.3
            recordLongPress.delegate = self
            self.largeCircleView.addGestureRecognizer(recordLongPress)
            takePictureTap?.require(toFail: recordLongPress)
        }
        
        self.retakeBtn.setImage(getImage("zl_retake"), for: .normal)
        self.retakeBtn.addTarget(self, action: #selector(retakeBtnClick), for: .touchUpInside)
        self.retakeBtn.isHidden = true
        self.retakeBtn.adjustsImageWhenHighlighted = false
        self.retakeBtn.zl_enlargeValidTouchArea(inset: 30)
        self.view.addSubview(self.retakeBtn)
        
        let cameraCount = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified).devices.count
        self.switchCameraBtn.setImage(getImage("zl_toggle_camera"), for: .normal)
        self.switchCameraBtn.addTarget(self, action: #selector(switchCameraBtnClick), for: .touchUpInside)
        self.switchCameraBtn.adjustsImageWhenHighlighted = false
        self.switchCameraBtn.zl_enlargeValidTouchArea(inset: 30)
        self.switchCameraBtn.isHidden = cameraCount <= 1
        self.view.addSubview(self.switchCameraBtn)
        
        self.doneBtn.titleLabel?.font = ZLLayout.bottomToolTitleFont
        self.doneBtn.setTitle(localLanguageTextValue(.done), for: .normal)
        self.doneBtn.setTitleColor(.bottomToolViewBtnNormalTitleColor, for: .normal)
        self.doneBtn.backgroundColor = .bottomToolViewBtnNormalBgColor
        self.doneBtn.addTarget(self, action: #selector(doneBtnClick), for: .touchUpInside)
        self.doneBtn.isHidden = true
        self.doneBtn.layer.masksToBounds = true
        self.doneBtn.layer.cornerRadius = ZLLayout.bottomToolBtnCornerRadius
        self.view.addSubview(self.doneBtn)
        
        let focusCursorTap = UITapGestureRecognizer(target: self, action: #selector(adjustFocusPoint))
        focusCursorTap.delegate = self
        self.view.addGestureRecognizer(focusCursorTap)
        
        if ZLPhotoConfiguration.default().allowRecordVideo {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(adjustCameraFocus(_:)))
            pan.delegate = self
            pan.maximumNumberOfTouches = 1
            self.view.addGestureRecognizer(pan)
            
            self.recordVideoPlayerLayer = AVPlayerLayer()
            self.recordVideoPlayerLayer?.backgroundColor = UIColor.black.cgColor
            self.recordVideoPlayerLayer?.videoGravity = .resizeAspect
            self.recordVideoPlayerLayer?.isHidden = true
            self.view.layer.insertSublayer(self.recordVideoPlayerLayer!, at: 0)
            
            NotificationCenter.default.addObserver(self, selector: #selector(recordVideoPlayFinished), name: .AVPlayerItemDidPlayToEndTime, object: nil)
        }
        
        let pinchGes = UIPinchGestureRecognizer(target: self, action: #selector(pinchToAdjustCameraFocus(_:)))
        self.view.addGestureRecognizer(pinchGes)
    }
    
    func observerDeviceMotion() {
        if !Thread.isMainThread {
            ZLMainAsync {
                self.observerDeviceMotion()
            }
            return
        }
        self.motionManager = CMMotionManager()
        self.motionManager?.deviceMotionUpdateInterval = 0.5
        
        if self.motionManager?.isDeviceMotionAvailable == true {
            self.motionManager?.startDeviceMotionUpdates(to: OperationQueue.main, withHandler: { (motion, error) in
                if let _ = motion {
                    self.handleDeviceMotion(motion!)
                }
            })
        } else {
            self.motionManager = nil
        }
    }
    
    func handleDeviceMotion(_ motion: CMDeviceMotion) {
        let x = motion.gravity.x
        let y = motion.gravity.y
        
        if abs(y) >= abs(x) {
            if y >= 0 {
                self.orientation = .portraitUpsideDown
            } else {
                self.orientation = .portrait
            }
        } else {
            if x >= 0 {
                self.orientation = .landscapeLeft
            } else {
                self.orientation = .landscapeRight
            }
        }
    }
    
    func setupCamera() {
        guard let backCamera = self.getCamera(position: .back) else { return }
        guard let input = try? AVCaptureDeviceInput(device: backCamera) else { return }
        
        self.session.beginConfiguration()
        
        // 相机画面输入流
        self.videoInput = input
        // 照片输出流
        self.imageOutput = AVCapturePhotoOutput()
        
        let preset = ZLPhotoConfiguration.default().cameraConfiguration.sessionPreset.avSessionPreset
        if self.session.canSetSessionPreset(preset) {
            self.session.sessionPreset = preset
        } else {
            self.session.sessionPreset = .hd1280x720
        }
        
        self.movieFileOutput = AVCaptureMovieFileOutput()
        // 解决视频录制超过10s没有声音的bug
        self.movieFileOutput.movieFragmentInterval = .invalid
        
        // 添加视频输入
        if let vi = self.videoInput, self.session.canAddInput(vi) {
            self.session.addInput(vi)
        }
        // 添加音频输入
        self.addAudioInput()
        
        // 将输出流添加到session
        if self.session.canAddOutput(self.imageOutput) {
            self.session.addOutput(self.imageOutput)
        }
        if self.session.canAddOutput(self.movieFileOutput) {
            self.session.addOutput(self.movieFileOutput)
        }
        
        self.session.commitConfiguration()
        // 预览layer
        self.previewLayer = AVCaptureVideoPreviewLayer(session: self.session)
        self.previewLayer?.videoGravity = .resizeAspectFill
        self.previewLayer?.opacity = 0
        self.view.layer.masksToBounds = true
        self.view.layer.insertSublayer(self.previewLayer!, at: 0)
        
        self.cameraConfigureFinish = true
    }
    
    func getCamera(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: position).devices
        for device in devices {
            if device.position == position {
                return device
            }
        }
        return nil
    }
    
    func getMicrophone() -> AVCaptureDevice? {
        return AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInMicrophone], mediaType: .audio, position: .unspecified).devices.first
    }
    
    func addAudioInput() {
        guard ZLPhotoConfiguration.default().allowRecordVideo else { return }
        // 音频输入流
        var audioInput: AVCaptureDeviceInput?
        if let microphone = self.getMicrophone() {
            audioInput = try? AVCaptureDeviceInput(device: microphone)
        }
        guard self.microPhontIsAvailable, let ai = audioInput else { return }
        self.removeAudioInput()
        
        if self.session.isRunning {
            self.session.beginConfiguration()
        }
        if self.session.canAddInput(ai) {
            self.session.addInput(ai)
        }
        if self.session.isRunning {
            self.session.commitConfiguration()
        }
    }
    
    func removeAudioInput() {
        var audioInput: AVCaptureInput?
        for input in self.session.inputs {
            if (input as? AVCaptureDeviceInput)?.device.deviceType == .builtInMicrophone {
                audioInput = input
            }
        }
        guard let ai = audioInput else { return }
        
        if self.session.isRunning {
            self.session.beginConfiguration()
        }
        self.session.removeInput(ai)
        if self.session.isRunning {
            self.session.commitConfiguration()
        }
    }
    
    func addNotification() {
        NotificationCenter.default.addObserver(self, selector: #selector(appWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
        
        if ZLPhotoConfiguration.default().allowRecordVideo {
            NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(handleAudioSessionInterruption), name: AVAudioSession.interruptionNotification, object: nil)
        }
    }
    
    func showNoMicrophoneAuthorityAlert() {
        let alert = UIAlertController(title: nil, message: String(format: localLanguageTextValue(.noMicrophoneAuthority), getAppName()), preferredStyle: .alert)
        let continueAction = UIAlertAction(title: localLanguageTextValue(.keepRecording), style: .default, handler: nil)
        let gotoSettingsAction = UIAlertAction(title: localLanguageTextValue(.gotoSettings), style: .default) { (_) in
            guard let url = URL(string: UIApplication.openSettingsURLString) else {
                return
            }
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
        alert.addAction(continueAction)
        alert.addAction(gotoSettingsAction)
        showAlertController(alert)
    }
    
    func showAlertAndDismissAfterDoneAction(message: String, type: ZLNoAuthorityType?) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        let action = UIAlertAction(title: localLanguageTextValue(.done), style: .default) { (_) in
            self.dismiss(animated: true) {
                if let t = type {
                    ZLPhotoConfiguration.default().noAuthorityCallback?(t)
                }
            }
        }
        alert.addAction(action)
        showAlertController(alert)
    }
    
    func showTipsLabel(animate: Bool) {
        guard UserDefaults.standard.bool(forKey: "show_camera_tip") == false else {
            return
        }
        UserDefaults.standard.set(true, forKey: "show_camera_tip")
        self.tipsLabel.layer.removeAllAnimations()
        if animate {
            UIView.animate(withDuration: 0.25) {
                self.tipsLabel.alpha = 1
            }
        } else {
            self.tipsLabel.alpha = 1
        }
        self.startHideTipsLabelTimer()
    }
    
    func hideTipsLabel(animate: Bool) {
        self.tipsLabel.layer.removeAllAnimations()
        if animate {
            UIView.animate(withDuration: 0.25) {
                self.tipsLabel.alpha = 0
            }
        } else {
            self.tipsLabel.alpha = 0
        }
    }
    
    @objc func hideTipsLabel_timerFunc() {
        self.cleanTimer()
        self.hideTipsLabel(animate: true)
    }
    
    func startHideTipsLabelTimer() {
        self.cleanTimer()
        self.hideTipsTimer = Timer.scheduledTimer(timeInterval: 3, target: ZLWeakProxy(target: self), selector: #selector(hideTipsLabel_timerFunc), userInfo: nil, repeats: false)
        RunLoop.current.add(self.hideTipsTimer!, forMode: .common)
    }
    
    func cleanTimer() {
        self.hideTipsTimer?.invalidate()
        self.hideTipsTimer = nil
    }
    
    @objc func appWillResignActive() {
        if self.session.isRunning {
            self.dismiss(animated: true, completion: nil)
        }
        if self.videoUrl != nil, let player = self.recordVideoPlayerLayer?.player {
            player.pause()
        }
    }
    
    @objc func appDidBecomeActive() {
        if self.videoUrl != nil, let player = self.recordVideoPlayerLayer?.player {
            player.play()
        }
    }
    
    @objc func handleAudioSessionInterruption(_ notify: Notification) {
        guard self.recordVideoPlayerLayer?.isHidden == false, let player = self.recordVideoPlayerLayer?.player else {
            return
        }
        guard player.rate == 0 else {
            return
        }
        
        let type = notify.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
        let option = notify.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
        if type == AVAudioSession.InterruptionType.ended.rawValue, option == AVAudioSession.InterruptionOptions.shouldResume.rawValue {
            player.play()
        }
    }
    
    @objc func dismissBtnClick() {
        self.dismiss(animated: true) {
            self.cancelBlock?()
        }
    }
    
    @objc func retakeBtnClick() {
        self.session.startRunning()
        self.resetSubViewStatus()
        self.takedImage = nil
        self.stopRecordAnimation()
        if let url = self.videoUrl {
            self.recordVideoPlayerLayer?.player?.pause()
            self.recordVideoPlayerLayer?.player = nil
            self.recordVideoPlayerLayer?.isHidden = true
            self.videoUrl = nil
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    @objc func switchCameraBtnClick() {
        do {
            guard !self.restartRecordAfterSwitchCamera else {
                return
            }
            
            guard let currInput = self.videoInput else {
                return
            }
            var newVideoInput: AVCaptureDeviceInput?
            if currInput.device.position == .back, let front = self.getCamera(position: .front) {
                newVideoInput = try AVCaptureDeviceInput(device: front)
            } else if currInput.device.position == .front, let back = self.getCamera(position: .back) {
                newVideoInput = try AVCaptureDeviceInput(device: back)
            } else {
                return
            }
            
            let zoomFactor = currInput.device.videoZoomFactor
            
            if let ni = newVideoInput {
                self.session.beginConfiguration()
                self.session.removeInput(currInput)
                if self.session.canAddInput(ni) {
                    self.session.addInput(ni)
                    self.videoInput = ni
                    ni.device.videoZoomFactor = zoomFactor
                } else {
                    self.session.addInput(currInput)
                }
                self.session.commitConfiguration()
                if self.movieFileOutput.isRecording {
                    let pauseTime = self.animateLayer.convertTime(CACurrentMediaTime(), from: nil)
                    self.animateLayer.speed = 0
                    self.animateLayer.timeOffset = pauseTime
                    self.restartRecordAfterSwitchCamera = true
                }
            }
        } catch {
            zl_debugPrint("切换摄像头失败 \(error.localizedDescription)")
        }
    }
    
    @objc func editImage() {
        guard ZLPhotoConfiguration.default().allowEditImage, let image = self.takedImage else {
            return
        }
        ZLEditImageViewController.showEditImageVC(parentVC: self, image: image) { [weak self] in
            self?.retakeBtnClick()
        } completion: { [weak self] (editImage, _) in
            self?.takedImage = editImage
            self?.takedImageView.image = editImage
            self?.doneBtnClick()
        }
    }
    
    @objc func doneBtnClick() {
        self.session.startRunning()
        self.recordVideoPlayerLayer?.player?.pause()
        
        let clean = { [weak self] in
            guard let self = self else { return }
            self.resetSubViewStatus()
            self.stopRecordAnimation()
            if let url = self.videoUrl {
                self.recordVideoPlayerLayer?.player?.pause()
                self.recordVideoPlayerLayer?.player = nil
                self.recordVideoPlayerLayer?.isHidden = true
                self.videoUrl = nil
                try? FileManager.default.removeItem(at: url)
            } else {
                self.takedImage = nil
                self.takedImageView.isHidden = true
            }
        }
        // 置为nil会导致卡顿，先注释，不影响内存释放
//        self.recordVideoPlayerLayer?.player = nil
        if let takeDoneBlock = self.takeDoneBlock {
            self.dismiss(animated: true) {
                self.takeDoneBlock?(self.takedImage, self.videoUrl)
                clean()
            }
        } else {
            self.save(image: self.takedImage, videoUrl: self.videoUrl) {
                clean()
            }
        }
    }
    
    func save(image: UIImage?, videoUrl: URL?, complete: (() -> Void)? = nil) {
        let hud = ZLProgressHUD(style: ZLPhotoConfiguration.default().hudStyle)
        if let image = image {
            hud.show()
            ZLPhotoManager.saveImageToAlbum(image: image) { [weak self] (suc, asset) in
                if suc, let at = asset {
                    let model = ZLPhotoModel(asset: at)
                    self?.handleDataArray(newModel: model)
                } else {
                    showAlertView(localLanguageTextValue(.saveImageError), self)
                }
                hud.hide()
                complete?()
            }
        } else if let videoUrl = videoUrl {
            let status = PHPhotoLibrary.authorizationStatus()
            
            if status == .denied || status == .restricted {
                showAlertView("library denied", self)
                return
            }
            let file = (videoUrl.absoluteString as NSString).replacingOccurrences(of: "file://", with: "")
            if FileManager.default.fileExists(atPath: file) == false {
                showAlertView("video not exist", self)
                return
            }
            hud.show()
            ZLPhotoManager.saveVideoToAlbum(url: videoUrl) { [weak self] (suc, asset) in
                if suc, let at = asset {
                    let model = ZLPhotoModel(asset: at)
                    self?.handleDataArray(newModel: model)
                } else {
                    showAlertView(localLanguageTextValue(.saveVideoError), self)
                }
                hud.hide()
                complete?()
            }
        }
    }
    
    func handleDataArray(newModel: ZLPhotoModel) {
        let nav = self.navigationController as? ZLImageNavController
        let config = ZLPhotoConfiguration.default()
        if let vc = thumbnailsVC {
            vc.handleDataArray(newModel: newModel)
            
        } else {
            var canSelect = true
            // If mixed selection is not allowed, and the newModel type is video, it will not be selected.
            if !config.allowMixSelect, newModel.type == .video {
                canSelect = false
            }
            if canSelect, canAddModel(newModel, currentSelectCount: nav?.arrSelectedModels.count ?? 0, sender: self, showAlert: false) {
                newModel.isSelected = true
                nav?.arrSelectedModels.append(newModel)
            }
        }
        nav?.selectImageBlock?()
        if ZLPhotoConfiguration.default().maxSelectCount == 1 {
            newModel.isSelected = false
            nav?.arrSelectedModels.removeAll(where: { $0.ident == newModel.ident })
        }
    }
    
    // 点击拍照
    @objc func takePicture() {
        guard ZLPhotoManager.hasCameraAuthority() else {
            return
        }
        
        let connection = self.imageOutput.connection(with: .video)
        connection?.videoOrientation = self.orientation
        if self.videoInput?.device.position == .front, connection?.isVideoMirroringSupported == true {
            connection?.isVideoMirrored = true
        }
        let setting = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecJPEG])
        if self.videoInput?.device.hasFlash == true {
            setting.flashMode = ZLPhotoConfiguration.default().cameraConfiguration.flashMode.avFlashMode
        }
        self.imageOutput.capturePhoto(with: setting, delegate: self)
    }
    
    // 长按录像
    @objc func longPressAction(_ longGes: UILongPressGestureRecognizer) {
        if longGes.state == .began {
            guard ZLPhotoManager.hasCameraAuthority(), ZLPhotoManager.hasMicrophoneAuthority() else {
                return
            }
            self.startRecord()
        } else if longGes.state == .cancelled || longGes.state == .ended {
            self.finishRecord()
        }
    }
    
    // 调整焦点
    @objc func adjustFocusPoint(_ tap: UITapGestureRecognizer) {
        guard self.session.isRunning else {
            return
        }
        let point = tap.location(in: self.view)
        if point.y > self.bottomView.frame.minY - 30 {
            return
        }
        self.setFocusCusor(point: point)
    }
    
    func setFocusCusor(point: CGPoint) {
        self.focusCursorView.center = point
        self.focusCursorView.layer.removeAllAnimations()
        self.focusCursorView.alpha = 1
        self.focusCursorView.layer.transform = CATransform3DMakeScale(1.2, 1.2, 1)
        UIView.animate(withDuration: 0.5, animations: {
            self.focusCursorView.layer.transform = CATransform3DIdentity
        }) { (_) in
            self.focusCursorView.alpha = 0
        }
        // ui坐标转换为摄像头坐标
        let cameraPoint = self.previewLayer?.captureDevicePointConverted(fromLayerPoint: point) ?? self.view.center
        self.focusCamera(
            mode: ZLPhotoConfiguration.default().cameraConfiguration.focusMode.avFocusMode,
            exposureMode: ZLPhotoConfiguration.default().cameraConfiguration.exposureMode.avFocusMode,
            point: cameraPoint
        )
    }
    
    // 调整焦距
    @objc func adjustCameraFocus(_ pan: UIPanGestureRecognizer) {
        let convertRect = self.bottomView.convert(self.largeCircleView.frame, to: self.view)
        let point = pan.location(in: self.view)
        
        if pan.state == .began {
            if !convertRect.contains(point) {
                return
            }
            self.dragStart = true
            self.startRecord()
        } else if pan.state == .changed {
            guard self.dragStart else {
                return
            }
            let maxZoomFactor = self.getMaxZoomFactor()
            var zoomFactor = (convertRect.midY - point.y) / convertRect.midY * maxZoomFactor
            zoomFactor = max(1, min(zoomFactor, maxZoomFactor))
            self.setVideoZoomFactor(zoomFactor)
        } else if pan.state == .cancelled || pan.state == .ended {
            guard self.dragStart else {
                return
            }
            self.dragStart = false
            self.finishRecord()
        }
    }
    
    @objc func pinchToAdjustCameraFocus(_ pinch: UIPinchGestureRecognizer) {
        guard let device = self.videoInput?.device else {
            return
        }
        
        var zoomFactor = device.videoZoomFactor * pinch.scale
        zoomFactor = max(1, min(zoomFactor, self.getMaxZoomFactor()))
        self.setVideoZoomFactor(zoomFactor)
        
        pinch.scale = 1
    }
    
    func getMaxZoomFactor() -> CGFloat {
        guard let device = self.videoInput?.device else {
            return 1
        }
        if #available(iOS 11.0, *) {
            return device.maxAvailableVideoZoomFactor
        } else {
            return device.activeFormat.videoMaxZoomFactor
        }
    }
    
    func setVideoZoomFactor(_ zoomFactor: CGFloat) {
        guard let device = self.videoInput?.device else {
            return
        }
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = zoomFactor
            device.unlockForConfiguration()
        } catch {
            zl_debugPrint("调整焦距失败 \(error.localizedDescription)")
        }
    }
    
    
    func focusCamera(mode: AVCaptureDevice.FocusMode, exposureMode: AVCaptureDevice.ExposureMode, point: CGPoint) {
        do {
            guard let device = self.videoInput?.device else {
                return
            }
            
            try device.lockForConfiguration()
            
            if device.isFocusModeSupported(mode) {
                device.focusMode = mode
            }
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = point
            }
            if device.isExposureModeSupported(exposureMode) {
                device.exposureMode = exposureMode
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
            }
            
            device.unlockForConfiguration()
        } catch {
            zl_debugPrint("相机聚焦设置失败 \(error.localizedDescription)")
        }
    }
    
    func startRecord() {
        guard !self.movieFileOutput.isRecording else {
            return
        }
        self.dismissBtn.isHidden = true
        let connection = self.movieFileOutput.connection(with: .video)
        connection?.videoScaleAndCropFactor = 1
        if !self.restartRecordAfterSwitchCamera {
            connection?.videoOrientation = self.orientation
            self.cacheVideoOrientation = self.orientation
        } else {
            connection?.videoOrientation = self.cacheVideoOrientation
        }
        // 解决前置摄像头录制视频时候左右颠倒的问题
        if self.videoInput?.device.position == .front, connection?.isVideoMirroringSupported == true {
            // 镜像设置
            connection?.isVideoMirrored = true
        }
        let url = URL(fileURLWithPath: ZLVideoManager.getVideoExportFilePath())
        self.movieFileOutput.startRecording(to: url, recordingDelegate: self)
    }
    
    func finishRecord() {
        guard self.movieFileOutput.isRecording else {
            return
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        self.movieFileOutput.stopRecording()
        self.stopRecordAnimation()
    }
    
    func startRecordAnimation() {
        UIView.animate(withDuration: 0.1, animations: {
            self.largeCircleView.layer.transform = CATransform3DScale(CATransform3DIdentity, ZLCustomCamera.Layout.largeCircleRecordScale, ZLCustomCamera.Layout.largeCircleRecordScale, 1)
            self.smallCircleView.layer.transform = CATransform3DScale(CATransform3DIdentity, ZLCustomCamera.Layout.smallCircleRecordScale, ZLCustomCamera.Layout.smallCircleRecordScale, 1)
        }) { (_) in
            self.largeCircleView.layer.addSublayer(self.animateLayer)
            let animation = CABasicAnimation(keyPath: "strokeEnd")
            animation.fromValue = 0
            animation.toValue = 1
            animation.duration = Double(ZLPhotoConfiguration.default().maxRecordDuration)
            animation.delegate = self
            self.animateLayer.add(animation, forKey: nil)
        }
    }
    
    func stopRecordAnimation() {
        self.animateLayer.removeFromSuperlayer()
        self.animateLayer.removeAllAnimations()
        self.largeCircleView.transform = .identity
        self.smallCircleView.transform = .identity
    }
    
    public func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        self.finishRecord()
    }
    
    func resetSubViewStatus() {

        if self.session.isRunning {
            self.showTipsLabel(animate: true)
            self.bottomView.isHidden = false
            self.switchCameraBtn.isHidden = false
            self.retakeBtn.isHidden = true
            self.doneBtn.isHidden = true
            self.takedImageView.isHidden = true
            self.takedImage = nil
            self.dismissBtn.isHidden = false
        } else {
            self.hideTipsLabel(animate: false)
            self.bottomView.isHidden = true
            self.switchCameraBtn.isHidden = true
            self.retakeBtn.isHidden = false
            self.doneBtn.isHidden = false
            self.dismissBtn.isHidden = true

        }
    }
    
    func playRecordVideo(fileUrl: URL) {
        self.recordVideoPlayerLayer?.isHidden = false
        let player = AVPlayer(url: fileUrl)
        player.automaticallyWaitsToMinimizeStalling = false
        self.recordVideoPlayerLayer?.player = player
        player.play()
    }
    
    @objc func recordVideoPlayFinished() {
        self.recordVideoPlayerLayer?.player?.seek(to: .zero)
        self.recordVideoPlayerLayer?.player?.play()
    }

}


extension ZLCustomCamera: AVCapturePhotoCaptureDelegate {
    
    public func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        DispatchQueue.main.async {
            self.previewLayer?.opacity = 0
            UIView.animate(withDuration: 0.25) {
                self.previewLayer?.opacity = 1
            }
        }
    }
    
    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photoSampleBuffer: CMSampleBuffer?, previewPhoto previewPhotoSampleBuffer: CMSampleBuffer?, resolvedSettings: AVCaptureResolvedPhotoSettings, bracketSettings: AVCaptureBracketedStillImageSettings?, error: Error?) {
        ZLMainAsync {
            if photoSampleBuffer == nil || error != nil {
                zl_debugPrint("拍照失败 \(error?.localizedDescription ?? "")")
                return
            }
            
            if let data = AVCapturePhotoOutput.jpegPhotoDataRepresentation(forJPEGSampleBuffer: photoSampleBuffer!, previewPhotoSampleBuffer: previewPhotoSampleBuffer) {
                self.session.stopRunning()
                self.takedImage = UIImage(data: data)?.fixOrientation()
                self.takedImageView.image = self.takedImage
                self.takedImageView.isHidden = false
                self.resetSubViewStatus()
                self.editImage()
            } else {
                zl_debugPrint("拍照失败，data为空")
            }
        }
    }
    
}


extension ZLCustomCamera: AVCaptureFileOutputRecordingDelegate {
    
    public func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        if self.restartRecordAfterSwitchCamera {
            self.restartRecordAfterSwitchCamera = false
            // 稍微加一个延时，否则切换摄像头后拍摄时间会略小于设置的最大值
            ZLMainAsync(after: 0.1) {
                let pauseTime = self.animateLayer.timeOffset
                self.animateLayer.speed = 1
                self.animateLayer.timeOffset = 0
                self.animateLayer.beginTime = 0
                let timeSincePause = self.animateLayer.convertTime(CACurrentMediaTime(), from: nil) - pauseTime
                self.animateLayer.beginTime = timeSincePause
            }
        } else {
            ZLMainAsync {
                self.startRecordAnimation()
            }
        }
    }
    
    public func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        ZLMainAsync {
            if self.restartRecordAfterSwitchCamera {
                self.recordUrls.append(outputFileURL)
                self.startRecord()
                return
            }
            self.recordUrls.append(outputFileURL)
            
            var duration: Double = 0
            if self.recordUrls.count == 1 {
                duration = output.recordedDuration.seconds
            } else {
                for url in self.recordUrls {
                    let temp = AVAsset(url: url)
                    duration += temp.duration.seconds
                }
            }
            
            // 重置焦距
            self.setVideoZoomFactor(1)
            if duration < Double(ZLPhotoConfiguration.default().minRecordDuration) {
                showAlertView(String(format: localLanguageTextValue(.minRecordTimeTips), ZLPhotoConfiguration.default().minRecordDuration), self)
                self.resetSubViewStatus()
                self.recordUrls.forEach { try? FileManager.default.removeItem(at: $0) }
                self.recordUrls.removeAll()
                return
            }
            
            // 拼接视频
            self.session.stopRunning()
            self.resetSubViewStatus()
            if self.recordUrls.count > 1 {
                ZLVideoManager.mergeVideos(fileUrls: self.recordUrls) { [weak self] (url, error) in
                    if let url = url, error == nil {
                        self?.videoUrl = url
                        self?.playRecordVideo(fileUrl: url)
                    } else if let error = error {
                        self?.videoUrl = nil
                        showAlertView(error.localizedDescription, self)
                    }

                    self?.recordUrls.forEach { try? FileManager.default.removeItem(at: $0) }
                    self?.recordUrls.removeAll()
                }
            } else {
                self.videoUrl = outputFileURL
                self.playRecordVideo(fileUrl: outputFileURL)
                self.recordUrls.removeAll()
            }
        }
    }
    
}


extension ZLCustomCamera: UIGestureRecognizerDelegate {
    
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
//        if gestureRecognizer is UILongPressGestureRecognizer, otherGestureRecognizer is UIPanGestureRecognizer {
//            return true
//        }
        return true
    }
    
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if gestureRecognizer is UIPanGestureRecognizer, touch.view is UIControl {
            // 解决拖动改变焦距时，无法点击其他按钮的问题
            return false
        }
        return true
    }
    
}

