//
//  ZLThumbnailImagesView.swift
//  ZLPhotoBrowser
//
//  Created by leven on 2023/3/6.
//

import Foundation
import UIKit
import SnapKit
class ZLThumbnailImagesView: UIView, UICollectionViewDelegateFlowLayout, UICollectionViewDataSource {

    var maxImageCount = 8
    
    var didClickImage: ((Int, Bool) -> Void)?
    
    var imageData: [(image: UIImage, duration: String)] = [] {
        didSet {
            collectionView.reloadData()
        }
    }
    
    lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 12
        layout.scrollDirection = .horizontal
        let view = UICollectionView(frame: CGRect.zero, collectionViewLayout: layout)
        view.dataSource = self
        view.backgroundColor = UIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1)
        view.delegate = self
        view.register(ImageCell.self, forCellWithReuseIdentifier: "ImageCell")
        return view
    }()
    
    let itemSpace: CGFloat = 0
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.addSubview(self.collectionView)
        self.collectionView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        self.collectionView.contentInset = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return self.imageData.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ImageCell", for: indexPath) as! ImageCell
        let data = imageData[indexPath.row]
        cell.updateImage(data.image, duration: data.duration)
        return cell
        
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        return itemSpace
    }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return itemSpace
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = (collectionView.frame.size.width - itemSpace * 7 - 14 * 2) / 8
        return CGSize(width: width, height: width)
    }
}

extension ZLThumbnailImagesView {
    class ImageCell: UICollectionViewCell {
        lazy var imageView = UIImageView()
        lazy var durationLabel = UILabel()
        override init(frame: CGRect) {
            super.init(frame: frame)
            createUI()
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        func createUI() {
            durationLabel.font = UIFont.systemFont(ofSize: 10)
            durationLabel.textColor = UIColor.white
            durationLabel.textAlignment = .center
            backgroundColor = UIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1)
            imageView.contentMode = .scaleAspectFill
            self.contentView.addSubview(self.imageView)
            imageView.snp.makeConstraints { make in
                make.edges.equalTo(UIEdgeInsets(top: 2, left: 2, bottom: 2, right: 2))
            }
            self.imageView.layer.cornerRadius = 2
            self.imageView.layer.masksToBounds = true
            self.layer.cornerRadius = 2
            self.layer.masksToBounds = true
            self.contentView.addSubview(self.durationLabel)
            durationLabel.snp.makeConstraints { make in
                make.left.equalTo(2)
                make.right.equalTo(-2)
                make.bottom.equalToSuperview()
                make.height.equalTo(12)
            }
        }
        
        override func layoutSubviews() {
            super.layoutSubviews()
        }
        
        func updateImage(_ image: UIImage?, duration: String?) {
            if let image = image {
                imageView.image = image
                if let duration = duration {
                    self.durationLabel.text = duration
                    self.durationLabel.isHidden = false
                } else {
                    self.durationLabel.isHidden = true
                }
            } else {
            
            }
        }
    }
}
