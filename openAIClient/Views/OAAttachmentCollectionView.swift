//
//  OAAttachmentCollectionView.swift
//  openAIClient
//
//  Created by Claude on 15.06.25.
//

import UIKit

@MainActor
protocol OAAttachmentCollectionViewDelegate: AnyObject {
    func attachmentCollectionView(_ collectionView: OAAttachmentCollectionView, didRemoveAttachmentAt index: Int)
}

class OAAttachmentCollectionView: UIView {
    
    weak var delegate: OAAttachmentCollectionViewDelegate?
    
    private let collectionView: UICollectionView
    private var attachments: [OAAttachment] = []
    
    override init(frame: CGRect) {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 80, height: 80)
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        layout.sectionInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        
        super.init(frame: frame)
        
        setupCollectionView()
        setupConstraints()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupCollectionView() {
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(AttachmentPreviewCell.self, forCellWithReuseIdentifier: "AttachmentCell")
        
        addSubview(collectionView)
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
            collectionView.heightAnchor.constraint(equalToConstant: 96)
        ])
    }
    
    func updateAttachments(_ attachments: [OAAttachment]) {
        self.attachments = attachments
        collectionView.reloadData()
        isHidden = attachments.isEmpty
    }
}

extension OAAttachmentCollectionView: UICollectionViewDataSource, UICollectionViewDelegate {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return attachments.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "AttachmentCell", for: indexPath) as! AttachmentPreviewCell
        let attachment = attachments[indexPath.item]
        cell.configure(with: attachment)
        cell.onRemove = { [weak self] in
            self?.delegate?.attachmentCollectionView(self!, didRemoveAttachmentAt: indexPath.item)
        }
        return cell
    }
}

private class AttachmentPreviewCell: UICollectionViewCell {
    
    var onRemove: (() -> Void)?
    
    private let imageView = UIImageView()
    private let nameLabel = UILabel()
    private let removeButton = UIButton(type: .system)
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        contentView.layer.cornerRadius = 8
        contentView.layer.borderWidth = 1
        contentView.layer.borderColor = UIColor.systemGray4.cgColor
        contentView.backgroundColor = .systemGray6
        
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 4
        contentView.addSubview(imageView)
        
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(ofSize: 10)
        nameLabel.textColor = .secondaryLabel
        nameLabel.textAlignment = .center
        nameLabel.numberOfLines = 2
        contentView.addSubview(nameLabel)
        
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        removeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        removeButton.tintColor = .systemRed
        removeButton.backgroundColor = .systemBackground
        removeButton.layer.cornerRadius = 10
        removeButton.addTarget(self, action: #selector(removeButtonTapped), for: .touchUpInside)
        contentView.addSubview(removeButton)
        
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            imageView.heightAnchor.constraint(equalToConstant: 50),
            
            nameLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 2),
            nameLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 2),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -2),
            nameLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -2),
            
            removeButton.topAnchor.constraint(equalTo: contentView.topAnchor, constant: -5),
            removeButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: 5),
            removeButton.widthAnchor.constraint(equalToConstant: 20),
            removeButton.heightAnchor.constraint(equalToConstant: 20)
        ])
    }
    
    func configure(with attachment: OAAttachment) {
        nameLabel.text = attachment.filename
        
        if attachment.isImage {
            if let thumbnailData = attachment.thumbnailData,
               let thumbnail = UIImage(data: thumbnailData) {
                imageView.image = thumbnail
            } else if let image = UIImage(data: attachment.data) {
                imageView.image = image
            } else {
                imageView.image = UIImage(systemName: "photo")
            }
        } else {
            imageView.image = UIImage(systemName: "doc.fill")
            imageView.tintColor = .systemBlue
        }
    }
    
    @objc private func removeButtonTapped() {
        onRemove?()
    }
}