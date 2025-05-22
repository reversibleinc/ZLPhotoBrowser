//
//  ZLEditVideoViewController.swift
//  ZLPhotoBrowser
//
//  Created by long on 2020/8/30.
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
import Photos

public class ZLEditVideoViewController: UIViewController {

    static let frameImageSize = CGSize(width: CGFloat(round(50.0 * 2.0 / 3.0)), height: 50.0)
    
    let avAsset: AVAsset
    
    let timeRange: CMTimeRange?
    
    let animateDismiss: Bool
    
    var cancelBtn: UIButton!
    
    var doneBtn: UIButton!
    
    var timer: Timer?
    
    var playerLayer: AVPlayerLayer!
    
    var collectionView: UICollectionView!
    
    var frameImageBorderView: ZLEditVideoFrameImageBorderView!
    
    var leftSideView: UIImageView!
    
    var rightSideView: UIImageView!
    
    var leftSidePan: UIPanGestureRecognizer!
    
    var rightSidePan: UIPanGestureRecognizer!
    
    var frameSidePan: UIPanGestureRecognizer!

    var indicator: UIView!
    
    var measureCount = 0
    
    lazy var interval: TimeInterval = {
        let assetDuration = round(self.avAsset.duration.seconds)
        return min(assetDuration, TimeInterval(ZLPhotoConfiguration.default().maxEditVideoTime)) / 10
    }()
    
    var requestFrameImageQueue: OperationQueue!
    
    var avAssetRequestID = PHInvalidImageRequestID
    
    var videoRequestID = PHInvalidImageRequestID
    
    public var frameImageCache: [Int: UIImage] = [:]
    
    var requestFailedFrameImageIndex: [Int] = []
    
    var shouldLayout = true
    var timeLabel = UILabel(frame: CGRect.zero)
    lazy var generator: AVAssetImageGenerator = {
        let g = AVAssetImageGenerator(asset: self.avAsset)
        g.maximumSize = CGSize(width: ZLEditVideoViewController.frameImageSize.width * 3, height: ZLEditVideoViewController.frameImageSize.height * 3)
        g.appliesPreferredTrackTransform = true
        g.requestedTimeToleranceBefore = .zero
        g.requestedTimeToleranceAfter = .zero
        g.apertureMode = .productionAperture
        return g
    }()
    
    public var didGenerateThumbnails: (([Int: UIImage]) -> Void)?
    public var editFinishBlock: ( (URL?, CMTimeRange?, UIImage?) -> Void )?
    
    public override var prefersStatusBarHidden: Bool {
        return true
    }
    
    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
    
    deinit {
        zl_debugPrint("ZLEditVideoViewController deinit")
        self.cleanTimer()
        self.requestFrameImageQueue.cancelAllOperations()
        if self.avAssetRequestID > PHInvalidImageRequestID {
            PHImageManager.default().cancelImageRequest(self.avAssetRequestID)
        }
        if self.videoRequestID > PHInvalidImageRequestID {
            PHImageManager.default().cancelImageRequest(self.videoRequestID)
        }
        if let timeObserver = timeObserver {
            self.playerLayer.player?.removeTimeObserver(timeObserver)
        }
    }
    
    
    /// initialize
    /// - Parameters:
    ///   - avAsset: AVAsset对象，需要传入本地视频，网络视频不支持
    ///   - animateDismiss: 退出界面时是否显示dismiss动画
    public init(avAsset: AVAsset, animateDismiss: Bool = false, range: CMTimeRange? = nil) {
        self.avAsset = avAsset
        self.animateDismiss = animateDismiss
        self.timeRange = range
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()

        self.setupUI()
        
        self.requestFrameImageQueue = OperationQueue()
        self.requestFrameImageQueue.maxConcurrentOperationCount = 10
        
        NotificationCenter.default.addObserver(self, selector: #selector(appWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        self.analysisAssetImages()
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        self.cleanTimer()
    }
    
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard self.shouldLayout else {
            return
        }
        self.shouldLayout = false
        
        zl_debugPrint("edit video layout subviews")
        var insets = UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0)
        if #available(iOS 11.0, *) {
            insets = self.view.safeAreaInsets
        }
        
        let btnH = ZLLayout.bottomToolBtnH
        let bottomBtnAndColSpacing: CGFloat = 20
        let playerLayerY = insets.top + 20
        let diffBottom = btnH + ZLEditVideoViewController.frameImageSize.height + bottomBtnAndColSpacing + insets.bottom + 40
        
        self.playerLayer.frame = CGRect(x: 15, y: insets.top + 20, width: self.view.bounds.width - 30, height: self.view.bounds.height - playerLayerY - diffBottom)
        self.timeLabel.frame = CGRect(x: 20, y: self.playerLayer.frame.maxY, width: self.view.bounds.width - 40, height: 20)
        self.timeLabel.textAlignment = .center
        let cancelBtnW = localLanguageTextValue(.cancel).boundingRect(font: ZLLayout.bottomToolTitleFont, limitSize: CGSize(width: CGFloat.greatestFiniteMagnitude, height: btnH)).width
        self.cancelBtn.frame = CGRect(x: 20, y: self.view.bounds.height - insets.bottom - btnH, width: cancelBtnW, height: btnH)
        let doneBtnW = localLanguageTextValue(.done).boundingRect(font: ZLLayout.bottomToolTitleFont, limitSize: CGSize(width: CGFloat.greatestFiniteMagnitude, height: btnH)).width + 20
        self.doneBtn.frame = CGRect(x: self.view.bounds.width-doneBtnW-20, y: self.view.bounds.height - insets.bottom - btnH, width: doneBtnW, height: btnH)
        
        self.collectionView.frame = CGRect(x: 0, y: self.doneBtn.frame.minY - bottomBtnAndColSpacing - ZLEditVideoViewController.frameImageSize.height, width: self.view.bounds.width, height: ZLEditVideoViewController.frameImageSize.height)
        
        let frameViewW = ZLEditVideoViewController.frameImageSize.width * 10
        
        self.frameImageBorderView.frame = CGRect(x: (self.view.bounds.width - frameViewW)/2, y: self.collectionView.frame.minY, width: frameViewW, height: ZLEditVideoViewController.frameImageSize.height)
        
        if let timeRange = timeRange {
            let leftRightSideViewW = ZLEditVideoViewController.frameImageSize.width/2

            let startX = Double(timeRange.start.value) /  Double(timeRange.start.timescale) / Double(self.interval) * ZLEditVideoViewController.frameImageSize.width + self.frameImageBorderView.frame.minX
            let endX = Double(timeRange.end.value) /  Double(timeRange.end.timescale) / Double(self.interval) * ZLEditVideoViewController.frameImageSize.width + self.frameImageBorderView.frame.minX
            
            self.leftSideView.frame = CGRect(x: startX, y: self.collectionView.frame.minY, width: leftRightSideViewW, height: ZLEditVideoViewController.frameImageSize.height)
            self.rightSideView.frame = CGRect(x: endX, y: self.collectionView.frame.minY, width: leftRightSideViewW, height: ZLEditVideoViewController.frameImageSize.height)
            let maxX = self.frameImageBorderView.frame.maxX - self.rightSideView.frame.width
            if self.rightSideView.frame.minX > maxX {
                self.rightSideView.frame = CGRect(x: maxX, y: self.collectionView.frame.minY, width: leftRightSideViewW, height: ZLEditVideoViewController.frameImageSize.height)
            }

            self.frameImageBorderView.validRect = self.frameImageBorderView.convert(self.clipRect(), from: self.view)

        } else {
            let leftRightSideViewW = ZLEditVideoViewController.frameImageSize.width/2

            // 左右拖动view
            self.leftSideView.frame = CGRect(x: self.frameImageBorderView.frame.minX, y: self.collectionView.frame.minY, width: leftRightSideViewW, height: ZLEditVideoViewController.frameImageSize.height)
            let rightSideViewX = self.view.bounds.width - self.frameImageBorderView.frame.minX - leftRightSideViewW
            self.rightSideView.frame = CGRect(x: rightSideViewX, y: self.collectionView.frame.minY, width: leftRightSideViewW, height: ZLEditVideoViewController.frameImageSize.height)
            
            self.frameImageBorderView.validRect = self.frameImageBorderView.convert(self.clipRect(), from: self.view)
        }
        self.indicator.frame = CGRect(x: self.leftSideView.frame.minX + 8, y: self.leftSideView.frame.minY, width: 2, height: self.leftSideView.frame.height)
    }
    
    func setupUI() {
        self.view.backgroundColor = .black
        
        self.playerLayer = AVPlayerLayer()
        self.playerLayer.videoGravity = .resizeAspect
        self.view.layer.addSublayer(self.playerLayer)
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didClickPlayer(_:)))
        self.view.addGestureRecognizer(tapGesture)
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = ZLEditVideoViewController.frameImageSize
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.scrollDirection = .horizontal
        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        self.collectionView.backgroundColor = .clear
        self.collectionView.delegate = self
        self.collectionView.dataSource = self
        self.collectionView.showsHorizontalScrollIndicator = false
        self.view.addSubview(self.collectionView)
        self.view.addSubview(self.timeLabel)
        self.timeLabel.font = UIFont.systemFont(ofSize: 10)
        self.timeLabel.textColor = UIColor.white
        
        ZLEditVideoFrameImageCell.zl_register(self.collectionView)
        
        self.frameImageBorderView = ZLEditVideoFrameImageBorderView()
        self.frameImageBorderView.isUserInteractionEnabled = false
        self.view.addSubview(self.frameImageBorderView)
        
        self.indicator = UIView()
        self.indicator.backgroundColor = UIColor.white.withAlphaComponent(0.7)
        self.view.addSubview(self.indicator)
        
        self.leftSideView = UIImageView(image: getImage("zl_ic_left"))
        self.leftSideView.isUserInteractionEnabled = true
        self.view.addSubview(self.leftSideView)
        
        self.frameSidePan = UIPanGestureRecognizer(target: self, action: #selector(frameSidePanAction(_:)))
        self.frameSidePan.delegate = self
        self.view.addGestureRecognizer(self.frameSidePan)
        
        self.leftSidePan = UIPanGestureRecognizer(target: self, action: #selector(leftSidePanAction(_:)))
        self.leftSidePan.delegate = self
        self.view.addGestureRecognizer(self.leftSidePan)
        
        self.rightSideView = UIImageView(image: getImage("zl_ic_right"))
        self.rightSideView.isUserInteractionEnabled = true
        self.view.addSubview(self.rightSideView)
        
        self.rightSidePan = UIPanGestureRecognizer(target: self, action: #selector(rightSidePanAction(_:)))
        self.rightSidePan.delegate = self
        self.view.addGestureRecognizer(self.rightSidePan)
        
        self.collectionView.panGestureRecognizer.require(toFail: self.leftSidePan)
        self.collectionView.panGestureRecognizer.require(toFail: self.rightSidePan)
        self.rightSidePan.require(toFail: self.leftSidePan)
        
        self.cancelBtn = UIButton(type: .custom)
        self.cancelBtn.setImage(getImage("video_edit_close"), for: .normal)
//        self.cancelBtn.setTitle(localLanguageTextValue(.cancel), for: .normal)
        self.cancelBtn.setTitleColor(.bottomToolViewBtnNormalTitleColor, for: .normal)
        self.cancelBtn.titleLabel?.font = ZLLayout.bottomToolTitleFont
        self.cancelBtn.addTarget(self, action: #selector(cancelBtnClick), for: .touchUpInside)
        self.view.addSubview(self.cancelBtn)
        
        self.doneBtn = UIButton(type: .custom)
        self.doneBtn.setImage(getImage("video_edit_done"), for: .normal)
//        self.doneBtn.setTitle(localLanguageTextValue(.done), for: .normal)
        self.doneBtn.setTitleColor(.bottomToolViewBtnNormalTitleColor, for: .normal)
        self.doneBtn.titleLabel?.font = ZLLayout.bottomToolTitleFont
        self.doneBtn.addTarget(self, action: #selector(doneBtnClick), for: .touchUpInside)
        self.doneBtn.backgroundColor = .bottomToolViewBtnNormalBgColor
        self.doneBtn.layer.masksToBounds = true
        self.doneBtn.layer.cornerRadius = ZLLayout.bottomToolBtnCornerRadius
        self.view.addSubview(self.doneBtn)
    }
    
    @objc func cancelBtnClick() {
        self.dismiss(animated: self.animateDismiss, completion: nil)
    }
    
    @objc func doneBtnClick() {
        self.cleanTimer()
        
        let d = CGFloat(self.interval) * self.clipRect().width / ZLEditVideoViewController.frameImageSize.width
        if Second(round(d)) < ZLPhotoConfiguration.default().minSelectVideoDuration {
            let message = String(format: localLanguageTextValue(.shorterThanMaxVideoDuration), ZLPhotoConfiguration.default().minSelectVideoDuration)
            showAlertView(message, self)
            return
        }
        if Second(round(d)) > ZLPhotoConfiguration.default().maxSelectVideoDuration {
            let message = String(format: localLanguageTextValue(.longerThanMaxVideoDuration), ZLPhotoConfiguration.default().maxSelectVideoDuration)
            showAlertView(message, self)
            return
        }
        
        if d == round(CGFloat(self.avAsset.duration.seconds)) {
            self.dismiss(animated: self.animateDismiss) {
                self.editFinishBlock?(nil, nil, nil)
            }
            return
        }
        
        let hud = ZLProgressHUD(style: ZLPhotoConfiguration.default().hudStyle)
        hud.show()
        
        ZLVideoManager.exportEditVideo(for: avAsset, range: self.getTimeRange()) { [weak self] (url, error) in
            hud.hide()
            if let er = error {
                showAlertView(er.localizedDescription, self)
            } else if let url = url {
                self?.dismiss(animated: self?.animateDismiss ?? false) {
                    self?.editFinishBlock?(url, self?.getTimeRange(), ZLVideoManager.getVideoFirstFrame(for: url))
                }
            }
        }
    }
    
    
    @objc func didClickPlayer(_ tap: UITapGestureRecognizer) {
        self.playerLayer.player?.timeControlStatus == .playing ?  self.playerLayer.player?.pause() : self.playerLayer.player?.play()
    }
    
    @objc func frameSidePanAction(_ pan: UIPanGestureRecognizer) {
        let point = pan.location(in: self.view)
        let playerPoint = self.view.convert(point, to: self.frameImageBorderView)
        let second = max(0, CGFloat(self.interval) * playerPoint.x / ZLEditVideoViewController.frameImageSize.width)
        let time = CMTimeMakeWithSeconds(Float64(second), preferredTimescale: self.avAsset.duration.timescale)
        if pan.state == .began {
            self.frameImageBorderView.layer.borderColor = UIColor(white: 1, alpha: 0.4).cgColor
            self.cleanTimer()
        } else if pan.state == .changed {
            self.playerLayer.player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        } else if pan.state == .ended || pan.state == .cancelled {
            self.playerLayer.player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
            self.frameImageBorderView.layer.borderColor = UIColor.clear.cgColor
            self.startTimer()
        }
    }
    
    @objc func leftSidePanAction(_ pan: UIPanGestureRecognizer) {
        let point = pan.location(in: self.view)
        
        if pan.state == .began {
            self.frameImageBorderView.layer.borderColor = UIColor(white: 1, alpha: 0.4).cgColor
            self.cleanTimer()
        } else if pan.state == .changed {
            let minX = self.frameImageBorderView.frame.minX
            let maxX = self.rightSideView.frame.minX - self.leftSideView.frame.width
            
            var frame = self.leftSideView.frame
            frame.origin.x = min(maxX, max(minX, point.x))
            self.leftSideView.frame = frame
            self.frameImageBorderView.validRect = self.frameImageBorderView.convert(self.clipRect(), from: self.view)
            
            self.playerLayer.player?.seek(to: self.getStartTime(), toleranceBefore: .zero, toleranceAfter: .zero)
        } else if pan.state == .ended || pan.state == .cancelled {
            self.frameImageBorderView.layer.borderColor = UIColor.clear.cgColor
            self.startTimer()
        }
    }
    
    @objc func rightSidePanAction(_ pan: UIPanGestureRecognizer) {
        let point = pan.location(in: self.view)
        
        if pan.state == .began {
            self.frameImageBorderView.layer.borderColor = UIColor(white: 1, alpha: 0.4).cgColor
            self.cleanTimer()
        } else if pan.state == .changed {
            let minX = self.leftSideView.frame.maxX
            let maxX = self.frameImageBorderView.frame.maxX - self.rightSideView.frame.width
            
            var frame = self.rightSideView.frame
            frame.origin.x = min(maxX, max(minX, point.x))
            self.rightSideView.frame = frame
            self.frameImageBorderView.validRect = self.frameImageBorderView.convert(self.clipRect(), from: self.view)
            
            self.playerLayer.player?.seek(to:self.getTimeRange().start + self.getTimeRange().duration, toleranceBefore: .zero, toleranceAfter: .zero)
        } else if pan.state == .ended || pan.state == .cancelled {
            self.frameImageBorderView.layer.borderColor = UIColor.clear.cgColor
            self.playerLayer.player?.seek(to: self.getStartTime(), toleranceBefore: .zero, toleranceAfter: .zero)
            self.startTimer()
        }
    }
    
    @objc func appWillResignActive() {
        self.cleanTimer()
        self.indicator.layer.removeAllAnimations()
    }
    
    @objc func appDidBecomeActive() {
        self.startTimer()
    }

    
    var timeObserver: Any?
    func analysisAssetImages() {
        let duration = round(self.avAsset.duration.seconds)
        guard duration > 0 else {
            self.showFetchFailedAlert()
            return
        }
        if let timeObserver = timeObserver {
            self.playerLayer.player?.removeTimeObserver(timeObserver)
        }
        let item = AVPlayerItem(asset: self.avAsset)
        let player = AVPlayer(playerItem: item)
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 5), queue: .main) { [weak self]time in
            guard let self = self else { return }
            let second = time.seconds
            print(second)
            if second < (self.getStartTime().seconds) - 0.2 {
                self.playerLayer.player?.seek(to: self.getStartTime(), toleranceBefore: .zero, toleranceAfter: .zero)
            } else if second > (self.interval * TimeInterval(self.clipRect().width / ZLEditVideoViewController.frameImageSize.width) + self.getStartTime().seconds) {
                self.playerLayer.player?.seek(to: self.getStartTime(), toleranceBefore: .zero, toleranceAfter: .zero)
            } else {
                self.playerTimeUpdate(second)
            }
        }
        self.playerLayer.player = player
        if let timeRange = timeRange {
            self.playerLayer.player?.seek(to: timeRange.start)
        }
        self.startTimer()
        
        self.measureCount = Int(duration / self.interval)
        self.collectionView.reloadData()
        self.requestVideoMeasureFrameImage()
    }
    
    func timeString(_ dur: Int) -> String {
        switch dur {
        case 0..<60:
            return String(format: "00:%02d", dur)
        case 60..<3600:
            let m = dur / 60
            let s = dur % 60
            return String(format: "%02d:%02d", m, s)
        case 3600...:
            let h = dur / 3600
            let m = (dur % 3600) / 60
            let s = dur % 60
            return String(format: "%02d:%02d:%02d", h, m, s)
        default:
            return ""
        }
    }
    
    func playerTimeUpdate(_ time: Double) {
        let startTime = Double(self.getStartTime().value) / Double(self.getStartTime().timescale)
        let duration = self.interval * TimeInterval(self.clipRect().width / ZLEditVideoViewController.frameImageSize.width)
        let minX = self.leftSideView.frame.minX + 8
        let maxX = self.rightSideView.frame.maxX - 8
        let curX = minX + (maxX - minX) * (time - startTime) / duration
        if self.indicator.frame.size.width == 0 {
            self.indicator
        }
        UIView.animate(withDuration: self.playerLayer.player!.timeControlStatus == .playing ? 0.2 : 0, delay: 0, options: .curveLinear, animations: {
            self.indicator.frame = CGRect(x: curX, y: self.rightSideView.frame.minY, width: 2, height: self.rightSideView.frame.height)
        }, completion: nil)
        var cur = max(0, Int(self.playerLayer.player!.currentTime().seconds - self.getStartTime().seconds))
        if self.rightSidePan.state == .changed {
            cur = 0
        }
        self.timeLabel.text = self.timeString(cur) + "/" + self.timeString(Int(self.getTimeRange().duration.seconds))
    }
    
    func requestVideoMeasureFrameImage() {
        if self.frameImageCache.values.count == self.measureCount {
            self.collectionView.reloadData()
            return
        }
        for i in 0..<self.measureCount {
            let mes = TimeInterval(i) * self.interval
            let time = CMTimeMakeWithSeconds(Float64(mes), preferredTimescale: self.avAsset.duration.timescale)
            
            let operation = ZLEditVideoFetchFrameImageOperation(generator: self.generator, time: time) { [weak self] (image, time) in
                guard let self = self else { return }

                self.frameImageCache[Int(i)] = image
                let cell = self.collectionView.cellForItem(at: IndexPath(row: Int(i), section: 0)) as? ZLEditVideoFrameImageCell
                cell?.imageView.image = image
                if image == nil {
                    self.requestFailedFrameImageIndex.append(i)
                }
                self.didGenerateThumbnails?(self.frameImageCache)
            }
            self.requestFrameImageQueue.addOperation(operation)
        }
    }
    
    @objc func playPartVideo() {
        self.playerLayer.player?.seek(to: self.getStartTime(), toleranceBefore: .zero, toleranceAfter: .zero)
        if (self.playerLayer.player?.rate ?? 0) == 0 {
            self.playerLayer.player?.play()
        }
    }
    
    func startTimer() {
        self.playerLayer.player?.play()
    }
    
    func cleanTimer() {
        self.playerLayer.player?.pause()
    }
    
    func getStartTime() -> CMTime {
        var rect = self.collectionView.convert(self.clipRect(), from: self.view)
        rect.origin.x -= self.frameImageBorderView.frame.minX
        let second = max(0, CGFloat(self.interval) * rect.minX / ZLEditVideoViewController.frameImageSize.width)
        return CMTimeMakeWithSeconds(Float64(second), preferredTimescale: self.avAsset.duration.timescale)
    }
    
    func getTimeRange() -> CMTimeRange {
        let start = self.getStartTime()
        let d = CGFloat(self.interval) * self.clipRect().width / ZLEditVideoViewController.frameImageSize.width
        let duration = CMTimeMakeWithSeconds(Float64(d), preferredTimescale: self.avAsset.duration.timescale)
        return CMTimeRangeMake(start: start, duration: duration)
    }
    
    func clipRect() -> CGRect {
        var frame = CGRect.zero
        frame.origin.x = self.leftSideView.frame.minX
        frame.origin.y = self.leftSideView.frame.minY
        frame.size.width = self.rightSideView.frame.maxX - frame.minX
        frame.size.height = self.leftSideView.frame.height
        return frame
    }
    
    func showFetchFailedAlert() {
        let alert = UIAlertController(title: nil, message: localLanguageTextValue(.iCloudVideoLoadFaild), preferredStyle: .alert)
        let action = UIAlertAction(title: localLanguageTextValue(.ok), style: .default) { (_) in
            self.dismiss(animated: false, completion: nil)
        }
        alert.addAction(action)
        showAlertController(alert)
    }
    
}


extension ZLEditVideoViewController: UIGestureRecognizerDelegate {
    
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer == self.leftSidePan {
            let point = gestureRecognizer.location(in: self.view)
            let frame = self.leftSideView.frame
            let outerFrame = frame.inset(by: UIEdgeInsets(top: -20, left: -40, bottom: -20, right: -20))
            return outerFrame.contains(point)
        } else if gestureRecognizer == self.rightSidePan {
            let point = gestureRecognizer.location(in: self.view)
            let frame = self.rightSideView.frame
            let outerFrame = frame.inset(by: UIEdgeInsets(top: -20, left: -20, bottom: -20, right: -40))
            return outerFrame.contains(point)
        } else if gestureRecognizer == self.frameSidePan {
            let point = gestureRecognizer.location(in: self.view)
            let frame = self.clipRect()
            return frame.contains(point)
        }
        return true
    }
    
}


extension ZLEditVideoViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        self.cleanTimer()
        self.playerLayer.player?.seek(to: self.getStartTime(), toleranceBefore: .zero, toleranceAfter: .zero)
    }
    
    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            self.startTimer()
        }
    }
    
    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        self.startTimer()
    }
    
    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        let w = ZLEditVideoViewController.frameImageSize.width * 10
        let leftRight = (collectionView.frame.width - w) / 2
        return UIEdgeInsets(top: 0, left: leftRight, bottom: 0, right: leftRight)
    }
    
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return self.measureCount
    }
    
    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ZLEditVideoFrameImageCell.zl_identifier(), for: indexPath) as! ZLEditVideoFrameImageCell
        
        if let image = self.frameImageCache[indexPath.row] {
            cell.imageView.image = image
        }
        
        return cell
    }
    
    public func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if self.requestFailedFrameImageIndex.contains(indexPath.row) {
            let mes = TimeInterval(indexPath.row) * self.interval
            let time = CMTimeMakeWithSeconds(Float64(mes), preferredTimescale: self.avAsset.duration.timescale)
            
            let operation = ZLEditVideoFetchFrameImageOperation(generator: self.generator, time: time) { [weak self] (image, time) in
                self?.frameImageCache[indexPath.row] = image
                let cell = self?.collectionView.cellForItem(at: IndexPath(row: indexPath.row, section: 0)) as? ZLEditVideoFrameImageCell
                cell?.imageView.image = image
                if image != nil {
                    self?.requestFailedFrameImageIndex.removeAll { $0 == indexPath.row }
                }
            }
            self.requestFrameImageQueue.addOperation(operation)
        }
    }
    
}


class ZLEditVideoFrameImageBorderView: UIView {
    
    var validRect: CGRect = .zero {
        didSet {
            self.setNeedsDisplay()
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.layer.borderWidth = 2
        self.layer.borderColor = UIColor.clear.cgColor
        self.backgroundColor = .clear
        self.isOpaque = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ rect: CGRect) {
        let context = UIGraphicsGetCurrentContext()
        context?.setStrokeColor(UIColor.white.cgColor)
        context?.setLineWidth(4)
        
        context?.move(to: CGPoint(x: self.validRect.minX, y: 0))
        context?.addLine(to: CGPoint(x: self.validRect.minX+self.validRect.width, y: 0))
        
        context?.move(to: CGPoint(x: self.validRect.minX, y: rect.height))
        context?.addLine(to: CGPoint(x: self.validRect.minX+self.validRect.width, y: rect.height))
        
        context?.strokePath()
    }
    
}


class ZLEditVideoFrameImageCell: UICollectionViewCell {
    
    var imageView: UIImageView!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        self.imageView = UIImageView()
        self.imageView.contentMode = .scaleAspectFill
        self.imageView.clipsToBounds = true
        self.contentView.addSubview(self.imageView)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        self.imageView.frame = self.bounds
    }
    
}


class ZLEditVideoFetchFrameImageOperation: Operation {

    let generator: AVAssetImageGenerator
    
    let time: CMTime
    
    let completion: ( (UIImage?, CMTime) -> Void )
    
    var pri_isExecuting = false {
        willSet {
            self.willChangeValue(forKey: "isExecuting")
        }
        didSet {
            self.didChangeValue(forKey: "isExecuting")
        }
    }
    
    override var isExecuting: Bool {
        return self.pri_isExecuting
    }
    
    var pri_isFinished = false {
        willSet {
            self.willChangeValue(forKey: "isFinished")
        }
        didSet {
            self.didChangeValue(forKey: "isFinished")
        }
    }
    
    override var isFinished: Bool {
        return self.pri_isFinished
    }
    
    var pri_isCancelled = false {
        willSet {
            self.willChangeValue(forKey: "isCancelled")
        }
        didSet {
            self.didChangeValue(forKey: "isCancelled")
        }
    }

    override var isCancelled: Bool {
        return self.pri_isCancelled
    }
    
    init(generator: AVAssetImageGenerator, time: CMTime, completion: @escaping ( (UIImage?, CMTime) -> Void )) {
        self.generator = generator
        self.time = time
        self.completion = completion
        super.init()
    }
    
    override func start() {
        if self.isCancelled {
            self.fetchFinish()
            return
        }
        self.pri_isExecuting = true
        self.generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: self.time)]) { (_, cgImage, _, result, error) in
            if result == .succeeded, let cg = cgImage {
                let image = UIImage(cgImage: cg)
                ZLMainAsync {
                    self.completion(image, self.time)
                }
                self.fetchFinish()
            } else {
                self.fetchFinish()
            }
        }
    }
    
    func fetchFinish() {
        self.pri_isExecuting = false
        self.pri_isFinished = true
    }
    
    override func cancel() {
        super.cancel()
        self.pri_isCancelled = true
    }
    
}
