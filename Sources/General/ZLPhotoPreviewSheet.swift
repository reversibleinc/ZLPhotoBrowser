//
//  ZLPhotoPreviewSheet.swift
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
import Photos

public class ZLPhotoPreviewSheet: UIView {

    struct Layout {
        
        static let colH: CGFloat = 155
        
        static let btnH: CGFloat = 45
        
        static let spacing: CGFloat = 1 / UIScreen.main.scale
        
    }
    
    private lazy var baseView = UIView()
    
    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumInteritemSpacing = 3
        layout.minimumLineSpacing = 3
        layout.sectionInset = UIEdgeInsets(top: 0, left: 5, bottom: 0, right: 5)
        
        return UICollectionView(frame: .zero, collectionViewLayout: layout)
    }()
    
    private var cameraBtn: UIButton!
    
    private var photoLibraryBtn: UIButton!
    
    private var cancelBtn: UIButton!
    
    private lazy var flexibleView = UIView()
    
    private lazy var placeholderLabel = UILabel()
    
    private var arrDataSources: [ZLPhotoModel] = []
    
    private var arrSelectedModels: [ZLPhotoModel] = []
    
    private var preview = false
    
    private var animate = true
    
    private var senderTabBarIsHidden: Bool?
    
    private var baseViewHeight: CGFloat = 0
    
    private var isSelectOriginal = true
    
    private var panBeginPoint: CGPoint = .zero
    
    private var panImageView: UIImageView?
    
    private var panModel: ZLPhotoModel?
    
    private var panCell: ZLThumbnailPhotoCell?
    
    private weak var sender: UIViewController?
    
    private lazy var fetchImageQueue: OperationQueue = OperationQueue()
    
    /// Success callback
    /// block params
    ///  - params1: images for asset.
    ///  - params2: selected assets
    ///  - params3: is full image
    @objc public var selectImageBlock: ( ([UIImage], [PHAsset], Bool) -> Void )?
    
    
    
    @objc public var doneRedirectBlock: ((UIViewController?) -> Void)?
    /// Callback for photos that failed to parse
    /// block params
    ///  - params1: failed assets.
    ///  - params2: index for asset
    @objc public var selectImageRequestErrorBlock: ( ([PHAsset], [Int]) -> Void )?
    
    @objc public var cancelBlock: ( () -> Void )?
    
    deinit {
        zl_debugPrint("ZLPhotoPreviewSheet deinit")
    }
    
    convenience public override init(frame: CGRect) {
        self.init(selectedAssets: nil)
    }
    
    /// - Parameter selectedAssets: preselected assets
    @objc public init(selectedAssets: [PHAsset]? = nil) {
        super.init(frame: .zero)
        let config = ZLPhotoConfiguration.default()
        if !config.allowSelectImage &&
            !config.allowSelectVideo {
            assert(false, "ZLPhotoBrowser: error configuration. The values of allowSelectImage and allowSelectVideo are both false")
            config.allowSelectImage = true
        }
        
        fetchImageQueue.maxConcurrentOperationCount = 3
        setupUI()
        
        arrSelectedModels.removeAll()
        selectedAssets?.removeDuplicate().forEach { (asset) in
            if !config.allowMixSelect, asset.mediaType == .video {
                return
            }
            
            let m = ZLPhotoModel(asset: asset)
            m.isSelected = true
            self.arrSelectedModels.append(m)
        }
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        baseView.frame = CGRect(x: 0, y: bounds.height - baseViewHeight, width: bounds.width, height: baseViewHeight)
        
        var btnY: CGFloat = 0
        if ZLPhotoConfiguration.default().maxPreviewCount > 0 {
            collectionView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: ZLPhotoPreviewSheet.Layout.colH)
            btnY += (collectionView.frame.maxY + ZLPhotoPreviewSheet.Layout.spacing)
        }
        if canShowCameraBtn() {
            cameraBtn.frame = CGRect(x: 0, y: btnY, width: bounds.width, height: ZLPhotoPreviewSheet.Layout.btnH)
            btnY += (ZLPhotoPreviewSheet.Layout.btnH + ZLPhotoPreviewSheet.Layout.spacing)
        }
        photoLibraryBtn.frame = CGRect(x: 0, y: btnY, width: bounds.width, height: ZLPhotoPreviewSheet.Layout.btnH)
        btnY += (ZLPhotoPreviewSheet.Layout.btnH + ZLPhotoPreviewSheet.Layout.spacing)
        cancelBtn.frame = CGRect(x: 0, y: btnY, width: bounds.width, height: ZLPhotoPreviewSheet.Layout.btnH)
        btnY += ZLPhotoPreviewSheet.Layout.btnH
        flexibleView.frame = CGRect(x: 0, y: btnY, width: bounds.width, height: baseViewHeight - btnY)
    }
    
    func setupUI() {
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        backgroundColor = .previewBgColor
        
        let showCameraBtn = canShowCameraBtn()
        var bh: CGFloat = 0
        if ZLPhotoConfiguration.default().maxPreviewCount > 0 {
            bh += ZLPhotoPreviewSheet.Layout.colH
        }
        bh += (ZLPhotoPreviewSheet.Layout.spacing + ZLPhotoPreviewSheet.Layout.btnH) * (showCameraBtn ? 3 : 2)
        bh += deviceSafeAreaInsets().bottom
        baseViewHeight = bh
        
        baseView.backgroundColor = zlRGB(230, 230, 230)
        addSubview(baseView)
        
        collectionView.backgroundColor = .previewBtnBgColor
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.isHidden = ZLPhotoConfiguration.default().maxPreviewCount == 0
        ZLThumbnailPhotoCell.zl_register(collectionView)
        baseView.addSubview(collectionView)
        
        placeholderLabel.font = getFont(15)
        placeholderLabel.text = localLanguageTextValue(.noPhotoTips)
        placeholderLabel.textAlignment = .center
        placeholderLabel.textColor = .previewBtnTitleColor
        collectionView.backgroundView = placeholderLabel
        
        func createBtn(_ title: String) -> UIButton {
            let btn = UIButton(type: .custom)
            btn.backgroundColor = .previewBtnBgColor
            btn.setTitleColor(.previewBtnTitleColor, for: .normal)
            btn.setTitle(title, for: .normal)
            btn.titleLabel?.font = getFont(17)
            return btn
        }
        
        let cameraTitle: String
        if !ZLPhotoConfiguration.default().allowTakePhoto, ZLPhotoConfiguration.default().allowRecordVideo {
            cameraTitle = localLanguageTextValue(.previewCameraRecord)
        } else {
            cameraTitle = localLanguageTextValue(.previewCamera)
        }
        cameraBtn = createBtn(cameraTitle)
        cameraBtn.isHidden = !showCameraBtn
        cameraBtn.addTarget(self, action: #selector(cameraBtnClick), for: .touchUpInside)
        baseView.addSubview(cameraBtn)
        
        photoLibraryBtn = createBtn(localLanguageTextValue(.previewAlbum))
        photoLibraryBtn.addTarget(self, action: #selector(photoLibraryBtnClick), for: .touchUpInside)
        baseView.addSubview(photoLibraryBtn)
        
        cancelBtn = createBtn(localLanguageTextValue(.cancel))
        cancelBtn.addTarget(self, action: #selector(cancelBtnClick), for: .touchUpInside)
        baseView.addSubview(cancelBtn)
        
        flexibleView.backgroundColor = .previewBtnBgColor
        baseView.addSubview(flexibleView)
        
        if ZLPhotoConfiguration.default().allowDragSelect {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(panSelectAction(_:)))
            baseView.addGestureRecognizer(pan)
        }
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapAction(_:)))
        tap.delegate = self
        addGestureRecognizer(tap)
    }
    
    func canShowCameraBtn() -> Bool {
        if !ZLPhotoConfiguration.default().allowTakePhoto, !ZLPhotoConfiguration.default().allowRecordVideo {
            return false
        }
        return true
    }
    
    @objc public func showPreview(animate: Bool = true, sender: UIViewController) {
        self.show(preview: true, animate: animate, sender: sender)
    }
    
    @objc public func showPhotoLibrary(sender: UIViewController) {
        self.show(preview: false, animate: false, sender: sender)
    }
    
    /// 传入已选择的assets，并预览
    @objc public func previewAssets(sender: UIViewController, assets: [PHAsset], index: Int, isOriginal: Bool, showBottomViewAndSelectBtn: Bool = true) {
        let models = assets.removeDuplicate().map { (asset) -> ZLPhotoModel in
            let m = ZLPhotoModel(asset: asset)
            m.isSelected = true
            return m
        }
        arrSelectedModels.removeAll()
        arrSelectedModels.append(contentsOf: models)
        self.sender = sender
        isSelectOriginal = isOriginal
        isHidden = true
        sender.view.addSubview(self)
        
        let vc = ZLPhotoPreviewController(photos: models, index: index, showBottomViewAndSelectBtn: showBottomViewAndSelectBtn)
        vc.autoSelectCurrentIfNotSelectAnyone = false
        let nav = getImageNav(rootViewController: vc)
        vc.backBlock = { [weak self] in
            self?.hide()
        }
        sender.showDetailViewController(nav, sender: nil)
    }
    
    func show(preview: Bool, animate: Bool, sender: UIViewController) {
        self.preview = preview
        self.animate = animate
        self.sender = sender
        
        let status = PHPhotoLibrary.authorizationStatus()
        if status == .restricted || status == .denied {
            showNoAuthorityAlert()
        } else if status == .notDetermined {
            PHPhotoLibrary.requestAuthorization { (status) in
                ZLMainAsync {
                    if status == .denied {
                        self.showNoAuthorityAlert()
                    } else if status == .authorized {
                        if self.preview {
                            self.loadPhotos()
                            self.show()
                        } else {
                            self.photoLibraryBtnClick()
                        }
                    }
                }
            }
            
            sender.view.addSubview(self)
        } else {
            if preview {
                loadPhotos()
                show()
            } else {
                sender.view.addSubview(self)
                photoLibraryBtnClick()
            }
        }
        
        // Register for the album change notification when the status is limited, because the photoLibraryDidChange method will be repeated multiple times each time the album changes, causing the interface to refresh multiple times. So the album changes are not monitored in other authority.
        if #available(iOS 14.0, *), preview, PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited {
            PHPhotoLibrary.shared().register(self)
        }
    }
    
    func loadPhotos() {
        arrDataSources.removeAll()
        
        let config = ZLPhotoConfiguration.default()
        ZLPhotoManager.getCameraRollAlbum(allowSelectImage: config.allowSelectImage, allowSelectVideo: config.allowSelectVideo) { [weak self] (cameraRoll) in
            guard let `self` = self else { return }
            var totalPhotos = ZLPhotoManager.fetchPhoto(in: cameraRoll.result, ascending: false, allowSelectImage: config.allowSelectImage, allowSelectVideo: config.allowSelectVideo, limitCount: config.maxPreviewCount)
            markSelected(source: &totalPhotos, selected: &self.arrSelectedModels)
            self.arrDataSources.append(contentsOf: totalPhotos)
            self.collectionView.reloadData()
        }
    }
    
    func show() {
        frame = sender?.view.bounds ?? .zero
        
        collectionView.contentOffset = .zero
        
        if superview == nil {
            sender?.view.addSubview(self)
        }
        
        if let tabBar = sender?.tabBarController?.tabBar, !tabBar.isHidden {
            senderTabBarIsHidden = tabBar.isHidden
            tabBar.isHidden =  true
        }
        
        if animate {
            backgroundColor = UIColor.previewBgColor.withAlphaComponent(0)
            var frame = baseView.frame
            frame.origin.y = bounds.height
            baseView.frame = frame
            frame.origin.y -= baseViewHeight
            UIView.animate(withDuration: 0.2) {
                self.backgroundColor = UIColor.previewBgColor
                self.baseView.frame = frame
            }
        }
    }
    
    func hide(completion: ( () -> Void )? = nil) {
        if animate {
            var frame = baseView.frame
            frame.origin.y += baseViewHeight
            UIView.animate(withDuration: 0.2, animations: {
                self.backgroundColor = UIColor.previewBgColor.withAlphaComponent(0)
                self.baseView.frame = frame
            }) { (_) in
                self.isHidden = true
                completion?()
                self.removeFromSuperview()
            }
        } else {
            isHidden = true
            completion?()
            removeFromSuperview()
        }
        
        if let temp = senderTabBarIsHidden {
            sender?.tabBarController?.tabBar.isHidden = temp
        }
    }
    
    func showNoAuthorityAlert() {
        let alert = UIAlertController(title: nil, message: String(format: localLanguageTextValue(.noPhotoLibratyAuthority), getAppName()), preferredStyle: .alert)
        let action = UIAlertAction(title: localLanguageTextValue(.ok), style: .default) { (_) in
            ZLPhotoConfiguration.default().noAuthorityCallback?(.library)
        }
        alert.addAction(action)
        sender?.showAlertController(alert)
    }
    
    @objc func tapAction(_ tap: UITapGestureRecognizer) {
        hide {
            self.cancelBlock?()
        }
    }
    
    @objc func cameraBtnClick() {
        let config = ZLPhotoConfiguration.default()
        if config.useCustomCamera {
            let camera = ZLCustomCamera()
            camera.takeDoneBlock = { [weak self] (image, videoUrl) in
                self?.save(image: image, videoUrl: videoUrl)
            }
            sender?.showDetailViewController(camera, sender: nil)
        } else {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                let picker = UIImagePickerController()
                picker.delegate = self
                picker.allowsEditing = false
                picker.videoQuality = .typeHigh
                picker.sourceType = .camera
                picker.cameraFlashMode = config.cameraConfiguration.flashMode.imagePickerFlashMode
                var mediaTypes = [String]()
                if config.allowTakePhoto {
                    mediaTypes.append("public.image")
                }
                if config.allowRecordVideo {
                    mediaTypes.append("public.movie")
                }
                picker.mediaTypes = mediaTypes
                picker.videoMaximumDuration = TimeInterval(config.maxRecordDuration)
                sender?.showDetailViewController(picker, sender: nil)
            } else {
                showAlertView(localLanguageTextValue(.cameraUnavailable), self.sender)
            }
        }
    }
    
    @objc func photoLibraryBtnClick() {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
        animate = false
        showThumbnailViewController()
    }
    
    @objc func cancelBtnClick() {
        guard !self.arrSelectedModels.isEmpty else {
            hide { [weak self] in
                self?.cancelBlock?()
            }
            return
        }
        requestSelectPhoto()
    }
    
    @objc func panSelectAction(_ pan: UIPanGestureRecognizer) {
        let point = pan.location(in: collectionView)
        if pan.state == .began {
            let cp = baseView.convert(point, from: collectionView)
            guard collectionView.frame.contains(cp) else {
                panBeginPoint = .zero
                return
            }
            panBeginPoint = point
        } else if pan.state == .changed {
            guard panBeginPoint != .zero else {
                return
            }
            
            guard let indexPath = collectionView.indexPathForItem(at: panBeginPoint) else {
                return
            }
            
            if panImageView == nil {
                guard point.y < panBeginPoint.y else {
                    return
                }
                guard let cell = collectionView.cellForItem(at: indexPath) as? ZLThumbnailPhotoCell else {
                    return
                }
                panModel = arrDataSources[indexPath.row]
                panCell = cell
                panImageView = UIImageView(frame: cell.bounds)
                panImageView?.contentMode = .scaleAspectFill
                panImageView?.clipsToBounds = true
                panImageView?.image = cell.imageView.image
                cell.imageView.image = nil
                addSubview(panImageView!)
            }
            panImageView?.center = convert(point, from: collectionView)
        } else if pan.state == .cancelled || pan.state == .ended {
            guard let pv = panImageView else {
                return
            }
            let pvRect = baseView.convert(pv.frame, from: self)
            var callBack = false
            if pvRect.midY < -10 {
                arrSelectedModels.removeAll()
                arrSelectedModels.append(panModel!)
                requestSelectPhoto()
                callBack = true
            }
            
            panModel = nil
            if !callBack {
                let toRect = convert(panCell?.frame ?? .zero, from: collectionView)
                UIView.animate(withDuration: 0.25, animations: {
                    self.panImageView?.frame = toRect
                }) { (_) in
                    self.panCell?.imageView.image = self.panImageView?.image
                    self.panCell = nil
                    self.panImageView?.removeFromSuperview()
                    self.panImageView = nil
                }
            } else {
                panCell?.imageView.image = panImageView?.image
                panImageView?.removeFromSuperview()
                panImageView = nil
                panCell = nil
            }
        }
    }
    
    func requestSelectPhoto(viewController: UIViewController? = nil) {
        guard !arrSelectedModels.isEmpty else {
            selectImageBlock?([], [], isSelectOriginal)
            hide()
            viewController?.dismiss(animated: true, completion: nil)
            return
        }
        
        let config = ZLPhotoConfiguration.default()
        
        if config.allowMixSelect {
            let videoCount = arrSelectedModels.filter { $0.type == .video }.count
            
            if videoCount > config.maxVideoSelectCount {
                showAlertView(String(format: localLanguageTextValue(.exceededMaxVideoSelectCount), ZLPhotoConfiguration.default().maxVideoSelectCount), viewController)
                return
            } else if videoCount < config.minVideoSelectCount {
                showAlertView(String(format: localLanguageTextValue(.lessThanMinVideoSelectCount), ZLPhotoConfiguration.default().minVideoSelectCount), viewController)
                return
            }
        }
        
        let hud = ZLProgressHUD(style: ZLPhotoConfiguration.default().hudStyle)
        
        var timeout = false
        hud.timeoutBlock = { [weak self] in
            timeout = true
            showAlertView(localLanguageTextValue(.timeout), viewController ?? self?.sender)
            self?.fetchImageQueue.cancelAllOperations()
        }
        
        hud.show(timeout: ZLPhotoConfiguration.default().timeout)
        
        let callback = { [weak self] (sucImages: [UIImage], sucAssets: [PHAsset], errorAssets: [PHAsset], errorIndexs: [Int]) in
            hud.hide()
            
            func call() {
                self?.selectImageBlock?(sucImages, sucAssets, self?.isSelectOriginal ?? false)
                if !errorAssets.isEmpty {
                    self?.selectImageRequestErrorBlock?(errorAssets, errorIndexs)
                }
            }
            if let doneRedirectBlock = self?.doneRedirectBlock {
                call()
                doneRedirectBlock(viewController)
            } else {
                if let vc = viewController {
                    self?.isHidden = true
                    self?.animate = false
                    vc.dismiss(animated: true) {
                        call()
                        self?.hide()
                    }
                } else {
                    self?.hide(completion: {
                        call()
                    })
                }
                self?.arrSelectedModels.removeAll()
                self?.arrDataSources.removeAll()
            }
        }
        
        guard ZLPhotoConfiguration.default().shouldAnialysisAsset else {
            callback([], arrSelectedModels.map { $0.asset }, [], [])
            return
        }
        
        var images: [UIImage?] = Array(repeating: nil, count: arrSelectedModels.count)
        var assets: [PHAsset?] = Array(repeating: nil, count: arrSelectedModels.count)
        var errorAssets: [PHAsset] = []
        var errorIndexs: [Int] = []
        
        var sucCount = 0
        let totalCount = arrSelectedModels.count
        for (i, m) in arrSelectedModels.enumerated() {
            let operation = ZLFetchImageOperation(model: m, isOriginal: isSelectOriginal) { (image, asset) in
                guard !timeout else { return }
                
                sucCount += 1
                
                if let image = image {
                    images[i] = image
                    assets[i] = asset ?? m.asset
                    zl_debugPrint("ZLPhotoBrowser: suc request \(i)")
                } else {
                    errorAssets.append(m.asset)
                    errorIndexs.append(i)
                    zl_debugPrint("ZLPhotoBrowser: failed request \(i)")
                }
                
                guard sucCount >= totalCount else { return }
                
                callback(
                    images.compactMap { $0 },
                    assets.compactMap { $0 },
                    errorAssets,
                    errorIndexs
                )
            }
            fetchImageQueue.addOperation(operation)
        }
    }
    
    func showThumbnailViewController() {
        ZLPhotoManager.getCameraRollAlbum(allowSelectImage: ZLPhotoConfiguration.default().allowSelectImage, allowSelectVideo: ZLPhotoConfiguration.default().allowSelectVideo) { [weak self] (cameraRoll) in
            guard let `self` = self else { return }
            let nav: ZLImageNavController
            if ZLPhotoConfiguration.default().style == .embedAlbumList {
                let tvc = ZLThumbnailViewController(albumList: cameraRoll)
                let camera = ZLCustomCamera()
                camera.thumbnailsVC = tvc
                let mainVC = ZLPhotoMainViewController(childVCs: [("album".localized("Album").uppercasedPrefix(1), tvc), ("camera".localized("Camera").uppercasedPrefix(1), camera)])
                mainVC.curChildTitle = ZLPhotoConfiguration.default().defaultAlbumTab ? "album".localized("Album").uppercasedPrefix(1) : "camera".localized("Camera").uppercasedPrefix(1)
                nav = self.getImageNav(rootViewController: mainVC)
            } else {
                nav = self.getImageNav(rootViewController: ZLAlbumListController())
                let tvc = ZLThumbnailViewController(albumList: cameraRoll)
                nav.pushViewController(tvc, animated: true)
            }
            if deviceIsiPad() {
                self.sender?.present(nav, animated: true, completion: nil)
            } else {
                self.sender?.showDetailViewController(nav, sender: nil)
            }
        }
    }
    
    func showPreviewController(_ models: [ZLPhotoModel], index: Int) {
        let vc = ZLPhotoPreviewController(photos: models, index: index)
        let nav = getImageNav(rootViewController: vc)
        vc.backBlock = { [weak self, weak nav] in
            guard let `self` = self else { return }
            self.isSelectOriginal = nav?.isSelectedOriginal ?? false
            self.arrSelectedModels.removeAll()
            self.arrSelectedModels.append(contentsOf: nav?.arrSelectedModels ?? [])
            markSelected(source: &self.arrDataSources, selected: &self.arrSelectedModels)
            self.collectionView.reloadItems(at: self.collectionView.indexPathsForVisibleItems)
            self.changeCancelBtnTitle()
        }
        sender?.showDetailViewController(nav, sender: nil)
    }
    
    func showEditImageVC(model: ZLPhotoModel) {
        let hud = ZLProgressHUD(style: ZLPhotoConfiguration.default().hudStyle)
        hud.show()
        
        ZLPhotoManager.fetchImage(for: model.asset, size: model.previewSize) { [weak self] (image, isDegraded) in
            if !isDegraded {
                if let image = image {
                    ZLEditImageViewController.showEditImageVC(parentVC: self?.sender, image: image, editModel: model.editImageModel) { [weak self] (ei, editImageModel) in
                        model.isSelected = true
                        model.editImage = ei
                        model.editImageModel = editImageModel
                        self?.arrSelectedModels.append(model)
                        self?.requestSelectPhoto()
                    }
                } else {
                    showAlertView(localLanguageTextValue(.imageLoadFailed), self?.sender)
                }
                hud.hide()
            }
        }
    }
    
    func showEditVideoVC(model: ZLPhotoModel) {
        let hud = ZLProgressHUD(style: ZLPhotoConfiguration.default().hudStyle)
        
        var requestAvAssetID: PHImageRequestID?
        
        hud.show(timeout: 20)
        hud.timeoutBlock = { [weak self] in
            showAlertView(localLanguageTextValue(.timeout), self?.sender)
            if let _ = requestAvAssetID {
                PHImageManager.default().cancelImageRequest(requestAvAssetID!)
            }
        }
        
        func inner_showEditVideoVC(_ avAsset: AVAsset) {
            let vc = ZLEditVideoViewController(avAsset: avAsset)
            vc.editFinishBlock = { [weak self] (url, _, _) in
                if let u = url {
                    ZLPhotoManager.saveVideoToAlbum(url: u) { [weak self] (suc, asset) in
                        if suc, asset != nil {
                            let m = ZLPhotoModel(asset: asset!)
                            m.isSelected = true
                            self?.arrSelectedModels.removeAll()
                            self?.arrSelectedModels.append(m)
                            self?.requestSelectPhoto()
                        } else {
                            showAlertView(localLanguageTextValue(.saveVideoError), self?.sender)
                        }
                    }
                } else {
                    self?.arrSelectedModels.removeAll()
                    self?.arrSelectedModels.append(model)
                    self?.requestSelectPhoto()
                }
            }
            vc.modalPresentationStyle = .fullScreen
            sender?.showDetailViewController(vc, sender: nil)
        }
        
        // 提前fetch一下 avasset
        requestAvAssetID = ZLPhotoManager.fetchAVAsset(forVideo: model.asset) { [weak self] (avAsset, _) in
            hud.hide()
            if let _ = avAsset {
                inner_showEditVideoVC(avAsset!)
            } else {
                showAlertView(localLanguageTextValue(.timeout), self?.sender)
            }
        }
    }
    
    func getImageNav(rootViewController: UIViewController) -> ZLImageNavController {
        let nav = ZLImageNavController(rootViewController: rootViewController)
        nav.modalPresentationStyle = .fullScreen
        nav.selectImageBlock = { [weak self, weak nav] in
            self?.isSelectOriginal = nav?.isSelectedOriginal ?? false
            self?.arrSelectedModels.removeAll()
            self?.arrSelectedModels.append(contentsOf: nav?.arrSelectedModels ?? [])
            self?.requestSelectPhoto(viewController: nav)
        }
        
        nav.cancelBlock = { [weak self] in
            self?.hide {
                self?.cancelBlock?()
            }
        }
        nav.isSelectedOriginal = isSelectOriginal
        nav.arrSelectedModels.removeAll()
        nav.arrSelectedModels.append(contentsOf: arrSelectedModels)
        
        return nav
    }
    
    func save(image: UIImage?, videoUrl: URL?) {
        let hud = ZLProgressHUD(style: ZLPhotoConfiguration.default().hudStyle)
        if let image = image {
            hud.show()
            ZLPhotoManager.saveImageToAlbum(image: image) { [weak self] (suc, asset) in
                if suc, let at = asset {
                    let model = ZLPhotoModel(asset: at)
                    self?.handleDataArray(newModel: model)
                } else {
                    showAlertView(localLanguageTextValue(.saveImageError), self?.sender)
                }
                hud.hide()
            }
        } else if let videoUrl = videoUrl {
            hud.show()
            ZLPhotoManager.saveVideoToAlbum(url: videoUrl) { [weak self] (suc, asset) in
                if suc, let at = asset {
                    let model = ZLPhotoModel(asset: at)
                    self?.handleDataArray(newModel: model)
                } else {
                    showAlertView(localLanguageTextValue(.saveVideoError), self?.sender)
                }
                hud.hide()
            }
        }
    }
    
    func handleDataArray(newModel: ZLPhotoModel) {
        arrDataSources.insert(newModel, at: 0)
        
        var canSelect = true
        // If mixed selection is not allowed, and the newModel type is video, it will not be selected.
        if !ZLPhotoConfiguration.default().allowMixSelect, newModel.type == .video {
            canSelect = false
        }
        if canSelect, canAddModel(newModel, currentSelectCount: arrSelectedModels.count, sender: sender, showAlert: false) {
            if !shouldDirectEdit(newModel) {
                newModel.isSelected = true
                arrSelectedModels.append(newModel)
            }
        }
        
        let insertIndexPath = IndexPath(row: 0, section: 0)
        collectionView.performBatchUpdates({
            self.collectionView.insertItems(at: [insertIndexPath])
        }) { (_) in
            self.collectionView.scrollToItem(at: insertIndexPath, at: .centeredHorizontally, animated: true)
            self.collectionView.reloadItems(at: self.collectionView.indexPathsForVisibleItems)
        }
        
        changeCancelBtnTitle()
    }
    
}


extension ZLPhotoPreviewSheet: UIGestureRecognizerDelegate {
    
    public override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let location = gestureRecognizer.location(in: self)
        return !baseView.frame.contains(location)
    }
    
}


extension ZLPhotoPreviewSheet: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let m = arrDataSources[indexPath.row]
        let w = CGFloat(m.asset.pixelWidth)
        let h = CGFloat(m.asset.pixelHeight)
        let scale = min(1.7, max(0.5, w / h))
        return CGSize(width: collectionView.frame.height * scale, height: collectionView.frame.height)
    }
    
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        placeholderLabel.isHidden = arrSelectedModels.isEmpty
        return arrDataSources.count
    }
    
    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ZLThumbnailPhotoCell.zl_identifier(), for: indexPath) as! ZLThumbnailPhotoCell
        
        let model = arrDataSources[indexPath.row]
        
        cell.selectedBlock = { [weak self, weak cell] (isSelected) in
            guard let `self` = self else { return }
            if !isSelected {
                guard canAddModel(model, currentSelectCount: self.arrSelectedModels.count, sender: self.sender) else {
                    return
                }
                if !self.shouldDirectEdit(model) {
                    model.isSelected = true
                    self.arrSelectedModels.append(model)
                    cell?.btnSelect.isSelected = true
                    self.refreshCellIndex()
                }
            } else {
                cell?.btnSelect.isSelected = false
                model.isSelected = false
                self.arrSelectedModels.removeAll { $0 == model }
                self.refreshCellIndex()
            }
            
            self.changeCancelBtnTitle()
        }
        
        cell.indexLabel.isHidden = true
        if ZLPhotoConfiguration.default().showSelectedIndex {
            for (index, selM) in arrSelectedModels.enumerated() {
                if model == selM {
                    setCellIndex(cell, showIndexLabel: true, index: index + 1)
                    break
                }
            }
        }
        
        setCellMaskView(cell, isSelected: model.isSelected, model: model)
        
        cell.model = model
        
        return cell
    }
    
    public func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let c = cell as? ZLThumbnailPhotoCell else {
            return
        }
        let model = arrDataSources[indexPath.row]
        setCellMaskView(c, isSelected: model.isSelected, model: model)
    }
    
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let cell = collectionView.cellForItem(at: indexPath) as? ZLThumbnailPhotoCell else {
            return
        }
        
        if !ZLPhotoConfiguration.default().allowPreviewPhotos {
            cell.btnSelectClick()
            return
        }
        
        if !cell.enableSelect, ZLPhotoConfiguration.default().showInvalidMask {
            return
        }
        let model = arrDataSources[indexPath.row]
        
        if shouldDirectEdit(model) {
            return
        }
        let config = ZLPhotoConfiguration.default()
        let hud = ZLProgressHUD(style: config.hudStyle)
        hud.show()
        
        ZLPhotoManager.getCameraRollAlbum(allowSelectImage: config.allowSelectImage, allowSelectVideo: config.allowSelectVideo) { [weak self] (cameraRoll) in
            guard let `self` = self else {
                hud.hide()
                return
            }
            var totalPhotos = ZLPhotoManager.fetchPhoto(in: cameraRoll.result, ascending: config.sortAscending, allowSelectImage: config.allowSelectImage, allowSelectVideo: config.allowSelectVideo)
            markSelected(source: &totalPhotos, selected: &self.arrSelectedModels)
            let defaultIndex = config.sortAscending ? totalPhotos.count - 1 : 0
            var index: Int?
            // last和first效果一样，只是排序方式不同时候分别从前后开始查找可以更快命中
            if config.sortAscending {
                index = totalPhotos.lastIndex { $0 == model }
            } else {
                index = totalPhotos.firstIndex { $0 == model }
            }
            hud.hide()
            
            self.showPreviewController(totalPhotos, index: index ?? defaultIndex)
        }
    }
    
    func shouldDirectEdit(_ model: ZLPhotoModel) -> Bool {
        let config = ZLPhotoConfiguration.default()
        
        let canEditImage = config.editAfterSelectThumbnailImage &&
            config.allowEditImage &&
            config.maxSelectCount == 1 &&
            model.type.rawValue < ZLPhotoModel.MediaType.video.rawValue
        
        let canEditVideo = (config.editAfterSelectThumbnailImage &&
            config.allowEditVideo &&
            model.type == .video &&
            config.maxSelectCount == 1) ||
            (config.allowEditVideo &&
            model.type == .video &&
            !config.allowMixSelect &&
            config.cropVideoAfterSelectThumbnail)
        
        //当前未选择图片 或已经选择了一张并且点击的是已选择的图片
        let flag = arrSelectedModels.isEmpty || (arrSelectedModels.count == 1 && arrSelectedModels.first?.ident == model.ident)
        
        if canEditImage, flag {
            showEditImageVC(model: model)
        } else if canEditVideo, flag {
            showEditVideoVC(model: model)
        }
        
        return flag && (canEditImage || canEditVideo)
    }
    
    func setCellIndex(_ cell: ZLThumbnailPhotoCell?, showIndexLabel: Bool, index: Int) {
        guard ZLPhotoConfiguration.default().showSelectedIndex else {
            return
        }
        cell?.index = index
        cell?.indexLabel.isHidden = !showIndexLabel
    }
    
    func refreshCellIndex() {
        let showIndex = ZLPhotoConfiguration.default().showSelectedIndex
        let showMask = ZLPhotoConfiguration.default().showSelectedMask || ZLPhotoConfiguration.default().showInvalidMask
        
        guard showIndex || showMask else {
            return
        }
        
        let visibleIndexPaths = collectionView.indexPathsForVisibleItems
        
        visibleIndexPaths.forEach { (indexPath) in
            guard let cell = collectionView.cellForItem(at: indexPath) as? ZLThumbnailPhotoCell else {
                return
            }
            let m = arrDataSources[indexPath.row]
            
            var show = false
            var idx = 0
            var isSelected = false
            for (index, selM) in arrSelectedModels.enumerated() {
                if m == selM {
                    show = true
                    idx = index + 1
                    isSelected = true
                    break
                }
            }
            if showIndex {
                setCellIndex(cell, showIndexLabel: show, index: idx)
            }
            if showMask {
                setCellMaskView(cell, isSelected: isSelected, model: m)
            }
        }
    }
    
    func setCellMaskView(_ cell: ZLThumbnailPhotoCell, isSelected: Bool, model: ZLPhotoModel) {
        cell.coverView.isHidden = true
        cell.enableSelect = true
        let config = ZLPhotoConfiguration.default()
        
        if isSelected {
            cell.coverView.backgroundColor = .selectedMaskColor
            cell.coverView.isHidden = !config.showSelectedMask
            if config.showSelectedBorder {
                cell.layer.borderWidth = 4
            }
        } else {
            let selCount = arrSelectedModels.count
            if selCount < config.maxSelectCount {
                if config.allowMixSelect {
                    let videoCount = arrSelectedModels.filter { $0.type == .video }.count
                    if videoCount >= config.maxVideoSelectCount, model.type == .video {
                        cell.coverView.backgroundColor = .invalidMaskColor
                        cell.coverView.isHidden = !config.showInvalidMask
                        cell.enableSelect = false
                    } else if (config.maxSelectCount - selCount) <= (config.minVideoSelectCount - videoCount), model.type != .video {
                        cell.coverView.backgroundColor = .invalidMaskColor
                        cell.coverView.isHidden = !config.showInvalidMask
                        cell.enableSelect = false
                    }
                } else if selCount > 0 {
                    cell.coverView.backgroundColor = .invalidMaskColor
                    cell.coverView.isHidden = (!config.showInvalidMask || model.type != .video)
                    cell.enableSelect = model.type != .video
                }
            } else if selCount >= config.maxSelectCount {
                cell.coverView.backgroundColor = .invalidMaskColor
                cell.coverView.isHidden = !config.showInvalidMask
                cell.enableSelect = false
            }
            if config.showSelectedBorder {
                cell.layer.borderWidth = 0
            }
        }
    }
    
    func changeCancelBtnTitle() {
        if arrSelectedModels.count > 0 {
            cancelBtn.setTitle(String(format: "%@(%ld)", localLanguageTextValue(.done), arrSelectedModels.count), for: .normal)
            cancelBtn.setTitleColor(.previewBtnHighlightTitleColor, for: .normal)
        } else {
            cancelBtn.setTitle(localLanguageTextValue(.cancel), for: .normal)
            cancelBtn.setTitleColor(.previewBtnTitleColor, for: .normal)
        }
    }
    
}


extension ZLPhotoPreviewSheet: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true) {
            let image = info[.originalImage] as? UIImage
            let url = info[.mediaURL] as? URL
            self.save(image: image, videoUrl: url)
        }
    }
    
}


extension ZLPhotoPreviewSheet: PHPhotoLibraryChangeObserver {
    
    public func photoLibraryDidChange(_ changeInstance: PHChange) {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
        ZLMainAsync {
            self.loadPhotos()
        }
    }
    
}
