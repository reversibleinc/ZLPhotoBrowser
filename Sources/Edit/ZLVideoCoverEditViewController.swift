//
//  ZLVideoCoverEditViewController.swift
//  ZLPhotoBrowser
//
//  Created by leven on 2023/3/7.
//

import Foundation
import UIKit
import Photos

public class ZLVideoCoverEditViewController: UIViewController {

    static let frameImageSize = CGSize(width: CGFloat(round(50.0 * 2.0 / 3.0)), height: 50.0)
    
    let avAsset: AVAsset
    
    public var initCoverImage: UIImage?
    
    var coverTime: CMTime?
    
    let animateDismiss: Bool
    
    var cancelBtn: UIButton!
    
    var doneBtn: UIButton!
    
    var timer: Timer?
        
    lazy var coverPreviewImageView = UIImageView()
    
    var collectionView: UICollectionView!
    
    var frameImageBorderView: ZLEditVideoFrameImageBorderView!
    
   
    var coverSidePan: UIPanGestureRecognizer!
    
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
    
    lazy var coverSliderV = ZLVideoCoverSliderView(frame: CGRect.zero)
    
    lazy var coverImageView = UIImageView()
    lazy var closeIcon = UIImageView()
    
    lazy var generator: AVAssetImageGenerator = {
        let g = AVAssetImageGenerator(asset: self.avAsset)
        g.maximumSize = CGSize(width: ZLEditVideoViewController.frameImageSize.width * 3, height: ZLEditVideoViewController.frameImageSize.height * 3)
        g.appliesPreferredTrackTransform = true
        g.requestedTimeToleranceBefore = .zero
        g.requestedTimeToleranceAfter = .zero
        g.apertureMode = .encodedPixels
        return g
    }()
    public var didGenerateThumbnails: (([Int: UIImage]) -> Void)?

    public var editFinishBlock: ( (CMTime?, UIImage?) -> Void )?
    
    var albumCoverImage: UIImage? {
        didSet {
            if let albumCoverImage = albumCoverImage {
                self.closeIcon.isHidden = false
                self.collectionView.isHidden = true
                self.coverSliderV.isHidden = true
                self.frameImageBorderView.isHidden = true
                self.coverImageView.image = albumCoverImage
                self.coverPreviewImageView.image = albumCoverImage
                self.coverTime = .zero
            } else {
                self.collectionView.isHidden = false
                self.coverSliderV.isHidden = false
                self.frameImageBorderView.isHidden = false
                self.closeIcon.isHidden = true
                self.coverImageView.image = getImage("cover_upload")
                self.refreshCover()
                
            }
        }
    }
    
    public override var prefersStatusBarHidden: Bool {
        return true
    }
    
    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
    
    deinit {
        zl_debugPrint("ZLEditVideoViewController deinit")
        self.requestFrameImageQueue.cancelAllOperations()
        if self.avAssetRequestID > PHInvalidImageRequestID {
            PHImageManager.default().cancelImageRequest(self.avAssetRequestID)
        }
        if self.videoRequestID > PHInvalidImageRequestID {
            PHImageManager.default().cancelImageRequest(self.videoRequestID)
        }

    }
    
    
    /// initialize
    /// - Parameters:
    ///   - avAsset: AVAsset对象，需要传入本地视频，网络视频不支持
    ///   - animateDismiss: 退出界面时是否显示dismiss动画
    public init(avAsset: AVAsset, animateDismiss: Bool = false, coverTime: CMTime? = nil) {
        self.avAsset = avAsset
        self.animateDismiss = animateDismiss
        self.coverTime = coverTime
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
        
        self.analysisAssetImages()
        self.closeIcon.isUserInteractionEnabled = true
        self.coverImageView.isUserInteractionEnabled = true
        
        self.closeIcon.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(deleteAlbumCover(_:))))
        self.coverImageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(clickAlbumCover(_:))))

    }
    
    @objc func deleteAlbumCover(_ gesture: UITapGestureRecognizer) {
        if gesture.state == .ended {
            self.albumCoverImage = nil
        }
    }
    
    @objc func clickAlbumCover(_ gesture: UITapGestureRecognizer) {
        if gesture.state == .ended {
            self.pickCoverFromAlbum()
        }
    }
    
    func pickCoverFromAlbum() {
        ZLPhotoConfiguration.default().maxSelectCount = 1
        ZLPhotoConfiguration.default().editAfterSelectThumbnailImage = false
        ZLPhotoConfiguration.default().allowPreviewPhotos = false
        ZLPhotoConfiguration.default().allowEditImage = false
        ZLPhotoConfiguration.default().allowSelectGif = false
        ZLPhotoConfiguration.default().allowSelectVideo = false
        ZLPhotoConfiguration.default().allowSelectOriginal = false
        ZLPhotoConfiguration.default().showBottomToolBar = false
        ZLPhotoConfiguration.default().allowTakePhotoInLibrary = false
        ZLPhotoConfiguration.default().showAddPhotoButton = false
        ZLPhotoConfiguration.default().defaultAlbumTab = true
        
        let ps = ZLPhotoPreviewSheet()
        var coverImg: UIImage?
        ps.doneRedirectBlock = { [weak self]vc in
            guard let self = self else { return }
            if let coverImg = coverImg {
                self.albumCoverImage = coverImg
                vc?.dismiss(animated: true)
            } else {
                vc?.dismiss(animated: true)

            }
        }
        ps.selectImageBlock = { (images, _, _) in
            coverImg = images.first
        }
        ps.showPhotoLibrary(sender: self)
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
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
        let diffBottom = btnH + ZLEditVideoViewController.frameImageSize.height + bottomBtnAndColSpacing + insets.bottom + 30

        self.coverPreviewImageView.frame = CGRect(x: 15, y: insets.top + 20, width: self.view.bounds.width - 30, height: self.view.bounds.height - playerLayerY - diffBottom)
        let cancelBtnW = localLanguageTextValue(.cancel).boundingRect(font: ZLLayout.bottomToolTitleFont, limitSize: CGSize(width: CGFloat.greatestFiniteMagnitude, height: btnH)).width
        self.cancelBtn.frame = CGRect(x: 15, y: self.view.bounds.height - insets.bottom - btnH, width: cancelBtnW, height: btnH)
        let doneBtnW = localLanguageTextValue(.done).boundingRect(font: ZLLayout.bottomToolTitleFont, limitSize: CGSize(width: CGFloat.greatestFiniteMagnitude, height: btnH)).width + 20
        self.doneBtn.frame = CGRect(x: self.view.bounds.width-doneBtnW-15, y: self.view.bounds.height - insets.bottom - btnH, width: doneBtnW, height: btnH)
        
        self.coverImageView.frame = CGRect(x: self.cancelBtn.frame.minX, y: self.doneBtn.frame.minY - bottomBtnAndColSpacing - ZLEditVideoViewController.frameImageSize.height, width: ZLEditVideoViewController.frameImageSize.height, height: ZLEditVideoViewController.frameImageSize.height)
        self.closeIcon.frame = CGRect(x: self.coverImageView.frame.maxX - 7, y: self.coverImageView.frame.minY - 7, width: 14, height: 14)
        self.collectionView.frame = CGRect(x: self.coverImageView.frame.maxX + 10, y: self.doneBtn.frame.minY - bottomBtnAndColSpacing - ZLEditVideoViewController.frameImageSize.height, width: self.view.bounds.width - self.coverImageView.frame.maxX - 10 - 20, height: ZLEditVideoViewController.frameImageSize.height)
        
        
        let frameViewW = ZLEditVideoViewController.frameImageSize.width * 10
        
        self.frameImageBorderView.frame = self.collectionView.frame
        
        if let coverTime = coverTime {
            let startX = Double(coverTime.value) /  Double(coverTime.timescale) / Double(self.interval) * ZLEditVideoViewController.frameImageSize.width + self.frameImageBorderView.frame.minX
            self.coverSliderV.frame = CGRect(x: startX, y: self.collectionView.frame.minY, width: 6, height: ZLEditVideoViewController.frameImageSize.height)
        } else {
            self.coverSliderV.frame = CGRect(x: self.frameImageBorderView.frame.minX, y: self.collectionView.frame.minY, width: 6, height: ZLEditVideoViewController.frameImageSize.height)
        }
    }
    
    func setupUI() {
        self.view.backgroundColor = .black
        coverPreviewImageView.contentMode = .scaleAspectFit
        self.view.addSubview(self.coverPreviewImageView)
        
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
        
        ZLEditVideoFrameImageCell.zl_register(self.collectionView)
        
        self.view.addSubview(self.coverSliderV)
        self.coverImageView.contentMode = .scaleAspectFit
        self.coverImageView.image = getImage("cover_upload")
        self.view.addSubview(self.coverImageView)
        self.closeIcon.contentMode = .scaleAspectFit
        self.closeIcon.image = getImage("edit_cover")
        self.closeIcon.isHidden = true
        self.view.addSubview(self.closeIcon)

        self.coverSidePan = UIPanGestureRecognizer(target: self, action: #selector(coverSidePanAction(_:)))
        self.coverSidePan.delegate = self
        self.view.addGestureRecognizer(self.coverSidePan)
        
        self.frameImageBorderView = ZLEditVideoFrameImageBorderView()
        self.frameImageBorderView.isUserInteractionEnabled = false
        self.frameImageBorderView.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        self.view.addSubview(self.frameImageBorderView)
        

        self.collectionView.panGestureRecognizer.require(toFail: self.coverSidePan)
        
        self.cancelBtn = UIButton(type: .custom)
        self.cancelBtn.setImage(getImage("video_edit_close"), for: .normal)
        self.cancelBtn.setTitleColor(.bottomToolViewBtnNormalTitleColor, for: .normal)
        self.cancelBtn.titleLabel?.font = ZLLayout.bottomToolTitleFont
        self.cancelBtn.addTarget(self, action: #selector(cancelBtnClick), for: .touchUpInside)
        self.view.addSubview(self.cancelBtn)
        
        self.doneBtn = UIButton(type: .custom)
        self.doneBtn.setImage(getImage("video_edit_done"), for: .normal)
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
        if let albumCoverImage = albumCoverImage {
            self.editFinishBlock?(nil, albumCoverImage)
        } else {
            self.editFinishBlock?(self.coverTime, self.coverPreviewImageView.image)
        }
        self.dismiss(animated: true)
    }
    
    @objc func coverSidePanAction(_ pan: UIPanGestureRecognizer) {
        let point = pan.location(in: self.view)
        
        if pan.state == .began {
            self.frameImageBorderView.layer.borderColor = UIColor(white: 1, alpha: 0.6).cgColor
        } else if pan.state == .changed {
            let minX = self.frameImageBorderView.frame.minX
            let maxX = self.frameImageBorderView.frame.maxX
            
            var frame = self.coverSliderV.frame
            frame.origin.x = min(maxX, max(minX, point.x))
            self.coverSliderV.frame = frame
            self.refreshCoverTime()
            self.refreshCover()
        } else if pan.state == .ended || pan.state == .cancelled {
            self.frameImageBorderView.layer.borderColor = UIColor.clear.cgColor
            self.refreshCover()
        }
    }
    
    
    var timeObserver: Any?
    func analysisAssetImages() {
        let duration = round(self.avAsset.duration.seconds)
        guard duration > 0 else {
            self.showFetchFailedAlert()
            return
        }
        
        self.measureCount = Int(duration / self.interval)
        self.collectionView.reloadData()
        self.requestVideoMeasureFrameImage()
        self.refreshCoverTime()
        if let initCoverImage = initCoverImage {
            self.albumCoverImage = initCoverImage
        } else {
            self.refreshCover()
        }
    }
    
    func refreshCover() {
        let coverWidth = view.frame.width * 3
        generator.maximumSize = CGSize(width: coverWidth, height: coverWidth / ZLEditVideoViewController.frameImageSize.width * ZLEditVideoViewController.frameImageSize.height)
        generator.cancelAllCGImageGeneration()
        generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: self.coverTime!)]) {[weak self] _, cgImage, _, _, _ in
            guard let self = self else { return }
            if let cgImage = cgImage {
                DispatchQueue.main.async {
                    self.coverPreviewImageView.image = UIImage(cgImage: cgImage)
                }
            }
        }
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
    
    
    func refreshCoverTime() {
       let time = (self.coverSliderV.frame.centerX - self.frameImageBorderView.frame.minX) /  self.frameImageBorderView.frame.width *  round(self.avAsset.duration.seconds)
        if time.isNormal {
            self.coverTime = CMTime(value: CMTimeValue(time), timescale: 1)
        } else {
            self.coverTime = .zero
        }
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
        return self.frameImageBorderView.frame
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


extension ZLVideoCoverEditViewController: UIGestureRecognizerDelegate {
    
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if albumCoverImage != nil {
            return false
        }
         if gestureRecognizer == self.coverSliderV {
            let point = gestureRecognizer.location(in: self.view)
            let frame = self.coverSliderV.frame
            let outerFrame = frame.inset(by: UIEdgeInsets(top: -20, left: -20, bottom: -20, right: -40))
            return outerFrame.contains(point)
        }
        return true
    }
    
}
import SnapKit
extension ZLVideoCoverEditViewController {
    class ZLVideoCoverSliderView: UIView {
        override init(frame: CGRect) {
            super.init(frame: frame)
            let topV = UIView()
            topV.backgroundColor = UIColor.white
            let centerV = UIView()
            centerV.backgroundColor = UIColor.white
            let bottomV = UIView()
            bottomV.backgroundColor = UIColor.white
            self.addSubview(topV)
            self.addSubview(centerV)
            self.addSubview(bottomV)
            topV.snp.makeConstraints { make in
                make.left.top.right.equalToSuperview()
                make.height.equalTo(3)
            }
            bottomV.snp.makeConstraints { make in
                make.left.right.bottom.equalToSuperview()
                make.height.equalTo(4)
            }
            centerV.snp.makeConstraints { make in
                make.centerX.top.bottom.equalToSuperview()
                make.width.equalTo(3)
            }
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}


extension ZLVideoCoverEditViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        return UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
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

extension CGRect {
    var centerX: CGFloat {
        return maxX - width / 2
    }
    var centerY: CGFloat {
        return maxY - height / 2
    }
}
