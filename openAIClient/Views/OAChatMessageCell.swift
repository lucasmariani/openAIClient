//
//  OAChatMessageCell.swift
//  openAIClient
//
//  Created by Lucas on 16.05.25.
//

import UIKit

class OAChatMessageCell: UITableViewCell {
    
    private let messageStackView = UIStackView()
    private let bubbleView = UIView()
    private let bubbleStackView = UIStackView()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupSubviews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupSubviews() {
        backgroundColor = .clear
        selectionStyle = .none
        
        // Configure bubble view
        bubbleView.layer.cornerRadius = 16
        bubbleView.clipsToBounds = true
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        
        // Configure bubble stack view (contains the actual content)
        bubbleStackView.axis = .vertical
        bubbleStackView.spacing = 8
        bubbleStackView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.addSubview(bubbleStackView)
        
        // Configure main message stack view (positions the bubble)
        messageStackView.axis = .vertical
        messageStackView.translatesAutoresizingMaskIntoConstraints = false
        messageStackView.addArrangedSubview(bubbleView)
        
        contentView.addSubview(messageStackView)
        
        // Constraints
        NSLayoutConstraint.activate([
            // Message stack view constraints
            messageStackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            messageStackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            messageStackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            messageStackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            // Bubble stack view constraints (content inside bubble)
            bubbleStackView.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 12),
            bubbleStackView.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -12),
            bubbleStackView.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 12),
            bubbleStackView.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12)
        ])
    }
    
    func configure(with message: OAChatMessage) {
        // Remove previous content
        bubbleStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        // Configure bubble appearance based on role
        configureBubbleAppearance(for: message.role)
        
        // Add attachments first if any
        if !message.attachments.isEmpty {
            let attachmentView = createAttachmentView(for: message.attachments)
            bubbleStackView.addArrangedSubview(attachmentView)
        }
        
        // Parse and add text content
        if !message.content.isEmpty {
            let messageViews = parseMessage(message.content, role: message.role)
            messageViews.forEach { bubbleStackView.addArrangedSubview($0) }
        }
        
        // Configure bubble alignment and width constraints
        configureBubbleAlignment(for: message.role)
    }
    
    func configure(with message: String, role: OARole) {
        let chatMessage = OAChatMessage(id: UUID().uuidString, role: role, content: message)
        configure(with: chatMessage)
    }
    
    private func configureBubbleAppearance(for role: OARole) {
        switch role {
        case .user:
            bubbleView.backgroundColor = UIColor.systemBlue
            // User messages will have white text
        case .assistant:
            bubbleView.backgroundColor = UIColor.systemGray5
            // Assistant messages will have default text color
        case .system:
            bubbleView.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.8)
            // System messages will have default text color
        }
    }
    
    private func configureBubbleAlignment(for role: OARole) {
        // Remove any existing width constraints
        bubbleView.constraints.forEach { constraint in
            if constraint.firstAttribute == .width {
                constraint.isActive = false
            }
        }
        
        switch role {
        case .user:
            // User messages: align to trailing edge, max 80% width
            messageStackView.alignment = .trailing
            NSLayoutConstraint.activate([
                bubbleView.widthAnchor.constraint(lessThanOrEqualTo: messageStackView.widthAnchor, multiplier: 0.8)
            ])
        case .assistant, .system:
            // Assistant/system messages: align to leading edge, max 90% width
            messageStackView.alignment = .leading
            NSLayoutConstraint.activate([
                bubbleView.widthAnchor.constraint(lessThanOrEqualTo: messageStackView.widthAnchor, multiplier: 0.9)
            ])
        }
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        bubbleStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        // Remove dynamic width constraints
        bubbleView.constraints.forEach { constraint in
            if constraint.firstAttribute == .width {
                constraint.isActive = false
            }
        }
    }
    
    @MainActor func parseMessage(_ message: String, role: OARole) -> [UIView] {
        var views: [UIView] = []
        let components = message.components(separatedBy: "```")
        
        for (index, component) in components.enumerated() {
            if index % 2 == 0 {
                // Regular text
                let textView = createFormattedTextView(from: component, role: role)
                if !component.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    views.append(textView)
                }
            } else {
                // Code block - detect language from first line
                let lines = component.components(separatedBy: .newlines)
                let language = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "swift"
                let code = lines.dropFirst().joined(separator: "\n")
                
                let codeView = OACodeBlockView(code: code, language: language)
                views.append(codeView)
            }
        }
        return views
    }
    
    private func createFormattedTextView(from text: String, role: OARole) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        
        // Use built-in markdown support
        let attributedString = try? NSAttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        
        if let attributedString {
            let mutableString = NSMutableAttributedString(attributedString: attributedString)
            
            // Apply role-specific color
            let color: UIColor = {
                switch role {
                case .user: return .white
                case .assistant, .system: return .label
                }
            }()
            
            mutableString.addAttribute(
                .foregroundColor,
                value: color,
                range: NSRange(location: 0, length: mutableString.length)
            )
            
            // Set Dynamic Type font
            mutableString.addAttribute(
                .font,
                value: UIFont.preferredFont(forTextStyle: .body),
                range: NSRange(location: 0, length: mutableString.length)
            )
            
            textView.attributedText = mutableString
        } else {
            // Fallback to plain text
            textView.text = text
            textView.textColor = role == .user ? .white : .label
            textView.font = UIFont.preferredFont(forTextStyle: .body)
        }
        
        return textView
    }
    
    private func createAttachmentView(for attachments: [OAAttachment]) -> UIView {
        let containerView = UIView()
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        for attachment in attachments {
            let attachmentItemView = createSingleAttachmentView(for: attachment)
            stackView.addArrangedSubview(attachmentItemView)
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
