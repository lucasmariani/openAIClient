//
//  AttachmentSegmentRenderer.swift
//  openAIClient
//
//  Created by Lucas on 02.07.25.
//

import UIKit

/// Renderer for attachment segments
@MainActor
final class AttachmentSegmentRenderer: BaseContentSegmentRenderer {
    init() {
        super.init(segmentType: "attachments")
    }
    
    override func createView(for segment: ContentSegment) -> UIView {
        guard case .attachments(let attachments) = segment else {
            return UIView()
        }
        
        return createAttachmentStackView(for: attachments)
    }
    
    override func updateView(_ view: UIView, with segment: ContentSegment) -> Bool {
        // Attachments don't support in-place updates
        return false
    }
    
    private func createAttachmentStackView(for attachments: [OAAttachment]) -> UIView {
        let containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        for attachment in attachments {
            let attachmentView = createSingleAttachmentView(for: attachment)
            stackView.addArrangedSubview(attachmentView)
        }
        
        containerView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: containerView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor)
        ])
        
        return containerView
    }
    
    private func createSingleAttachmentView(for attachment: OAAttachment) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.9)
        containerView.layer.cornerRadius = 8
        containerView.layer.borderWidth = 1
        containerView.layer.borderColor = UIColor.systemGray4.cgColor
        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        if attachment.isImage {
            return createImageAttachmentView(for: attachment, in: containerView)
        } else {
            return createDocumentAttachmentView(for: attachment, in: containerView)
        }
    }
    
    private func createImageAttachmentView(for attachment: OAAttachment, in containerView: UIView) -> UIView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 8
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        if let image = UIImage(data: attachment.data) {
            imageView.image = image
        }
        
        containerView.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
            imageView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -8),
            imageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
            imageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
            imageView.heightAnchor.constraint(lessThanOrEqualToConstant: 200),
            imageView.widthAnchor.constraint(lessThanOrEqualToConstant: 200)
        ])
        
        return containerView
    }
    
    private func createDocumentAttachmentView(for attachment: OAAttachment, in containerView: UIView) -> UIView {
        let iconImageView = UIImageView()
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.image = UIImage(systemName: "doc.fill")
        iconImageView.tintColor = .systemBlue
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        
        let nameLabel = UILabel()
        nameLabel.text = attachment.filename
        nameLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        nameLabel.numberOfLines = 2
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let sizeLabel = UILabel()
        sizeLabel.text = attachment.sizeString
        sizeLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        sizeLabel.textColor = .secondaryLabel
        sizeLabel.translatesAutoresizingMaskIntoConstraints = false
        
        containerView.addSubview(iconImageView)
        containerView.addSubview(nameLabel)
        containerView.addSubview(sizeLabel)
        
        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            iconImageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 32),
            iconImageView.heightAnchor.constraint(equalToConstant: 32),
            
            nameLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 12),
            nameLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
            nameLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            
            sizeLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            sizeLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            sizeLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            sizeLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -8)
        ])
        
        return containerView
    }
}

/// Renderer for generated image segments
@MainActor
final class GeneratedImageSegmentRenderer: BaseContentSegmentRenderer {
    init() {
        super.init(segmentType: "generatedImages")
    }
    
    override func createView(for segment: ContentSegment) -> UIView {
        guard case .generatedImages(let imageDatas) = segment else {
            return UIView()
        }
        
        return createGeneratedImagesView(from: imageDatas)
    }
    
    override func updateView(_ view: UIView, with segment: ContentSegment) -> Bool {
        // Generated images don't support in-place updates
        return false
    }
    
    private func createGeneratedImagesView(from imageDataArray: [Data]) -> UIView {
        let containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        for imageData in imageDataArray {
            if let image = UIImage(data: imageData) {
                let imageView = createGeneratedImageView(with: image)
                stackView.addArrangedSubview(imageView)
            }
        }
        
        containerView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: containerView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor)
        ])
        
        return containerView
    }
    
    private func createGeneratedImageView(with image: UIImage) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.1)
        containerView.layer.cornerRadius = 12
        containerView.clipsToBounds = true
        containerView.translatesAutoresizingMaskIntoConstraints = false
        
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 8
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        containerView.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
            imageView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -8),
            imageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
            imageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
            imageView.heightAnchor.constraint(lessThanOrEqualToConstant: 300),
            imageView.widthAnchor.constraint(lessThanOrEqualToConstant: 300)
        ])
        
        return containerView
    }
}