//
//  ZLImageNavController.swift
//  ZLPhotoBrowser
//
//  Created by long on 2020/8/18.
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
import PanModal

public class ZLImageNavController: UINavigationController {

    var isSelectedOriginal: Bool = false
    
    var arrSelectedModels: [ZLPhotoModel] = []
    
    var selectImageBlock: ( () -> Void )?
    
    var cancelBlock: ( () -> Void )?
    
    deinit {
        zl_debugPrint("ZLImageNavController deinit")
    }
    
    public override var preferredStatusBarStyle: UIStatusBarStyle {
        return ZLPhotoConfiguration.default().statusBarStyle
    }
    
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nil, bundle: nil)
    }
    
    override init(rootViewController: UIViewController) {
        super.init(rootViewController: rootViewController)
        self.navigationBar.barStyle = .black
        self.navigationBar.isTranslucent = true
        self.modalPresentationStyle = .fullScreen
        self.isNavigationBarHidden = true
        
        let colorDeploy = ZLPhotoConfiguration.default().themeColorDeploy
        self.navigationBar.setBackgroundImage(self.image(color: colorDeploy.navBarColor), for: .default)
        self.navigationBar.tintColor = colorDeploy.navTitleColor
        self.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: colorDeploy.navTitleColor]
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }
    
    func image(color: UIColor) -> UIImage? {
        let rect = CGRect(x: 0, y: 0, width: 1, height: 1)
        UIGraphicsBeginImageContext(rect.size)
        let context = UIGraphicsGetCurrentContext()
        context?.setFillColor(color.cgColor)
        context?.fill(rect)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image
    }

}

extension ZLImageNavController: PanModalPresentable {
    
    public var panScrollable: UIScrollView? {
        return (topViewController as? PanModalPresentable)?.panScrollable
    }
    
    public var allowsDragToDismiss: Bool {
        return (topViewController as? PanModalPresentable)?.allowsDragToDismiss ?? true
    }
    public var allowsExtendedPanScrolling: Bool {
        return (topViewController as? PanModalPresentable)?.allowsExtendedPanScrolling ?? true
    }

    public var shouldRoundTopCorners: Bool {
        return (topViewController as? PanModalPresentable)?.shouldRoundTopCorners ?? true
    }

    public var showDragIndicator: Bool {
        return (topViewController as? PanModalPresentable)?.showDragIndicator ?? false

    }
    
    public var cornerRadius: CGFloat {
        return (topViewController as? PanModalPresentable)?.cornerRadius ?? 20
    }

    public var longFormHeight: PanModalHeight {
        // intrinsicHeight 15.X系统会有问题
        if let height = (topViewController as? PanModalPresentable)?.longFormHeight {
            return height
        }
        if #available(iOS 15.0, *) {
            return .maxHeight
        } else {
            return .intrinsicHeight
        }
    }
    public var shortFormHeight: PanModalHeight {
        if let height = (topViewController as? PanModalPresentable)?.shortFormHeight {
            return height
        }
        return longFormHeight
    }
}

