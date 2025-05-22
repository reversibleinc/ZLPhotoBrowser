//
//  ZLPhotoMainViewController.swift
//  ZLPhotoBrowser
//
//  Created by leven on 2023/3/6.
//

import Foundation
import UIKit
import SnapKit
//import JKCategories
class ZLPhotoMainViewController: UIViewController {
    var childVCs: [(String, UIViewController)] = []
    init(childVCs: [(String, UIViewController)]) {
        self.childVCs = childVCs
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    var curChildTitle = "" {
        didSet {
            guard self.isViewLoaded else {
                return
            }
            self.refreshChaildVC()
        }
    }
    lazy var bottomStackV = UIStackView()
    override func viewDidLoad() {
        super.viewDidLoad()
        self.initUI()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let cameraVC = self.curVC as? ZLCustomCamera {
            cameraVC.showVC()
        }
    }
    var curVC: UIViewController? {
        if let vc = self.childVCs.first(where: { $0.0 == self.curChildTitle}) {
            return vc.1
        }
        return nil
    }
    
    override var prefersStatusBarHidden: Bool {
        return self.curVC is ZLCustomCamera
    }
    
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        return .fade
    }
    
    func initUI() {
        self.view.backgroundColor = UIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1)
        bottomStackV.spacing = 27
        bottomStackV.axis = .horizontal
        self.view.addSubview(self.bottomStackV)
        self.bottomStackV.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalTo(-deviceSafeAreaInsets().bottom - 20)
            make.height.equalTo(30)
        }
        
        childVCs.forEach { item in
            let itemV = TabItemView()
            itemV.label.text = item.0
            itemV.accessibilityIdentifier = item.0
            bottomStackV.addArrangedSubview(itemV)
            itemV.addTarget(self, action: #selector(didClickItem(sender:)), for: .touchUpInside)
            itemV.snp.makeConstraints { make in
                make.width.equalTo(70)
            }
        }
        self.childVCs.forEach { item in
            self.addChild(item.1)
            self.view.addSubview(item.1.view)
            item.1.view.snp.remakeConstraints { make in
                make.left.right.top.equalToSuperview()
                make.bottom.equalTo(self.bottomStackV.snp.top).offset(-20)
            }
        }

        if self.curChildTitle.count > 0 {
            self.refreshChaildVC()
        } else {
            self.curChildTitle = self.childVCs.first?.0 ?? ""
        }
    }
    
    @objc func didClickItem(sender: TabItemView) {
        self.curChildTitle = sender.accessibilityIdentifier ?? ""
    }
    
    func refreshChaildVC() {
        self.childVCs.forEach { item in
            item.1.view.isHidden = item.0 != self.curChildTitle
        }
    
        if let camera = self.childVCs.first(where: { $0.1 is ZLCustomCamera}), let vc = camera.1 as? ZLCustomCamera {
            if camera.0 == self.curChildTitle {
                vc.showVC()
                
            } else {
                vc.hideVC()
            }
        }
        self.bottomStackV.arrangedSubviews.forEach { itemV in
            if let itemV = itemV as? TabItemView {
                itemV.isCurrent = itemV.label.text == self.curChildTitle
            }
        }
        self.setNeedsStatusBarAppearanceUpdate()
    }
}
extension ZLPhotoMainViewController {
    class TabItemView: UIControl {
        lazy var bottomLine = UIView()
        lazy var label = UILabel()
        override init(frame: CGRect) {
            super.init(frame: frame)
            self.addSubview(self.bottomLine)
            self.addSubview(self.label)
            self.label.snp.makeConstraints { make in
                make.left.equalTo(3)
                make.right.equalTo(-3)
                make.top.equalTo(3)
            }
            self.bottomLine.snp.makeConstraints { make in
                make.left.right.equalTo(self.label)
                make.top.equalTo(self.label.snp.bottom).offset(8)
                make.height.equalTo(4)
            }
            self.bottomLine.backgroundColor = UIColor.white
            self.label.textColor = UIColor.white
            label.textAlignment = .center
            self.label.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        }
        
        var isCurrent: Bool = false {
            didSet {
                self.bottomLine.isHidden = isCurrent == false
                self.label.alpha = isCurrent ? 1 : 0.5
            }
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}
